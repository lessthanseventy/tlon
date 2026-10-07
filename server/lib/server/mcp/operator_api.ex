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
      GET    /api/office/threads/:id      Office.thread_view (a page of messages, ?before=<id> for older, + what its pane shows)
      GET    /api/office/archive/:ws      Office.archive (a workspace's done tickets + closed threads)
      GET    /api/office/banter/:ws       Office.Banter.lines (recent small talk; asking may write the next line)
      GET    /api/office/pets/:ws         Office.Pets.voices (the pets' lines by occasion; asking may write a batch)
      GET    /api/office/corkboard/:ws    Office.Corkboard.notes (the coworkers' notes to each other; asking may pin the next)
      GET    /api/office/focus            Office.Focus.latest (the newest "show thread N" request)
      POST   /api/office/focus            Office.Focus.request {"thread_id"} — the desktop asks the office TUI to open a thread
      GET    /api/office/needs            Office.Needs.list (everything waiting on the operator: blocking first, then to decide)
      GET    /api/alerts                  Alerts.list (what the desktop raises: alarm, decision, sticky — each with its actions)
      DELETE /api/office/rollout/:id      Rollout.dismiss (a rollout note the operator has done)
      GET    /api/office/suggestions/:ws  Office.Corkboard.suggestions (the suggestion box)
      DELETE /api/office/suggestions/:ws/:id  Office.Corkboard.drop (filed as a ticket, or thrown out)
      GET    /api/office/activity/:ws     Office.Room.activity (what just happened: the in-tray)
      GET    /api/office/triage/:ws       Office.Room.triage (blockers, failed checks, unled threads: the beacon)
      GET    /api/office/memory/:ws       Office.Room.memory (pinned facts, habits to review: the bookshelf)
      GET    /api/office/tickets/:ws      Office.Room.tickets (the whole board, every status, with blockers)
      GET    /api/office/workspace/:ws    Office.Room.workspace (type, scope, icon, repos: its config card)
      GET    /api/office/schedules/:ws    Office.Room.schedules (the wall calendar: each schedule, its next
                                          firing, its days this month, its last run)
      GET    /api/office/health           Office.Room.health (the service and its box: the rack)
      GET    /api/settings                the office's switches from the settings file: {"banter"}
      PATCH  /api/settings                {"banter"} → OperatorConfig.put (the rest of the file kept)
      GET    /api/office/history          Office.Room.history (every closed thread, for the finder)

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
      GET    /api/threads/:id/docs        Workline.Docs.list (the workline's docs: work/<slug>/*.md)
      GET    /api/threads/:id/docs/:name  Workline.Docs.read (one doc's text; "current" is the stage's)
      POST   /api/threads/:id/verify      run a workline's verify again (Jobs.Verify), as entering verify does; 409 off verify
      POST   /api/threads/:id/track       Workline.promote: make a plain thread a workline
      POST   /api/threads/:id/checks      {"slug", "exit", "cmd", "tail"?} → Dossier.record_check (the verify stage's evidence)
      POST   /api/threads/:id/move        {"project_id"} → Projects.move_thread (within its workspace)
      DELETE /api/threads/:id             Server.delete_thread (its worktree too, when that loses nothing;
                                          the root machine thread is refused)
      POST   /api/threads                 {"workspace_id", "body", "project_id"?, "kind"?} → a thread titled
                                          by the body's first line, the body its opening message; kind
                                          "workline" opens at intent, "spike" at build; 201
      POST   /api/worklines               {"title", "slug"} → Workline.open at intent; 201
      POST   /api/notes                   {"workspace_id", "body"} → Notes.write as the operator; 201

      POST   /api/tickets                 {"workspace_id", "title", "project_id"?, "body"?} → Tickets.file; 201
      PATCH  /api/tickets/:id             {"status"?, "title"?, "body"?} → Tickets.update
      DELETE /api/tickets/:id             Tickets.remove
      POST   /api/tickets/:id/route       Tickets.route: to the workspace's manager (no manager: its lead starts it)
      POST   /api/tickets/:id/start       {"agent_id"?} → Tickets.start_thread (default: the lead); 201 + the thread
      POST   /api/tickets/:id/reorder     {"direction": "up"|"down"} → Tickets.reorder within its column
      POST   /api/tickets/:id/blockers    {"by"} → Tickets.link(by, id, "blocks")
      DELETE /api/tickets/:id/blockers/:by  Tickets.unlink

      POST   /api/workspaces              {"name", "template"?, "repo"?} → Workspaces.register_from (a
                                          template's type and bench) or Workspaces.register; 201
      PATCH  /api/workspaces/:id          {"type"?, "scope"?, "icon"?} → Workspaces.edit
      POST   /api/workspaces/:id/repos    {"path", "remote"?, "branch"?} → Workspaces.add_repo; 201
      DELETE /api/repos/:id               Workspaces.remove_repo
      DELETE /api/workspaces/:id          Workspaces.remove (its threads move on; the last is refused)
      POST   /api/workspaces/:id/coworkers  {"name", "archetype", "model"?, "effort"?, "ask"?} → seat + retarget; 201
      PATCH  /api/workspaces/:id/coworkers/:agent_id  {"model"?, "effort"?, "ask"?} → Workspaces.retarget
                                          ("inherit" puts a knob back to the archetype's; absent leaves it)
      POST   /api/workspaces/:id/coworkers/:agent_id/aside  {"question"} → Office.aside_spec: the
                                          command to run and where — the CALLER runs it
      POST   /api/workspaces/:id/coworkers/:agent_id/clear  Staffing.clear_context: its sessions end and
                                          its windows close; the next message spawns it fresh
      DELETE /api/seats/:id               Workspaces.unseat (the agent itself survives)
      DELETE /api/facts/:id               Dossier.forget_fact (a tombstone: out of recall, row kept)
      POST   /api/issues/:id/resolve      {"resolution"?} → Dossier.resolve_issue
      POST   /api/habits/:id/approve      Server.approve_habit (…/reject: Server.reject_habit)

      POST   /api/schedules               {"workspace_id", "kind": "agent"|"workline"|"script", "body",
                                          "cron" | "at", "title"?, "agent"?, "standing"?, "dir"?}
                                          → Schedules.create; 201
      PATCH  /api/schedules/:id           any of those but kind, and "enabled" → Schedules.update
      DELETE /api/schedules/:id           Schedules.remove (its runs go with it)
      POST   /api/schedules/:id/run       Schedules.run_now (its calendar untouched); 201 + the run
      GET    /api/schedules/:id/runs      Office.Room.runs (the automation board, newest first)
  """

  import Plug.Conn

  alias Server.Arbiter.Tmux
  alias Server.Board
  alias Server.Channel
  alias Server.Dossier
  alias Server.MCP.Brief
  alias Server.Office
  alias Server.Office.Room
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

  defp route(conn, "GET", "office", ["banter", ws]) do
    case Integer.parse(ws) do
      {id, ""} -> json(conn, 200, Server.Office.Banter.lines(id))
      _ -> json(conn, 404, %{error: "no workspace #{ws}"})
    end
  end

  defp route(conn, "GET", "office", ["needs"]), do: json(conn, 200, Server.Office.Needs.list())
  defp route(conn, "GET", "office", ["focus"]), do: json(conn, 200, Server.Office.Focus.latest())

  defp route(conn, "POST", "office", ["focus"]) do
    case body(conn) do
      {%{"thread_id" => id}, conn} when is_integer(id) ->
        json(conn, 200, Server.Office.Focus.request(id) && Server.Office.Focus.latest())

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"thread_id": n})})
    end
  end

  defp route(conn, "GET", "alerts", []), do: json(conn, 200, Server.Alerts.list())

  defp route(conn, "DELETE", "office", ["rollout", id]) do
    case Integer.parse(id) do
      {n, ""} -> json(conn, 200, %{ok: Server.Rollout.dismiss(n) == :ok})
      _ -> json(conn, 404, %{error: "no rollout note #{id}"})
    end
  end

  defp route(conn, "GET", "office", ["suggestions", ws]) do
    case Integer.parse(ws) do
      {id, ""} -> json(conn, 200, Server.Office.Corkboard.suggestions(id))
      _ -> json(conn, 404, %{error: "no workspace #{ws}"})
    end
  end

  defp route(conn, "DELETE", "office", ["suggestions", ws, id]) do
    case {Integer.parse(ws), Integer.parse(id)} do
      {{w, ""}, {i, ""}} -> json(conn, 200, %{ok: Server.Office.Corkboard.drop(w, i) == :ok})
      _ -> json(conn, 404, %{error: "no suggestion #{ws}/#{id}"})
    end
  end

  defp route(conn, "GET", "office", ["corkboard", ws]) do
    case Integer.parse(ws) do
      {id, ""} -> json(conn, 200, Server.Office.Corkboard.notes(id))
      _ -> json(conn, 404, %{error: "no workspace #{ws}"})
    end
  end

  defp route(conn, "GET", "office", ["pets", ws]) do
    case Integer.parse(ws) do
      {id, ""} -> json(conn, 200, Server.Office.Pets.voices(id))
      _ -> json(conn, 404, %{error: "no workspace #{ws}"})
    end
  end

  defp route(conn, "GET", "office", ["archive", ws]) do
    case Integer.parse(ws) do
      {id, ""} -> json(conn, 200, Office.archive(id))
      _ -> json(conn, 404, %{error: "no workspace #{ws}"})
    end
  end

  defp route(conn, "GET", "office", ["threads", id]),
    do: with_thread(conn, id, &json(conn, 200, Office.thread_view(&1, int_param(conn, "before"))))

  defp route(conn, "GET", "settings", []), do: json(conn, 200, settings())

  defp route(conn, "PATCH", "settings", []) do
    case body(conn) do
      {%{"banter" => on}, conn} when is_boolean(on) ->
        :ok = Server.OperatorConfig.put("banter", on)
        json(conn, 200, settings())

      {_, conn} ->
        json(conn, 422, %{error: ~s(expected {"banter": true|false})})
    end
  end

  defp route(conn, "GET", "office", ["health"]), do: json(conn, 200, Room.health())
  defp route(conn, "GET", "office", ["history"]), do: json(conn, 200, Room.history())

  defp route(conn, "GET", "office", [read, ws]) when read in ~w(activity triage memory tickets workspace schedules),
    do: with_workspace(conn, ws, &json(conn, 200, apply(Room, String.to_existing_atom(read), [&1.id])))

  defp route(conn, "POST", "threads", []), do: new_thread(conn)
  defp route(conn, method, "threads", [id | rest]), do: with_thread(conn, id, &on_thread(conn, method, rest, &1))
  defp route(conn, "POST", "notes", []), do: write_note(conn)
  defp route(conn, "DELETE", "repos", [id]), do: with_row(conn, Server.WorkspaceRepo, id, &remove_repo(conn, &1))

  defp route(conn, "POST", "habits", [id, verdict]) when verdict in ~w(approve reject),
    do: with_int(conn, id, &reply(conn, review_habit(verdict, &1), fn h -> %{id: h.id, state: h.state} end))

  defp route(conn, "POST", "worklines", []), do: open_workline(conn)
  defp route(conn, method, "tickets", rest), do: on_tickets(conn, method, rest)
  defp route(conn, "POST", "schedules", []), do: new_schedule(conn)

  defp route(conn, method, "schedules", [id | rest]),
    do: with_row(conn, Server.Schedule, id, &on_schedule(conn, method, rest, &1))

  defp route(conn, method, "workspaces", rest), do: on_workspaces(conn, method, rest)
  defp route(conn, "DELETE", "seats", [id]), do: with_int(conn, id, &fire(conn, &1))
  defp route(conn, "DELETE", "facts", [id]), do: with_row(conn, Server.Fact, id, &forget(conn, &1))
  defp route(conn, "POST", "issues", [id, "resolve"]), do: with_row(conn, Server.Issue, id, &resolve(conn, &1))
  defp route(conn, _, _, _), do: no_route(conn)

  defp on_thread(conn, "GET", [], t), do: json(conn, 200, t |> Board.brief() |> Brief.scope())
  defp on_thread(conn, "GET", ["messages"], t), do: messages(conn, t)
  defp on_thread(conn, "GET", ["terminal"], t), do: terminal(conn, t)
  defp on_thread(conn, "GET", ["worktree"], t), do: worktree(conn, t)
  defp on_thread(conn, "GET", ["docs"], t), do: json(conn, 200, Server.Workline.Docs.list(t))

  defp on_thread(conn, "GET", ["docs", name], t) do
    case Server.Workline.Docs.read(t, name) do
      {:ok, text} -> json(conn, 200, %{name: name, text: text})
      {:error, why} -> json(conn, 404, %{error: why})
    end
  end

  defp on_thread(conn, "POST", ["messages"], t), do: post(conn, t)
  defp on_thread(conn, "POST", ["close"], t), do: reply(conn, Channel.close_thread(t), &thread_row/1)
  defp on_thread(conn, "POST", ["hand-off"], t), do: hand_off(conn, t)
  defp on_thread(conn, "POST", ["advance"], t), do: reply(conn, Workline.advance(t), &thread_row/1)
  defp on_thread(conn, "POST", ["approve"], t), do: reply(conn, Workline.approve(t), &thread_row/1)
  defp on_thread(conn, "POST", ["track"], t), do: reply(conn, Workline.promote(t), &thread_row/1)

  defp on_thread(conn, "POST", ["verify"], %Thread{stage: "verify"} = t) do
    case Server.Jobs.enqueue(Server.Jobs.Verify.new(%{thread_id: t.id, slug: t.slug})) do
      {:ok, _} -> json(conn, 202, %{verifying: t.id})
      {:error, why} -> json(conn, 503, %{error: "verify can't be queued here: #{inspect(why)}"})
    end
  end

  defp on_thread(conn, "POST", ["verify"], t), do: json(conn, 409, %{error: "thread #{t.id} is not at verify"})
  defp on_thread(conn, "POST", ["checks"], t), do: record_check(conn, t)
  defp on_thread(conn, "POST", ["move"], t), do: move(conn, t)
  defp on_thread(conn, "DELETE", [], t), do: delete_thread(conn, t)
  defp on_thread(conn, _, _, _), do: no_route(conn)

  defp on_tickets(conn, "POST", []), do: file_ticket(conn)
  defp on_tickets(conn, "PATCH", [id]), do: with_ticket(conn, id, &update_ticket(conn, &1))

  defp on_tickets(conn, "DELETE", [id]),
    do: with_ticket(conn, id, &reply(conn, Tickets.remove(&1), fn _ -> %{deleted: &1.id} end))

  defp on_tickets(conn, "POST", [id, "route"]), do: with_ticket(conn, id, &route_ticket(conn, &1))
  defp on_tickets(conn, "POST", [id, "start"]), do: with_ticket(conn, id, &start(conn, &1))
  defp on_tickets(conn, "POST", [id, "reorder"]), do: with_ticket(conn, id, &reorder(conn, &1))
  defp on_tickets(conn, "POST", [id, "blockers"]), do: with_ticket(conn, id, &block(conn, &1))

  defp on_tickets(conn, "DELETE", [id, "blockers", by]),
    do: with_ticket(conn, id, &with_int(conn, by, fn b -> unblock(conn, &1, b) end))

  defp on_tickets(conn, _, _), do: no_route(conn)

  defp on_schedule(conn, "GET", ["runs"], s), do: json(conn, 200, Room.runs(s.id))
  defp on_schedule(conn, "POST", ["run"], s), do: reply(conn, Server.Schedules.run_now(s), &%{run: &1.id}, 201)
  defp on_schedule(conn, "PATCH", [], s), do: edit_schedule(conn, s)
  defp on_schedule(conn, "DELETE", [], s), do: reply(conn, Server.Schedules.remove(s), &%{deleted: &1.id})
  defp on_schedule(conn, _, _, _), do: no_route(conn)

  defp on_workspaces(conn, "POST", []), do: new_workspace(conn)
  defp on_workspaces(conn, "PATCH", [id]), do: with_workspace(conn, id, &edit_workspace(conn, &1))
  defp on_workspaces(conn, "POST", [id, "repos"]), do: with_workspace(conn, id, &add_repo(conn, &1))

  defp on_workspaces(conn, "DELETE", [id]),
    do: with_workspace(conn, id, &reply(conn, Workspaces.remove(&1), fn w -> %{deleted: w.id} end))

  defp on_workspaces(conn, "POST", [id, "coworkers"]), do: with_workspace(conn, id, &hire(conn, &1))

  defp on_workspaces(conn, "PATCH", [id, "coworkers", a]),
    do: with_workspace(conn, id, &with_int(conn, a, fn agent -> retarget(conn, &1, agent) end))

  defp on_workspaces(conn, "POST", [id, "coworkers", a, "aside"]),
    do: with_workspace(conn, id, &with_int(conn, a, fn agent -> aside(conn, &1, agent) end))

  defp on_workspaces(conn, "POST", [id, "coworkers", a, "clear"]),
    do: with_workspace(conn, id, &with_int(conn, a, fn agent -> clear(conn, &1, agent) end))

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

  # Post as the operator through the one door (`Server.Attention.respond/3`, the same call
  # `server:post` makes): a body naming an option of an open prompt answers
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

  defp reorder(conn, t) do
    case body(conn) do
      {%{"direction" => d}, conn} when d in ~w(up down) ->
        :ok = Tickets.reorder(t, String.to_existing_atom(d))
        json(conn, 200, %{ticket: t.id})

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"direction": "up" | "down"})})
    end
  end

  # "blocked by": a `blocks` link from the blocker to this ticket — the one direction it is stored in
  defp block(conn, t) do
    case body(conn) do
      {%{"by" => by}, conn} when is_integer(by) and by != t.id ->
        reply(conn, Tickets.link(by, t.id, "blocks"), fn _ -> %{ticket: t.id, blocked_by: Tickets.blockers(t.id)} end)

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"by": another ticket's id})})
    end
  end

  defp unblock(conn, t, by) do
    :ok = Tickets.unlink(by, t.id, "blocks")
    json(conn, 200, %{ticket: t.id, blocked_by: Tickets.blockers(t.id)})
  end

  # A new thread from the operator's first words: titled by their first line, the words posted as
  # its opening message (the lead wakes to them), in the workspace's chosen project. `kind` makes it
  # a workline instead: "workline" starts at intent, "spike" straight at build.
  defp new_thread(conn) do
    case body(conn) do
      {%{"workspace_id" => ws, "body" => text} = b, conn} when is_integer(ws) and is_binary(text) ->
        title = text |> String.split("\n", parts: 2) |> hd() |> String.trim() |> String.slice(0, 60)
        attrs = %{title: title, workspace_id: ws, project_id: b["project_id"]}

        opened =
          case b["kind"] do
            "workline" -> Server.open_workline(Map.put(attrs, :stage, "intent"))
            "spike" -> Server.open_workline(Map.put(attrs, :stage, "build"))
            _ -> Channel.open_thread(Map.put(attrs, :scope, "machine"))
          end

        case opened do
          {:ok, t} ->
            {:ok, _} = Channel.post(%{thread_id: t.id, author: operator(), body: text})
            staff_now(ws)
            json(conn, 201, thread_row(t))

          {:error, why} ->
            refused(conn, why)
        end

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"workspace_id": n, "body": "…", "project_id"?, "kind"?})})
    end
  end

  defp move(conn, thread) do
    case body(conn) do
      {%{"project_id" => p}, conn} when is_integer(p) ->
        reply(conn, Server.Projects.move_thread(thread, p), &thread_row/1)

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"project_id": n})})
    end
  end

  # the thread goes, and its worktree with it when that loses nothing (else it is kept, and named)
  defp delete_thread(conn, thread) do
    case Server.delete_thread(thread.id) do
      {:ok, _, {:kept, why}} -> json(conn, 200, %{deleted: thread.id, worktree: "kept: #{inspect(why)}"})
      {:ok, _, {:removed, path}} -> json(conn, 200, %{deleted: thread.id, worktree: "removed #{path}"})
      {:ok, _, :none} -> json(conn, 200, %{deleted: thread.id})
      {:error, why} -> refused(conn, why)
    end
  end

  defp write_note(conn) do
    case body(conn) do
      {%{"workspace_id" => ws, "body" => text}, conn} when is_integer(ws) and is_binary(text) ->
        note = %{scope: "workspace", scope_id: ws, author: operator(), body: text}
        reply(conn, Server.Notes.write(note), &%{id: &1.id, body: &1.body}, 201)

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"workspace_id": n, "body": "…"})})
    end
  end

  # A schedule from the operator: what (`kind`, `body`; `title` defaults to the body's first line),
  # when (`cron`, or `at` as an ISO-8601 time), and how (`agent`, `standing`, `dir`).
  defp new_schedule(conn) do
    case body(conn) do
      {%{"workspace_id" => ws, "kind" => kind, "body" => text} = b, conn} when is_integer(ws) and is_binary(text) ->
        title = b["title"] || text |> String.split("\n", parts: 2) |> hd() |> String.trim() |> String.slice(0, 60)
        attrs = Map.merge(schedule_attrs(b), %{workspace_id: ws, kind: kind, title: title})
        reply(conn, Server.Schedules.create(attrs), &schedule_row/1, 201)

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"workspace_id", "kind", "body", "cron" | "at", …})})
    end
  end

  defp edit_schedule(conn, s) do
    {b, conn} = body(conn)
    reply(conn, Server.Schedules.update(s, schedule_attrs(b)), &schedule_row/1)
  end

  defp schedule_attrs(b) do
    for {k, v} <- b,
        k in ~w(title body cron at agent standing dir enabled),
        into: %{},
        do: {String.to_existing_atom(k), v}
  end

  defp schedule_row(s), do: Map.take(s, [:id, :kind, :title, :cron, :at, :enabled, :standing, :agent])

  defp review_habit("approve", id), do: Server.approve_habit(id)
  defp review_habit("reject", id), do: Server.reject_habit(id)

  defp edit_workspace(conn, ws) do
    {b, conn} = body(conn)
    attrs = for {k, v} <- b, k in ~w(type scope), is_binary(v), into: %{}, do: {String.to_existing_atom(k), v}

    attrs =
      if is_binary(b["icon"]), do: Map.put(attrs, :knobs, Map.put(ws.knobs || %{}, "icon", b["icon"])), else: attrs

    if attrs == %{},
      do: json(conn, 400, %{error: ~s(expected some of {"type", "scope", "icon"})}),
      else: reply(conn, Workspaces.edit(ws, attrs), &%{id: &1.id, name: &1.name, type: &1.type, scope: &1.scope})
  end

  defp add_repo(conn, ws) do
    case body(conn) do
      {%{"path" => path} = b, conn} when is_binary(path) and path != "" ->
        attrs = %{path: path, remote: b["remote"], default_branch: b["branch"]}
        reply(conn, Workspaces.add_repo(ws.id, attrs), &%{id: &1.id, path: &1.path}, 201)

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"path", "remote"?, "branch"?})})
    end
  end

  defp remove_repo(conn, repo), do: reply(conn, Workspaces.remove_repo(repo), &%{deleted: &1.id})

  defp new_workspace(conn) do
    case body(conn) do
      {%{"name" => name, "template" => tpl} = b, conn} when is_binary(name) and name != "" and is_binary(tpl) ->
        reply(conn, Workspaces.register_from(tpl, name, repos_of(b)), &%{id: &1.id, name: &1.name}, 201)

      {%{"name" => name} = b, conn} when is_binary(name) and name != "" ->
        reply(conn, Workspaces.register(%{name: name, repos: repos_of(b)}), &%{id: &1.id, name: &1.name}, 201)

      {_, conn} ->
        json(conn, 400, %{error: ~s(expected {"name", "repo"?})})
    end
  end

  defp repos_of(%{"repo" => r}) when is_binary(r) and r != "", do: [r]
  defp repos_of(_), do: []

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

  # a seated coworker's context cleared: its sessions end, its windows close; the next message spawns it fresh
  defp clear(conn, ws, agent_id) do
    case Enum.find(Workspaces.bench(ws.id), &(&1.agent_id == agent_id)) do
      nil -> json(conn, 404, %{error: "no coworker #{agent_id} on #{ws.name}"})
      c -> reply(conn, {:ok, Server.Staffing.clear_context(ws.id, c.name)}, fn _ -> %{cleared: c.name} end)
    end
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

  defp settings, do: %{banter: Server.OperatorConfig.banter?()}

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

  defp int_param(conn, name) do
    case Integer.parse(fetch_query_params(conn).query_params[name] || "") do
      {n, ""} -> n
      _ -> nil
    end
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
