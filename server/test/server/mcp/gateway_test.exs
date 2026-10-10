defmodule Server.MCP.GatewayTest do
  # The /mint endpoint (Server.MCP.Gateway): an adapter mints a fresh token per connect
  # against its TLON_MCP_URL origin, so a pane is never stranded by a token-model
  # change or a secret regeneration. Proven END TO END over the wire (Bandit serves the
  # Gateway on a real loopback port, :httpc posts) — the same harness server_test uses.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.MCP
  alias Server.Staff

  setup_all do
    {:ok, _} = Application.ensure_all_started(:inets)
    :ok
  end

  setup do
    Server.TestDB.clean!()
    start_supervised!({MCP.Endpoint, transport: {:streamable_http, start: true}})
    # port 0: the OS picks a free one, so parallel suites never fight over a fixed port
    bandit = start_supervised!({Bandit, plug: {Server.MCP.Gateway, []}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    Process.put(:base_url, ~c"http://127.0.0.1:#{port}")
    Process.put(:mint_url, ~c"http://127.0.0.1:#{port}/mint")
    Process.put(:mcp_url, ~c"http://127.0.0.1:#{port}/mcp")

    {:ok, thread} = Channel.open_thread(%{title: "vision consult"})
    {:ok, agent} = Staff.register_agent(%{name: "pi-machine", mandate: "m", engine: "e"})
    %{thread: thread, agent: agent}
  end

  test "POST /mint returns a fresh, resolvable token for a live (thread, agent)", %{thread: t, agent: a} do
    {status, body} = mint(%{thread_id: t.id, agent: a.name})
    assert status == 200
    assert %{"token" => tok} = body
    assert is_binary(tok) and String.contains?(tok, ".")
    # The token this node just minted verifies here — same workspace secret end to end.
    t_id = t.id
    a_id = a.id
    assert {:ok, %{thread_id: ^t_id, agent_id: ^a_id}} = MCP.Tokens.resolve(tok)
  end

  test "POST /mint for a missing thread is a 400 (never mints against a guess)", %{agent: a} do
    {status, body} = mint(%{thread_id: 999_999, agent: a.name})
    assert status == 400
    assert body["error"]
  end

  test "POST /mint for a missing agent is a 400", %{thread: t} do
    {status, body} = mint(%{thread_id: t.id, agent: "nobody"})
    assert status == 400
    assert body["error"]
  end

  test "POST /mint with a malformed body is a 400" do
    {status, _body} = post_raw(Process.get(:mint_url), "not json")
    assert status == 400
  end

  test "GET /mint is a 405 (POST only)" do
    {:ok, {{_http, status, _reason}, _headers, _body}} =
      :httpc.request(:get, {Process.get(:mint_url), []}, [], body_format: :binary)

    assert status == 405
  end

  test "a non-/mint path forwards to the MCP server (the Gateway is a passthrough there)" do
    # A bare POST to /mcp with no bearer is the MCP server's 401 — proving the request
    # reached anubis through the Gateway, not the mint handler.
    {:ok, {{_http, status, _reason}, _headers, _body}} =
      :httpc.request(
        :post,
        {Process.get(:mcp_url), [], ~c"application/json", ~s({"jsonrpc":"2.0","method":"initialize"})},
        [],
        body_format: :binary
      )

    assert status == 401
  end

  test "two mints for the same (thread, agent) yield the SAME deterministic token" do
    # mint_for is deterministic (stateless HMAC), so per-connect minting is stable.
    {:ok, thread} = Channel.open_thread(%{title: "deterministic"})
    {:ok, agent} = Staff.register_agent(%{name: "det", mandate: "m", engine: "e"})
    {_, %{"token" => t1}} = mint(%{thread_id: thread.id, agent: agent.name})
    {_, %{"token" => t2}} = mint(%{thread_id: thread.id, agent: agent.name})
    assert t1 == t2
  end

  defp mint(body) do
    {status, decoded} = post_raw(Process.get(:mint_url), JSON.encode!(body))
    {status, decoded}
  end

  defp post_raw(url, body) do
    {:ok, {{_http, status, _reason}, _headers, resp_body}} =
      :httpc.request(:post, {url, [], ~c"application/json", body}, [], body_format: :binary)

    decoded =
      if resp_body not in [nil, "", []] do
        JSON.decode!(to_string(resp_body))
      end

    {status, decoded}
  end

  defp get_json(path) do
    {:ok, {{_http, status, _reason}, _headers, body}} =
      :httpc.request(:get, {Process.get(:base_url) ++ String.to_charlist(path), []}, [], body_format: :binary)

    {status, JSON.decode!(body)}
  end

  defp post_json(path, map) do
    {:ok, {{_http, status, _reason}, _headers, body}} =
      :httpc.request(
        :post,
        {Process.get(:base_url) ++ String.to_charlist(path), [], ~c"application/json", JSON.encode!(map)},
        [],
        body_format: :binary
      )

    {status, JSON.decode!(body)}
  end

  defp request_json(method, path, map) do
    {:ok, {{_http, status, _reason}, _headers, body}} =
      :httpc.request(
        method,
        {Process.get(:base_url) ++ String.to_charlist(path), [], ~c"application/json", JSON.encode!(map)},
        [],
        body_format: :binary
      )

    {status, JSON.decode!(body)}
  end

  test "PATCH /api/flags/:name flips a flag; the office snapshot shows it; an unknown name is a 404" do
    assert {200, %{"flags" => %{"build_mode" => false}}} = get_json("/api/office")

    assert {200, %{"name" => "build_mode", "enabled" => true}} =
             request_json(:patch, "/api/flags/build_mode", %{"enabled" => true})

    assert {200, %{"flags" => %{"build_mode" => true}}} = get_json("/api/office")
    assert {200, %{"enabled" => false}} = request_json(:patch, "/api/flags/build_mode", %{"enabled" => false})
    assert {404, %{"error" => _}} = request_json(:patch, "/api/flags/nope", %{"enabled" => true})
    assert {422, %{"error" => _}} = request_json(:patch, "/api/flags/build_mode", %{"enabled" => "yes"})
  end

  test "POST /api/restart while busy schedules it, says what it waits on; DELETE drops it" do
    :ok = Server.Presence.Thinking.thinking(987_654, "hronir")
    Application.put_env(:server, :restart_run, fn _force -> :ok end)

    on_exit(fn ->
      Application.delete_env(:server, :restart_run)
      Server.Rollout.cancel_restart()
      Server.Presence.Thinking.idle(987_654, "hronir")
    end)

    assert {202, %{"scheduled" => true, "waiting_on" => lines}} = request_json(:post, "/api/restart", %{})
    assert Enum.any?(lines, &(&1 =~ "#987654"))
    assert {200, %{"restart_pending" => true}} = get_json("/api/settings")

    assert {200, %{"restart_pending" => false}} = request_json(:delete, "/api/restart", %{})
  end

  test "GET/PATCH /api/settings read and change every runtime knob in the settings file" do
    path = Path.join(System.tmp_dir!(), "tlon-config-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      Application.put_env(:server, :operator_config_path, "/nonexistent/tlon-test-config.json")
      File.rm(path)
    end)

    value = fn {_, %{"knobs" => knobs}}, key -> Enum.find(knobs, &(&1["key"] == key))["value"] end

    assert "/api/settings" |> get_json() |> value.("banter") == true

    patched = request_json(:patch, "/api/settings", %{"banter" => false, "max_leaves" => 2})
    assert {200, _} = patched
    assert value.(patched, "max_leaves") == 2
    assert Server.OperatorConfig.read(path) == %{"banter" => false, "max_leaves" => 2}
    assert {422, %{"error" => _}} = request_json(:patch, "/api/settings", %{"banter" => "loud"})
    assert {422, _} = request_json(:patch, "/api/settings", %{"max_leaves" => 999})
  end

  test "POST /api/threads/:id/messages is the operator's one door: `y` answers an open prompt, a closed thread reopens",
       %{thread: t} do
    # the prompt row as Server.Attention opens it; the pane is a recording fake
    test_pid = self()

    Application.put_env(:server, :tmux_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})
      {"", 0}
    end)

    Application.put_env(:server, :attention_settle_ms, 0)
    on_exit(fn -> for k <- [:tmux_cmd, :attention_settle_ms], do: Application.delete_env(:server, k) end)

    {:ok, prompt} =
      %{
        thread_id: t.id,
        author: "tlon",
        body: "⚑ waiting on you — bash: env",
        kind: "prompt",
        payload: %{
          "harness" => "claude",
          "summary" => "bash: env",
          "window" => "t#{t.id}",
          "workspace_id" => 1,
          "options" => [%{"key" => "y", "label" => "Yes"}, %{"key" => "n", "label" => "No"}]
        }
      }
      |> Server.Message.post_changeset()
      |> Server.Repo.insert()

    {201, answer} = post_json("/api/threads/#{t.id}/messages", %{body: "y"})
    assert answer["reply_to"] == prompt.id
    assert_received {:tmux, ["-L", _, "send-keys", "-l", "-t", _, "y"]}
    assert Server.Repo.get!(Server.Message, prompt.id).resolution == "answered: y"

    {:ok, _} = Channel.close_thread(Server.Repo.get!(Server.Thread, t.id))
    {201, _} = post_json("/api/threads/#{t.id}/messages", %{body: "back to this"})
    assert Server.Repo.get!(Server.Thread, t.id).state == "open"
  end

  test "GET /api/threads/:id/terminal is where the coworker runs, 404 when nothing does" do
    {:ok, ws} = Server.Workspaces.register(%{name: "tmuxed", type: "code", scope: "project", repos: [], roster: []})
    {:ok, t} = Channel.open_thread(%{title: "where am i", workspace_id: ws.id})
    Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"", 1} end)
    on_exit(fn -> Application.delete_env(:server, :tmux_cmd) end)
    assert {404, _} = get_json("/api/threads/#{t.id}/terminal")
    Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"1\tt#{t.id}\t#{t.id}\t7\n", 0} end)

    assert {200, %{"socket" => socket, "session" => session, "window" => window}} =
             get_json("/api/threads/#{t.id}/terminal")

    assert socket == "tlon-workspace-#{ws.id}" and session == "w#{ws.id}" and window == "t#{t.id}"
  end

  test "GET /api/threads/:id/worktree is the coworker's working dir, ensured; 404 with no repo" do
    {:ok, bare} = Channel.open_thread(%{title: "nowhere"})
    assert {404, _} = get_json("/api/threads/#{bare.id}/worktree")

    repo = Path.join(System.tmp_dir!(), "tlon-worktree-api-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(repo) end)
    git = fn args -> {_, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) end
    git.(["init", "-q"])
    git.(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "seed"])
    {:ok, t} = Channel.open_thread(%{title: "somewhere", repo: repo})

    assert {200, %{"path" => path}} = get_json("/api/threads/#{t.id}/worktree")
    assert path == Server.Worktree.path(repo, Server.Worktree.name_for(t))
    assert File.exists?(Path.join(path, ".git"))
  end

  test "GET /api/office/archive/:ws is the workspace's done tickets and closed threads, nothing open" do
    {:ok, ws} = Server.Workspaces.register(%{name: "archived", type: "code", scope: "project", repos: [], roster: []})

    {:ok, other} =
      Server.Workspaces.register(%{name: "elsewhere", type: "code", scope: "project", repos: [], roster: []})

    {:ok, done} = Server.Tickets.file(%{workspace_id: ws.id, title: "shipped"})
    {:ok, _} = Server.Tickets.update(done, %{status: "done"})
    {:ok, _open} = Server.Tickets.file(%{workspace_id: ws.id, title: "still open"})
    {:ok, closed} = Channel.open_thread(%{title: "wrapped up", workspace_id: ws.id})
    {:ok, _} = Channel.close_thread(closed)
    {:ok, _live} = Channel.open_thread(%{title: "going on", workspace_id: ws.id})
    {:ok, theirs} = Channel.open_thread(%{title: "not ours", workspace_id: other.id})
    {:ok, _} = Channel.close_thread(theirs)

    assert {200, %{"tickets" => tickets, "threads" => threads}} = get_json("/api/office/archive/#{ws.id}")
    assert Enum.map(tickets, & &1["title"]) == ["shipped"]
    assert Enum.map(threads, & &1["title"]) == ["wrapped up"]
    assert {404, _} = get_json("/api/office/archive/nope")
  end

  test "GET /api/office/margin/:ws is Uqbar's margin notes, newest first" do
    {:ok, ws} = Server.Workspaces.register(%{name: "margined", type: "code", scope: "project", repos: [], roster: []})
    {:ok, root} = Channel.open_thread(%{title: "standing", scope: "machine", workspace_id: ws.id})
    {:ok, _} = Channel.post(%{thread_id: root.id, author: "uqbar", body: "cut 650fa4a", kind: "margin"})

    assert {200, [%{"author" => "uqbar", "body" => "cut 650fa4a", "at" => _}]} =
             get_json("/api/office/margin/#{ws.id}")

    assert {404, _} = get_json("/api/office/margin/nope")
  end

  test "GET /api/office/board/:ws is the backlog grouped by epic, with progress" do
    {:ok, ws} = Server.Workspaces.register(%{name: "boarded", type: "code", scope: "project", repos: [], roster: []})
    {:ok, epic} = Server.Tickets.file(%{workspace_id: ws.id, title: "Toy", kind: "epic"})
    {:ok, _} = Server.Tickets.file(%{workspace_id: ws.id, title: "step 1", epic_id: epic.id})

    assert {200, %{"epics" => [row], "loose" => []}} = get_json("/api/office/board/#{ws.id}")
    assert %{"done" => 0, "total" => 1, "title" => "Toy"} = row
    assert {404, _} = get_json("/api/office/board/nope")
  end

  test "a workline's brief carries the gate" do
    # the artifact check runs git under the workline root: a throwaway repo, never this checkout
    tmp = Path.join(System.tmp_dir!(), "tlon-gateway-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    {_, 0} = System.cmd("git", ["-C", tmp, "init", "-q"], stderr_to_stdout: true)
    previous = Application.get_env(:server, :workline_root)
    Application.put_env(:server, :workline_root, tmp)

    on_exit(fn ->
      Application.put_env(:server, :workline_root, previous)
      File.rm_rf!(tmp)
    end)

    {:ok, wl} = Server.Workline.open(%{title: "gate me", slug: "gate-me"})
    {200, brief} = get_json("/api/threads/#{wl.id}")
    assert %{"stage" => "intent", "artifact_ok" => false, "why" => why} = brief["workline"]
    assert why =~ "intent.md"
  end

  describe "/api/office and the office's writes — the TUI's door (Server.MCP.OperatorAPI)" do
    test "GET /api/office is Office.status; GET /api/office/threads/:id a close look at one", %{thread: t} do
      {200, body} = get_json("/api/office")
      assert Enum.any?(body["threads"], &(&1["id"] == t.id))
      assert Map.has_key?(body, "workspaces") and Map.has_key?(body, "bench")
      {200, view} = get_json("/api/office/threads/#{t.id}")
      assert is_list(view["messages"])
      assert {404, _} = get_json("/api/office/threads/999999")
    end

    test "POST /api/office/asks/:id answers that ask by its key; a key it doesn't offer is refused", %{thread: t} do
      {:ok, a} = Server.Attention.ask(t.id, "tertius", "start now?", ["go", "hold"])
      assert {409, _} = post_json("/api/office/asks/#{a.id}", %{key: "9"})
      assert {200, %{"ok" => true}} = post_json("/api/office/asks/#{a.id}", %{key: "2"})
      assert Server.Repo.get!(Server.Message, a.id).resolution == "answered: hold"
      assert {409, _} = post_json("/api/office/asks/#{a.id}", %{key: "1"})
      assert {400, _} = post_json("/api/office/asks/#{a.id}", %{nope: 1})
    end

    test "POST /api/threads/:id/send_back moves a workline back as the operator, saying why" do
      {:ok, wl} = Server.Workline.open(%{title: "send me back", slug: "send-me-back", stage: "review"})
      assert {400, _} = post_json("/api/threads/#{wl.id}/send_back", %{stage: "plan"})

      assert {200, %{"stage" => "plan"}} =
               post_json("/api/threads/#{wl.id}/send_back", %{stage: "plan", why: "wrong shape"})

      assert {409, _} = post_json("/api/threads/#{wl.id}/send_back", %{stage: "build", why: "forward"})
    end

    test "the shift board: the snapshot carries each shift and every seat's; seats are put on one, the shift switched" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Board"})
      {:ok, day} = Server.Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder", crew: "day"})
      {:ok, night} = Server.Workspaces.seat(ws.id, %{name: "dahlmann", archetype: "builder"})

      assert {200, %{"crew" => "night"}} = request_json(:patch, "/api/seats/#{night.id}", %{crew: "night"})
      assert {422, _} = request_json(:patch, "/api/seats/#{night.id}", %{crew: "dusk"})
      assert {422, _} = request_json(:patch, "/api/seats/#{night.id}", %{})
      assert {404, _} = post_json("/api/office/shift", %{workspace_id: 999_999, shift: "night"})

      {200, office} = get_json("/api/office")
      assert %{"shift" => "day"} = Enum.find(office["workspaces"], &(&1["id"] == ws.id))
      board = Enum.filter(office["shifts"], &(&1["workspace_id"] == ws.id))
      assert Enum.map(board, &{&1["seat_id"], &1["crew"]}) == [{day.id, "day"}, {night.id, "night"}]

      assert {200, %{"shift" => "night"}} = post_json("/api/office/shift", %{workspace_id: ws.id, shift: "night"})
      assert {400, _} = post_json("/api/office/shift", %{workspace_id: ws.id, shift: "dusk"})
      {200, office} = get_json("/api/office")
      assert Enum.map(Enum.filter(office["bench"], &(&1["workspace_id"] == ws.id)), & &1["name"]) == ["dahlmann"]
    end

    test "POST /api/tickets files one; /route and /start hand it on; /api/threads/:id/close closes" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Office"})
      {201, tk} = post_json("/api/tickets", %{workspace_id: ws.id, title: "from the TUI"})
      assert tk["title"] == "from the TUI"
      assert {400, _} = post_json("/api/tickets", %{workspace_id: ws.id})
      {:ok, th} = Channel.open_thread(%{title: "done soon", workspace_id: ws.id})
      {200, closed} = post_json("/api/threads/#{th.id}/close", %{})
      assert closed["id"] == th.id
      assert Server.Repo.get(Server.Thread, th.id).state == "closed"
      assert {404, _} = post_json("/api/tickets/999999/route", %{})
      assert {404, _} = post_json("/api/tickets/999999/start", %{})
    end
  end

  describe "/api — the CLI's writes over HTTP (Server.MCP.OperatorAPI)" do
    test "workspaces: create, hire, retarget, an aside's command, fire, delete" do
      {:ok, _keep} = Server.Workspaces.register(%{name: "Keep"})
      {201, ws} = post_json("/api/workspaces", %{name: "Office", repo: "/tmp/office-repo"})
      assert ws["name"] == "Office"
      assert {400, _} = post_json("/api/workspaces", %{})

      {201, c} =
        post_json("/api/workspaces/#{ws["id"]}/coworkers", %{name: "daneri", archetype: "builder", ask: "allow"})

      assert c["name"] == "daneri" and is_integer(c["agent_id"]) and is_integer(c["seat_id"])
      assert Server.Workspaces.policy(ws["id"], c["agent_id"]).ask_default == "allow"

      {200, _} =
        request_json(:patch, "/api/workspaces/#{ws["id"]}/coworkers/#{c["agent_id"]}", %{ask: "inherit", effort: "high"})

      p = Server.Workspaces.policy(ws["id"], c["agent_id"])
      assert p.ask_default == nil and p.model["thinking"] == "high"

      assert {422, _} =
               request_json(:patch, "/api/workspaces/#{ws["id"]}/coworkers/#{c["agent_id"]}", %{model: "nope/nada"})

      {200, aside} =
        post_json("/api/workspaces/#{ws["id"]}/coworkers/#{c["agent_id"]}/aside", %{question: "what is in main?"})

      assert Enum.any?(aside["argv"], &String.contains?(&1, "what is in main?"))
      assert aside["cwd"] == "/tmp/office-repo"

      {200, _} = request_json(:delete, "/api/seats/#{c["seat_id"]}", %{})
      assert Server.Workspaces.bench(ws["id"]) == []
      {200, _} = request_json(:delete, "/api/workspaces/#{ws["id"]}", %{})
      assert {404, _} = request_json(:delete, "/api/workspaces/#{ws["id"]}", %{})
    end

    test "a coworker's persona: made, rerolled and edited over HTTP" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Office"})
      {:ok, seat} = Server.Workspaces.seat(ws.id, %{name: "yu", archetype: "builder"})
      url = "/api/workspaces/#{ws.id}/coworkers/#{seat.agent_id}/persona"

      {200, a} = post_json(url, %{})
      assert is_integer(a["seed"]) and a["voice"] =~ "careful"
      {409, _} = post_json(url, %{reroll: true})
      {200, c} = request_json(:patch, url, %{voice: "calm"})
      assert c["voice"] == "calm" and c["seed"] == a["seed"]
      assert {404, _} = post_json("/api/workspaces/#{ws.id}/coworkers/999999/persona", %{})
    end

    test "hiring over HTTP gives the seat a persona, made off the request" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Office"})
      {201, c} = post_json("/api/workspaces/#{ws.id}/coworkers", %{name: "yu", archetype: "builder"})

      persona =
        Enum.find_value(1..50, fn _ ->
          Server.Persona.get(ws.id, c["name"]) || (Process.sleep(20) && nil)
        end)

      assert %{"voice" => _} = persona
    end

    test "tickets: change a field, delete" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Office"})
      {:ok, tk} = Server.Tickets.file(%{workspace_id: ws.id, title: "a"})
      {200, t} = request_json(:patch, "/api/tickets/#{tk.id}", %{status: "done", title: "b"})
      assert {t["status"], t["title"]} == {"done", "b"}
      assert {422, _} = request_json(:patch, "/api/tickets/#{tk.id}", %{status: "frozen"})
      {200, _} = request_json(:delete, "/api/tickets/#{tk.id}", %{})
      assert {404, _} = request_json(:delete, "/api/tickets/#{tk.id}", %{})
    end

    test "threads: hand off, delete; a plain thread is no workline to advance", %{thread: t} do
      {:ok, ws} = Server.Workspaces.register(%{name: "Office"})
      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "daneri", archetype: "builder"})
      {:ok, th} = Channel.open_thread(%{title: "pass it on", workspace_id: ws.id})
      {200, h} = post_json("/api/threads/#{th.id}/hand-off", %{agent: "daneri"})
      assert h["lead"] == "daneri"
      assert {409, _} = post_json("/api/threads/#{t.id}/advance", %{})
      {200, _} = request_json(:delete, "/api/threads/#{th.id}", %{})
      assert Server.Repo.get(Server.Thread, th.id) == nil
    end

    test "a workline opens; facts and issues are 404 when there is none" do
      {201, w} = post_json("/api/worklines", %{title: "the office API", slug: "office-api"})
      assert w["stage"] == "intent"
      assert {404, _} = request_json(:delete, "/api/facts/999999", %{})
      assert {404, _} = post_json("/api/issues/999999/resolve", %{})
    end
  end

  describe "/api — the office TUI's threads, room reads, settings and schedules" do
    test "a new thread: titled by its first line, the words its opening message; a spike is a workline at build" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Office"})
      {201, t} = post_json("/api/threads", %{workspace_id: ws.id, body: "fix the clock\nit runs fast"})
      assert t["title"] == "fix the clock"
      {200, view} = get_json("/api/office/threads/#{t["id"]}")
      assert [%{"body" => "fix the clock\nit runs fast"}] = view["messages"]
      assert view["more"] == false
      {201, s} = post_json("/api/threads", %{workspace_id: ws.id, body: "try a thing", kind: "spike"})
      assert s["stage"] == "build"
      assert {422, _} = post_json("/api/threads", %{workspace_id: ws.id, body: "  "})
    end

    test "a thread's messages page back with ?before=", %{thread: t} do
      for i <- 1..65, do: {:ok, _} = Channel.post(%{thread_id: t.id, author: "andrew", body: "m#{i}"})
      {200, page} = get_json("/api/office/threads/#{t.id}")
      assert length(page["messages"]) == 60 and page["more"]
      assert List.last(page["messages"])["body"] == "m65"
      {200, older} = get_json("/api/office/threads/#{t.id}?before=#{hd(page["messages"])["id"]}")
      assert Enum.map(older["messages"], & &1["body"]) == ~w(m1 m2 m3 m4 m5)
      refute older["more"]
    end

    test "the room's reads answer for a workspace, 404 for none" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Office"})

      for read <- ~w(activity triage memory tickets workspace) do
        assert {200, _} = get_json("/api/office/#{read}/#{ws.id}")
        assert {404, _} = get_json("/api/office/#{read}/999999")
      end

      assert {200, %{"state" => _}} = get_json("/api/office/health")
      assert {200, list} = get_json("/api/office/history")
      assert is_list(list)
    end

    test "notes, ticket order and blockers, workspace from a template, its repos and fields" do
      {201, ws} = post_json("/api/workspaces", %{name: "Life", template: "life"})
      assert [%{name: "assistant"}] = Server.Workspaces.bench(ws["id"])
      assert {409, _} = post_json("/api/workspaces", %{name: "Nope", template: "nope"})

      {201, n} = post_json("/api/notes", %{workspace_id: ws["id"], body: "buy milk"})
      assert n["body"] == "buy milk"

      {:ok, a} = Server.Tickets.file(%{workspace_id: ws["id"], title: "a"})
      {:ok, b} = Server.Tickets.file(%{workspace_id: ws["id"], title: "b"})
      {200, _} = post_json("/api/tickets/#{b.id}/reorder", %{direction: "down"})
      {200, blk} = post_json("/api/tickets/#{b.id}/blockers", %{by: a.id})
      assert blk["blocked_by"] == [a.id]
      {200, unblk} = request_json(:delete, "/api/tickets/#{b.id}/blockers/#{a.id}", %{})
      assert unblk["blocked_by"] == []

      {200, e} = request_json(:patch, "/api/workspaces/#{ws["id"]}", %{scope: "project", icon: "🏠"})
      assert e["scope"] == "project"
      assert Server.Workspaces.get(ws["id"]).knobs["icon"] == "🏠"
      {201, r} = post_json("/api/workspaces/#{ws["id"]}/repos", %{path: "/tmp/life-repo"})
      {200, _} = request_json(:delete, "/api/repos/#{r["id"]}", %{})
      assert Server.Workspaces.repos(ws["id"]) == []
    end

    test "schedules: made, read on the calendar, run now, edited, removed" do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      {:ok, ws} = Server.Workspaces.register(%{name: "Office"})

      {201, s} =
        post_json("/api/schedules", %{workspace_id: ws.id, kind: "script", body: "echo hi\nmore", cron: "0 9 * * *"})

      assert s["title"] == "echo hi"
      assert {422, _} = post_json("/api/schedules", %{workspace_id: ws.id, kind: "script", body: "x", cron: "nope"})
      at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()

      {201, once} =
        post_json("/api/schedules", %{workspace_id: ws.id, kind: "agent", body: "look", at: at, standing: true})

      {200, cal} = get_json("/api/office/schedules/#{ws.id}")
      assert [%{"days" => days, "next_at" => _, "last" => nil}, %{"id" => once_id}] = cal
      assert once_id == once["id"] and length(days) >= 28

      {201, %{"run" => run}} = post_json("/api/schedules/#{s["id"]}/run", %{})
      Server.Schedules.perform(run)
      {200, [%{"status" => "ok", "output" => "hi\n"}]} = get_json("/api/schedules/#{s["id"]}/runs")

      {200, off} = request_json(:patch, "/api/schedules/#{s["id"]}", %{enabled: false})
      refute off["enabled"]
      {200, _} = request_json(:delete, "/api/schedules/#{s["id"]}", %{})
      assert {404, _} = get_json("/api/schedules/#{s["id"]}/runs")
      {200, office} = get_json("/api/office")
      assert is_list(office["calendar"]["#{ws.id}"])
    end

    test "a seated coworker's context is cleared: their live sessions end; a stranger is a 404" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Office"})
      {:ok, seat} = Server.Workspaces.seat(ws.id, %{name: "daneri", archetype: "builder"})
      {:ok, th} = Channel.open_thread(%{title: "t", workspace_id: ws.id})
      {:ok, s} = Server.Staff.start_session(%{agent_id: seat.agent_id, thread_id: th.id})

      assert {200, %{"cleared" => "daneri"}} =
               post_json("/api/workspaces/#{ws.id}/coworkers/#{seat.agent_id}/clear", %{})

      assert Server.Repo.get!(Server.Session, s.id).ended_at
      assert {404, _} = post_json("/api/workspaces/#{ws.id}/coworkers/999999/clear", %{})
    end

    test "habits are approved or rejected; a thread moves between its workspace's projects" do
      {:ok, h} = Server.Dossier.propose_habit(%{text: "gate first", proposed_by: "hronir"})
      {200, %{"state" => "approved"}} = post_json("/api/habits/#{h.id}/approve", %{})
      assert {404, _} = post_json("/api/habits/999999/reject", %{})

      {:ok, ws} = Server.Workspaces.register(%{name: "Office"})
      {:ok, p} = Server.Projects.register(%{workspace_id: ws.id, name: "clock"})
      {:ok, th} = Channel.open_thread(%{title: "t", workspace_id: ws.id})
      {200, _} = post_json("/api/threads/#{th.id}/move", %{project_id: p.id})
      assert Server.Repo.get(Server.Thread, th.id).project_id == p.id
    end
  end

  describe "/api — the operator's door (Server.MCP.OperatorAPI)" do
    test "GET /api/sidebar is Board.sidebar as JSON, and carries the open thread", %{thread: t} do
      # the sidebar groups by workspace, so the row needs one to be grouped under
      # the sidebar groups by workspace, so a row needs one to be grouped under — and a thread with
      # NO workspace (the fixture's) lands in the default (oldest) one rather than being dropped
      {:ok, ws} = Server.Workspaces.register(%{name: "asterion", type: "code", scope: "project", repos: [], roster: []})
      {:ok, mine} = Channel.open_thread(%{title: "from the editor", workspace_id: ws.id})
      {200, body} = get_json("/api/sidebar")
      assert is_list(body)
      titles = for group <- body, row <- group["threads"], do: row["title"]
      assert mine.title in titles
      assert t.title in titles
    end

    test "GET /api/threads/:id is the brief an agent's get_dossier gets — COMMITS included", %{thread: t} do
      {200, body} = get_json("/api/threads/#{t.id}")
      assert body["goal"] == t.title
      assert %{"shown" => _, "more" => _} = body["commits"]
    end

    test "POST /api/threads/:id/messages posts AS THE OPERATOR, then GET lists it", %{thread: t} do
      {201, posted} = post_json("/api/threads/#{t.id}/messages", %{body: "ship it"})
      assert posted["author"] == Application.get_env(:server, :operator, "andrew")
      assert posted["body"] == "ship it"
      {200, messages} = get_json("/api/threads/#{t.id}/messages?limit=5")
      assert Enum.any?(messages, &(&1["id"] == posted["id"]))
    end

    test "GET /api/roster is Staff.roster with a plain `warm` key" do
      {200, body} = get_json("/api/roster")
      assert is_list(body)
    end

    test "an unknown thread is a 404, an empty body a 400, an unknown route a 404", %{thread: t} do
      assert {404, _} = get_json("/api/threads/999999")
      assert {400, _} = post_json("/api/threads/#{t.id}/messages", %{body: ""})
      assert {404, _} = get_json("/api/nope")
    end
  end

  describe "/api/life — routines, quests, xp (Server.MCP.OperatorAPI)" do
    test "the full loop: status, create a routine and a quest, edit, stamp done, stamp twice" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Home", type: "home"})

      {200, status} = get_json("/api/life/#{ws.id}")

      assert status == %{
               "xp" => 0,
               "level" => 0,
               "next_level_at" => 100,
               "streaks" => %{},
               "due" => [],
               "quests" => [],
               "today" => []
             }

      {201, r} = post_json("/api/life/#{ws.id}/routines", %{title: "stretch", every: "@daily"})
      assert r["title"] == "stretch" and r["every"] == "@daily"

      # "@daily"'s first occurrence is strictly after created_at — backdate it so there's
      # already a due instance to stamp (mirrors Server.LifeTest's routine_done/2 setup).
      past = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-90_000, :second)
      Server.Routine |> Server.Repo.get!(r["id"]) |> Ecto.Changeset.change(created_at: past) |> Server.Repo.update!()

      {200, edited} = request_json(:patch, "/api/life/routines/#{r["id"]}", %{window_minutes: 30})
      assert edited["window_minutes"] == 30

      {201, q} = post_json("/api/life/#{ws.id}/quests", %{title: "dentist"})
      assert q["title"] == "dentist"

      {200, %{"run" => run, "level_up" => false}} = post_json("/api/life/routines/#{r["id"]}/done", %{})
      assert run["routine_id"] == r["id"]
      assert {409, _} = post_json("/api/life/routines/#{r["id"]}/done", %{})

      {200, %{"quest" => done_q, "level_up" => false}} = post_json("/api/life/quests/#{q["id"]}/done", %{})
      assert done_q["id"] == q["id"]
      assert {409, _} = post_json("/api/life/quests/#{q["id"]}/done", %{})
    end
  end
end
