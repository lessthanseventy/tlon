defmodule Server.MCP.OperatorAPI do
  @moduledoc """
  The operator's door over loopback HTTP — `/api/*` on the same Bandit as `/mcp` and `/mint`
  (one-brain decision 5: one port family). Plain JSON, and every route is a thin caller of a
  `Server.*` context (decision 1: the API IS the contexts — a client that needs a new read gets a
  context function first, then a route here). Same trust stance as `/mint`: loopback,
  unauthenticated by design. First client: asterion's tlon.nvim (master plan piece B); the web
  UI (piece D) is the next.

      GET  /api/sidebar                 Board.sidebar
      GET  /api/roster                  Staff.roster
      GET  /api/threads/:id             Board.brief |> Brief.scope   (what get_dossier gives an agent)
      GET  /api/threads/:id/messages    Channel.recent_messages (?limit=, default 50)
      GET  /api/threads/:id/terminal    where its coworker runs: {socket, session, window}, 404 if none
      POST /api/threads/:id/messages    {"body"} → Attention.respond as the operator: answers an open
                                        prompt, reopens a closed thread, else posts; 201 + the message
      POST /api/threads/:id/close       Channel.close_thread: its sessions end, its ticket is done
      GET  /api/office                  Office.status (every workspace: roster, benches, threads, …)
      GET  /api/office/threads/:id      Office.thread_view (last messages + what its pane shows)
      POST /api/tickets                 {"workspace_id", "title", "project_id"?, "body"?} → Tickets.file; 201
      POST /api/tickets/:id/route       Tickets.route: to the workspace's manager (no manager: its lead starts it)
      POST /api/tickets/:id/start       {"agent_id"?} → Tickets.start_thread (default: the lead); 201 + the thread
  """

  import Plug.Conn

  alias Server.Arbiter.Tmux
  alias Server.Board
  alias Server.Channel
  alias Server.MCP.Brief
  alias Server.Office
  alias Server.Repo
  alias Server.Staff
  alias Server.Thread
  alias Server.Tickets

  @spec call(Plug.Conn.t(), [String.t()]) :: Plug.Conn.t()
  def call(conn, path) do
    case {conn.method, path} do
      {"GET", ["sidebar"]} -> json(conn, 200, Board.sidebar())
      {"GET", ["roster"]} -> json(conn, 200, Enum.map(Staff.roster(), &roster_row/1))
      {method, ["threads", id | rest]} -> with_thread(conn, id, &on_thread(conn, method, rest, &1))
      {"GET", ["office"]} -> json(conn, 200, Office.status())
      {"GET", ["office", "threads", id]} -> with_thread(conn, id, &json(conn, 200, Office.thread_view(&1)))
      {method, ["tickets" | rest]} -> on_tickets(conn, method, rest)
      _ -> no_route(conn)
    end
  end

  defp on_thread(conn, "GET", [], t), do: json(conn, 200, t |> Board.brief() |> Brief.scope())
  defp on_thread(conn, "GET", ["messages"], t), do: messages(conn, t)
  defp on_thread(conn, "GET", ["terminal"], t), do: terminal(conn, t)
  defp on_thread(conn, "POST", ["messages"], t), do: post(conn, t)
  defp on_thread(conn, "POST", ["close"], t), do: close(conn, t)
  defp on_thread(conn, _, _, _), do: no_route(conn)

  defp on_tickets(conn, "POST", []), do: file_ticket(conn)
  defp on_tickets(conn, "POST", [id, "route"]), do: with_ticket(conn, id, &route(conn, &1))
  defp on_tickets(conn, "POST", [id, "start"]), do: with_ticket(conn, id, &start(conn, &1))
  defp on_tickets(conn, _, _), do: no_route(conn)

  defp no_route(conn), do: json(conn, 404, %{error: "no such route"})

  defp messages(conn, thread) do
    limit =
      case Integer.parse(fetch_query_params(conn).query_params["limit"] || "") do
        {n, ""} when n > 0 -> n
        _ -> 50
      end

    json(conn, 200, thread |> Channel.recent_messages(limit) |> Enum.map(&Brief.message/1))
  end

  # Where the thread's coworker runs, for a client that attaches (asterion): the tmux socket,
  # session and window — resolved by the server, so no client derives the naming. 404 = no window.
  defp terminal(conn, thread) do
    case Tmux.terminal_target(thread) do
      nil -> json(conn, 404, %{error: "thread #{thread.id} has no live terminal"})
      target -> json(conn, 200, target)
    end
  end

  # Post as the operator through the one door (`Server.Attention.respond/3`, the same call the
  # console reply box and `server:post` make): a body naming an option of an open prompt answers
  # the coworker's dialog in its pane (the 201 carries `reply_to` = the prompt), a closed thread
  # reopens, anything else posts and the Bus wakes the thread's lead. `author` is not a
  # parameter: this door IS the operator.
  defp post(conn, thread) do
    with {:ok, raw, conn} <- read_body(conn),
         {:ok, %{"body" => body}} when is_binary(body) and body != "" <- JSON.decode(raw),
         {:ok, message} <- Server.Attention.respond(thread.id, operator(), body) do
      json(conn, 201, Brief.message(message))
    else
      _ -> json(conn, 400, %{error: ~s(expected {"body": "…"})})
    end
  end

  defp close(conn, thread) do
    case Channel.close_thread(thread) do
      {:ok, t} -> json(conn, 200, %{id: t.id, title: t.title, state: t.state})
      {:error, why} -> json(conn, 409, %{error: inspect(why)})
    end
  end

  defp file_ticket(conn) do
    with {:ok, raw, conn} <- read_body(conn),
         {:ok, %{"workspace_id" => ws, "title" => title} = b} when is_integer(ws) and is_binary(title) <-
           JSON.decode(raw),
         {:ok, t} <- Tickets.file(%{workspace_id: ws, title: title, project_id: b["project_id"], body: b["body"] || ""}) do
      json(conn, 201, ticket(t))
    else
      _ -> json(conn, 400, %{error: ~s(expected {"workspace_id": n, "title": "…"})})
    end
  end

  defp route(conn, t) do
    case Tickets.route(t) do
      {:ok, %{routed_to: m}} -> json(conn, 200, %{ticket: t.id, routed_to: m})
      {:ok, %{started: th}} -> json(conn, 201, %{ticket: t.id, thread: th.id})
      {:error, why} -> json(conn, 409, %{error: inspect(why)})
    end
  end

  defp start(conn, t) do
    case Tickets.start_thread(t, agent_of(conn)) do
      {:ok, th} -> json(conn, 201, %{ticket: t.id, thread: th.id})
      {:error, why} -> json(conn, 409, %{error: inspect(why)})
    end
  end

  # the coworker to hand a started ticket to, from the body; nil (the lead) when it names none
  defp agent_of(conn) do
    with {:ok, raw, _} <- read_body(conn),
         {:ok, %{"agent_id" => a}} when is_integer(a) <- JSON.decode(raw) do
      a
    else
      _ -> nil
    end
  end

  defp with_ticket(conn, id, fun) do
    with {n, ""} <- Integer.parse(id),
         %Server.Ticket{} = t <- Tickets.get(n) do
      fun.(t)
    else
      _ -> json(conn, 404, %{error: "no ticket #{id}"})
    end
  end

  defp ticket(t), do: %{id: t.id, workspace_id: t.workspace_id, title: t.title, status: t.status, priority: t.priority}

  defp with_thread(conn, id, fun) do
    with {n, ""} <- Integer.parse(id),
         %Thread{} = thread <- Repo.get(Thread, n) do
      fun.(thread)
    else
      _ -> json(conn, 404, %{error: "no thread #{id}"})
    end
  end

  defp roster_row(r) do
    %{
      agent: r.agent,
      thread_id: r.thread_id,
      thread_title: r.thread_title,
      pane_ref: r.pane_ref,
      last_active_at: r.last_active_at,
      warm: r.warm?
    }
  end

  defp operator, do: Application.get_env(:server, :operator, "andrew")

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
    |> halt()
  end
end
