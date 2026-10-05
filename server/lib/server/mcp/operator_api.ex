defmodule Server.MCP.OperatorAPI do
  @moduledoc """
  The operator's door over loopback HTTP — `/api/*` on the same Bandit as `/mcp` and `/mint`
  (one-brain decision 5: one port family). Plain JSON, and every route is a thin caller of a
  `Server.*` context (decision 1: the API IS the contexts — a client that needs a new read or write
  gets a context function first, then a route here; `scripts/tlon-cli.sh` calls the same
  functions). Same trust stance as `/mint`: loopback, unauthenticated by design. Clients:
  asterion's tlon.nvim, the desktop office, the office TUI.

      GET    /api/sidebar                 Board.sidebar
      GET    /api/roster                  Staff.roster
      GET    /api/office                  Office.status (every workspace: roster, benches, threads, …)
      GET    /api/office/threads/:id      Office.thread_view (last messages + what its pane shows)

      GET    /api/threads/:id             Board.brief |> Brief.scope   (what get_dossier gives an agent)
      GET    /api/threads/:id/messages    Channel.recent_messages (?limit=, default 50)
      GET    /api/threads/:id/terminal    where its coworker runs: {socket, session, window}, 404 if none
      GET    /api/threads/:id/worktree    its coworker's working dir: {path} (the per-thread git worktree, ensured), 404 if no repo
      POST   /api/threads/:id/messages    {"body"} → Attention.respond as the operator: answers an open
                                          prompt, reopens a closed thread, else posts; 201 + the message
      POST   /api/threads/:id/close       Channel.close_thread: its sessions end, its ticket is done
      POST   /api/threads/:id/hand-off    {"agent"} → Staffing.hand_off (staffed now where Oban runs)
      POST   /api/threads/:id/advance     Workline.advance (409 when it can't: not a workline, gated, …)
      POST   /api/threads/:id/approve     Workline.approve: complete its parked gate
      POST   /api/threads/:id/track       Workline.promote: make a plain thread a workline
      POST   /api/threads/:id/checks      {"slug", "exit", "cmd", "tail"?} → Dossier.record_check (the verify stage's evidence)
      DELETE /api/threads/:id             Channel.delete_thread (the root machine thread is refused)
      POST   /api/worklines               {"title", "slug"} → Workline.open at intent; 201

      POST   /api/tickets                 {"workspace_id", "title", "project_id"?, "body"?} → Tickets.file; 201
      PATCH  /api/tickets/:id             {"status"?, "title"?, "body"?} → Tickets.update
      DELETE /api/tickets/:id             Tickets.remove
      POST   /api/tickets/:id/route       Tickets.route: to the workspace's manager (no manager: its lead starts it)
      POST   /api/tickets/:id/start       {"agent_id"?} → Tickets.start_thread (default: the lead); 201 + the thread

      POST   /api/workspaces              {"name", "repo"?} → Workspaces.register; 201
      DELETE /api/workspaces/:id          Workspaces.remove (its threads move on; the last is refused)
      POST   /api/workspaces/:id/coworkers  {"name", "archetype", "model"?, "effort"?, "ask"?} → seat + retarget; 201
      PATCH  /api/workspaces/:id/coworkers/:agent_id  {"model"?, "effort"?, "ask"?} → Workspaces.retarget
                                          ("inherit" puts a knob back to the archetype's; absent leaves it)
      POST   /api/workspaces/:id/coworkers/:agent_id/aside  {"question"} → Office.aside_spec: the
                                          command to run and where — the CALLER runs it
      DELETE /api/seats/:id               Workspaces.unseat (the agent itself survives)
      DELETE /api/facts/:id               Dossier.forget_fact (a tombstone: out of recall, row kept)
      POST   /api/issues/:id/resolve      {"resolution"?} → Dossier.resolve_issue
  """

  import Plug.Conn

  alias Server.Arbiter.Tmux
  alias Server.Board
  alias Server.Channel
  alias Server.Dossier
  alias Server.MCP.Brief
  alias Server.Office
  alias Server.Repo
  alias Server.Staff
  alias Server.Thread
  alias Server.Tickets
  alias Server.Workline
  alias Server.Workspaces

  @spec call(Plug.Conn.t(), [String.t()]) :: Plug.Conn.t()
  def call(conn, [resource | rest]), do: route(conn, conn.method, resource, rest)
  def call(conn, []), do: no_route(conn)

  defp route(conn, "GET", "sidebar", []), do: json(conn, 200, Board.sidebar())
  defp route(conn, "GET", "roster", []), do: json(conn, 200, Enum.map(Staff.roster(), &roster_row/1))
  defp route(conn, "GET", "office", []), do: json(conn, 200, Office.status())

  defp route(conn, "GET", "office", ["threads", id]),
    do: with_thread(conn, id, &json(conn, 200, Office.thread_view(&1)))

  defp route(conn, method, "threads", [id | rest]), do: with_thread(conn, id, &on_thread(conn, method, rest, &1))
  defp route(conn, "POST", "worklines", []), do: open_workline(conn)
  defp route(conn, method, "tickets", rest), do: on_tickets(conn, method, rest)
  defp route(conn, method, "workspaces", rest), do: on_workspaces(conn, method, rest)
  defp route(conn, "DELETE", "seats", [id]), do: with_int(conn, id, &fire(conn, &1))
  defp route(conn, "DELETE", "facts", [id]), do: with_row(conn, Server.Fact, id, &forget(conn, &1))
  defp route(conn, "POST", "issues", [id, "resolve"]), do: with_row(conn, Server.Issue, id, &resolve(conn, &1))
  defp route(conn, _, _, _), do: no_route(conn)

  defp on_thread(conn, "GET", [], t), do: json(conn, 200, t |> Board.brief() |> Brief.scope())
  defp on_thread(conn, "GET", ["messages"], t), do: messages(conn, t)
  defp on_thread(conn, "GET", ["terminal"], t), do: terminal(conn, t)
  defp on_thread(conn, "GET", ["worktree"], t), do: worktree(conn, t)
  defp on_thread(conn, "POST", ["messages"], t), do: post(conn, t)
  defp on_thread(conn, "POST", ["close"], t), do: reply(conn, Channel.close_thread(t), &thread_row/1)
  defp on_thread(conn, "POST", ["hand-off"], t), do: hand_off(conn, t)
  defp on_thread(conn, "POST", ["advance"], t), do: reply(conn, Workline.advance(t), &thread_row/1)
  defp on_thread(conn, "POST", ["approve"], t), do: reply(conn, Workline.approve(t), &thread_row/1)
  defp on_thread(conn, "POST", ["track"], t), do: reply(conn, Workline.promote(t), &thread_row/1)
  defp on_thread(conn, "POST", ["checks"], t), do: record_check(conn, t)
  defp on_thread(conn, "DELETE", [], t), do: reply(conn, Channel.delete_thread(t), fn _ -> %{deleted: t.id} end)
  defp on_thread(conn, _, _, _), do: no_route(conn)

  defp on_tickets(conn, "POST", []), do: file_ticket(conn)
  defp on_tickets(conn, "PATCH", [id]), do: with_ticket(conn, id, &update_ticket(conn, &1))

  defp on_tickets(conn, "DELETE", [id]),
    do: with_ticket(conn, id, &reply(conn, Tickets.remove(&1), fn _ -> %{deleted: &1.id} end))

  defp on_tickets(conn, "POST", [id, "route"]), do: with_ticket(conn, id, &route_ticket(conn, &1))
  defp on_tickets(conn, "POST", [id, "start"]), do: with_ticket(conn, id, &start(conn, &1))
  defp on_tickets(conn, _, _), do: no_route(conn)

  defp on_workspaces(conn, "POST", []), do: new_workspace(conn)

  defp on_workspaces(conn, "DELETE", [id]),
    do: with_workspace(conn, id, &reply(conn, Workspaces.remove(&1), fn w -> %{deleted: w.id} end))

  defp on_workspaces(conn, "POST", [id, "coworkers"]), do: with_workspace(conn, id, &hire(conn, &1))

  defp on_workspaces(conn, "PATCH", [id, "coworkers", a]),
    do: with_workspace(conn, id, &with_int(conn, a, fn agent -> retarget(conn, &1, agent) end))

  defp on_workspaces(conn, "POST", [id, "coworkers", a, "aside"]),
    do: with_workspace(conn, id, &with_int(conn, a, fn agent -> aside(conn, &1, agent) end))

  defp on_workspaces(conn, _, _), do: no_route(conn)

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

  # The thread's coworker's working dir (its per-thread worktree, created on first ask), for a client
  # that runs something there (the office's lazygit). 404 = the thread has no repo.
  defp worktree(conn, thread) do
    case Server.worktree_for_thread(thread) do
      {:ok, path} -> json(conn, 200, %{path: path})
      {:error, reason} -> json(conn, 404, %{error: "thread #{thread.id} has no worktree: #{inspect(reason)}"})
    end
  end

  # Post as the operator through the one door (`Server.Attention.respond/3`, the same call the
  # console reply box and `server:post` make): a body naming an option of an open prompt answers
  # the coworker's dialog in its pane (the 201 carries `reply_to` = the prompt), a closed thread
  # reopens, anything else posts and the Bus wakes the thread's lead. `author` is not a
  # parameter: this door IS the operator.
  defp post(conn, thread) do
    case body(conn) do
      {%{"body" => body}, conn} when is_binary(body) and body != "" ->
        case Server.Attention.respond(thread.id, operator(), body) do
          {:ok, message} -> json(conn, 201, Brief.message(message))
          {:error, why} -> json(conn, 409, %{error: inspect(why)})
        end

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"body": "…"})})
    end
  end

  # Staff the thread now rather than at the next pass — where staffing runs (Oban: the service, the
  # standalone binary); a node without it (a test, a dev shell) leaves it to the next pass there.
  defp hand_off(conn, thread) do
    with {%{"agent" => handle}, conn} when is_binary(handle) and handle != "" <- body(conn),
         {:ok, t} <- Server.Staffing.hand_off(thread.id, handle) do
      staff_now(t.workspace_id)
      json(conn, 200, %{id: t.id, lead: handle})
    else
      {:error, why} -> refused(conn, why)
      {_, conn} -> json(conn, 400, %{error: ~s(expected {"agent": "name"})})
    end
  end

  defp staff_now(ws),
    do: if(Application.get_env(:server, :start_oban), do: Task.start(fn -> Server.Staffing.pass(ws) end))

  defp record_check(conn, thread) do
    case body(conn) do
      {%{"slug" => slug, "exit" => code, "cmd" => cmd} = b, conn}
      when is_binary(slug) and is_integer(code) and is_binary(cmd) ->
        attrs = %{
          thread_id: thread.id,
          cmd: cmd,
          exit: code,
          tail: b["tail"] || "",
          correlation: "workline:#{slug}:verify"
        }

        reply(conn, Dossier.record_check(attrs), &%{id: &1.id, kind: &1.kind}, 201)

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"slug", "exit": n, "cmd"})})
    end
  end

  defp open_workline(conn) do
    case body(conn) do
      {%{"title" => title, "slug" => slug}, conn} when is_binary(title) and is_binary(slug) ->
        reply(conn, Workline.open(%{title: title, slug: slug}), &thread_row/1, 201)

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"title", "slug"})})
    end
  end

  defp file_ticket(conn) do
    case body(conn) do
      {%{"workspace_id" => ws, "title" => title} = b, conn} when is_integer(ws) and is_binary(title) ->
        reply(
          conn,
          Tickets.file(%{workspace_id: ws, title: title, project_id: b["project_id"], body: b["body"] || ""}),
          &ticket/1,
          201
        )

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"workspace_id": n, "title": "…"})})
    end
  end

  defp update_ticket(conn, t) do
    {b, conn} = body(conn)
    attrs = for {k, v} <- b, k in ~w(status title body), is_binary(v), into: %{}, do: {String.to_existing_atom(k), v}

    if attrs == %{},
      do: json(conn, 400, %{error: ~s(expected some of {"status", "title", "body"})}),
      else: reply(conn, Tickets.update(t, attrs), &ticket/1)
  end

  defp route_ticket(conn, t) do
    case Tickets.route(t) do
      {:ok, %{routed_to: m}} -> json(conn, 200, %{ticket: t.id, routed_to: m})
      {:ok, %{started: th}} -> json(conn, 201, %{ticket: t.id, thread: th.id})
      {:error, why} -> json(conn, 409, %{error: inspect(why)})
    end
  end

  defp start(conn, t) do
    {b, conn} = body(conn)
    agent = if is_integer(b["agent_id"]), do: b["agent_id"]
    reply(conn, Tickets.start_thread(t, agent), &%{ticket: t.id, thread: &1.id}, 201)
  end

  defp new_workspace(conn) do
    case body(conn) do
      {%{"name" => name} = b, conn} when is_binary(name) and name != "" ->
        repos = if is_binary(b["repo"]) and b["repo"] != "", do: [b["repo"]], else: []
        reply(conn, Workspaces.register(%{name: name, repos: repos}), &%{id: &1.id, name: &1.name}, 201)

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"name", "repo"?})})
    end
  end

  # seat a new coworker, then its knobs if any were given — one request, as the CLI's `hire`
  defp hire(conn, ws) do
    case body(conn) do
      {%{"name" => name, "archetype" => arch} = b, conn} when is_binary(name) and is_binary(arch) ->
        with {:ok, c} <- Workspaces.seat(ws.id, %{name: name, archetype: arch}),
             {:ok, _} <- Workspaces.retarget(ws.id, c.agent_id, knobs(b)) do
          json(conn, 201, %{seat_id: c.id, agent_id: c.agent_id, name: c.name, archetype: c.archetype})
        else
          {:error, why} -> refused(conn, why)
        end

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"name", "archetype"})})
    end
  end

  defp retarget(conn, ws, agent) do
    {b, conn} = body(conn)
    reply(conn, Workspaces.retarget(ws.id, agent, knobs(b)), &policy_row/1)
  end

  defp aside(conn, ws, agent) do
    case body(conn) do
      {%{"question" => q}, conn} when is_binary(q) and q != "" -> reply(conn, Office.aside_spec(ws.id, agent, q), & &1)
      {_, conn} -> json(conn, 400, %{error: ~s(expected {"question"})})
    end
  end

  defp fire(conn, seat_id), do: reply(conn, Workspaces.unseat(seat_id), fn _ -> %{unseated: seat_id} end)
  defp forget(conn, fact), do: reply(conn, Dossier.forget_fact(fact), fn _ -> %{forgot: fact.id} end)

  defp resolve(conn, issue) do
    {b, conn} = body(conn)
    res = if is_binary(b["resolution"]), do: b["resolution"]
    reply(conn, Dossier.resolve_issue(issue, res), fn _ -> %{resolved: issue.id} end)
  end

  # a coworker's knobs from a request body: a value sets, "inherit" puts back, absent leaves
  defp knobs(b) do
    inherit = fn
      "inherit" -> :inherit
      v -> v
    end

    %{model: inherit.(b["model"]), effort: b["effort"], ask: inherit.(b["ask"])}
  end

  # a context's {:ok, x} as `status` + `render.(x)`; its {:error, …} as 409 (a refusal) or 422 (bad input)
  defp reply(conn, result, render, status \\ 200)
  defp reply(conn, {:ok, x}, render, status), do: json(conn, status, render.(x))
  defp reply(conn, {:awaiting, x}, render, _), do: json(conn, 202, Map.put(render.(x), :gated, true))
  defp reply(conn, {:error, why}, _, _), do: refused(conn, why)

  defp refused(conn, %Ecto.Changeset{} = cs), do: json(conn, 422, %{error: inspect(cs.errors)})
  defp refused(conn, :unknown_model), do: json(conn, 422, %{error: "no such model"})
  defp refused(conn, :not_found), do: json(conn, 404, %{error: "not found"})
  defp refused(conn, why), do: json(conn, 409, %{error: inspect(why)})

  # the request body as a map (empty when there is none or it isn't a JSON object)
  defp body(conn) do
    case read_body(conn) do
      {:ok, raw, conn} ->
        case JSON.decode(raw) do
          {:ok, %{} = m} -> {m, conn}
          _ -> {%{}, conn}
        end

      _ ->
        {%{}, conn}
    end
  end

  defp with_thread(conn, id, fun), do: with_row(conn, Thread, id, fun)

  defp with_ticket(conn, id, fun),
    do: with_int(conn, id, &if(t = Tickets.get(&1), do: fun.(t), else: not_found(conn, "ticket", id)))

  defp with_workspace(conn, id, fun),
    do: with_int(conn, id, &if(w = Workspaces.get(&1), do: fun.(w), else: not_found(conn, "workspace", id)))

  defp with_row(conn, schema, id, fun) do
    with_int(conn, id, fn n ->
      case Repo.get(schema, n) do
        nil -> not_found(conn, schema |> Module.split() |> List.last() |> String.downcase(), id)
        row -> fun.(row)
      end
    end)
  end

  defp with_int(conn, id, fun) do
    case Integer.parse(id) do
      {n, ""} -> fun.(n)
      _ -> json(conn, 404, %{error: "no such id #{id}"})
    end
  end

  defp not_found(conn, what, id), do: json(conn, 404, %{error: "no #{what} #{id}"})

  defp thread_row(t), do: %{id: t.id, title: t.title, state: t.state, stage: t.stage, awaiting: t.awaiting}
  defp ticket(t), do: %{id: t.id, workspace_id: t.workspace_id, title: t.title, status: t.status, priority: t.priority}
  defp policy_row(nil), do: %{model: nil, ask: nil}
  defp policy_row(p), do: %{model: p.model, ask: p.ask_default}

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
