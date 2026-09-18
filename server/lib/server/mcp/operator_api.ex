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
      POST /api/threads/:id/messages    {"body"} → Channel.post as the operator; 201 + the message
  """

  import Plug.Conn

  alias Server.Board
  alias Server.Channel
  alias Server.MCP.Brief
  alias Server.Repo
  alias Server.Staff
  alias Server.Thread

  @spec call(Plug.Conn.t(), [String.t()]) :: Plug.Conn.t()
  def call(conn, path) do
    case {conn.method, path} do
      {"GET", ["sidebar"]} -> json(conn, 200, Board.sidebar())
      {"GET", ["roster"]} -> json(conn, 200, Enum.map(Staff.roster(), &roster_row/1))
      {"GET", ["threads", id]} -> with_thread(conn, id, &json(conn, 200, &1 |> Board.brief() |> Brief.scope()))
      {"GET", ["threads", id, "messages"]} -> with_thread(conn, id, &messages(conn, &1))
      {"POST", ["threads", id, "messages"]} -> with_thread(conn, id, &post(conn, &1))
      _ -> json(conn, 404, %{error: "no such route"})
    end
  end

  defp messages(conn, thread) do
    limit =
      case Integer.parse(fetch_query_params(conn).query_params["limit"] || "") do
        {n, ""} when n > 0 -> n
        _ -> 50
      end

    json(conn, 200, thread |> Channel.recent_messages(limit) |> Enum.map(&Brief.message/1))
  end

  # Post as the operator — the same call `server:post` makes; Channel.post's Bus broadcast is
  # what wakes the thread's lead. `author` is not a parameter: this door IS the operator.
  defp post(conn, thread) do
    with {:ok, raw, conn} <- read_body(conn),
         {:ok, %{"body" => body}} when is_binary(body) and body != "" <- JSON.decode(raw),
         {:ok, message} <- Channel.post(%{thread_id: thread.id, author: operator(), body: body}) do
      json(conn, 201, Brief.message(message))
    else
      _ -> json(conn, 400, %{error: ~s(expected {"body": "…"})})
    end
  end

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
