defmodule Server.MCP.GatewayTest do
  # The /mint endpoint (Server.MCP.Gateway): an adapter mints a fresh token per connect
  # against its TLON_MCP_URL origin, so a pane is never stranded by a token-model
  # change or a secret regeneration. Proven END TO END over the wire (Bandit serves the
  # Gateway on a real loopback port, :httpc posts) — the same harness server_test uses.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.MCP
  alias Server.Staff

  @port 48_641
  @mint_url ~c"http://127.0.0.1:48641/mint"
  @mcp_url ~c"http://127.0.0.1:48641/mcp"

  setup_all do
    {:ok, _} = Application.ensure_all_started(:inets)
    :ok
  end

  setup do
    Server.TestDB.clean!()
    start_supervised!({MCP.Endpoint, transport: {:streamable_http, start: true}})
    start_supervised!({Bandit, plug: {Server.MCP.Gateway, []}, ip: {127, 0, 0, 1}, port: @port})

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
    {status, _body} = post_raw(@mint_url, "not json")
    assert status == 400
  end

  test "GET /mint is a 405 (POST only)" do
    {:ok, {{_http, status, _reason}, _headers, _body}} =
      :httpc.request(:get, {@mint_url, []}, [], body_format: :binary)

    assert status == 405
  end

  test "a non-/mint path forwards to the MCP server (the Gateway is a passthrough there)" do
    # A bare POST to /mcp with no bearer is the MCP server's 401 — proving the request
    # reached anubis through the Gateway, not the mint handler.
    {:ok, {{_http, status, _reason}, _headers, _body}} =
      :httpc.request(:post, {@mcp_url, [], ~c"application/json", ~s({"jsonrpc":"2.0","method":"initialize"})}, [],
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
    {status, decoded} = post_raw(@mint_url, JSON.encode!(body))
    {status, decoded}
  end

  defp post_raw(url, body) do
    {:ok, {{_http, status, _reason}, _headers, resp_body}} =
      :httpc.request(:post, {url, [], ~c"application/json", body}, [], body_format: :binary)

    decoded =
      if resp_body in [nil, "", []] do
        nil
      else
        JSON.decode!(to_string(resp_body))
      end

    {status, decoded}
  end

  defp get_json(path) do
    {:ok, {{_http, status, _reason}, _headers, body}} =
      :httpc.request(:get, {~c"http://127.0.0.1:48641" ++ String.to_charlist(path), []}, [], body_format: :binary)

    {status, JSON.decode!(body)}
  end

  defp post_json(path, map) do
    {:ok, {{_http, status, _reason}, _headers, body}} =
      :httpc.request(
        :post,
        {~c"http://127.0.0.1:48641" ++ String.to_charlist(path), [], ~c"application/json", JSON.encode!(map)},
        [],
        body_format: :binary
      )

    {status, JSON.decode!(body)}
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

    assert socket == "console-workspace-#{ws.id}" and session == "w#{ws.id}" and window == "t#{t.id}"
  end

  test "a workline's brief carries the gate, and the Claude Code Stop hook bounces a stop on a missing artifact" do
    # the artifact check runs git under the workline root: a throwaway repo, never this checkout
    tmp = Path.join(System.tmp_dir!(), "tlon-gateway-#{System.unique_integer([:positive])}")
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

    hook = Path.expand("../../../../adapters/claude-code/gate-hook.sh", __DIR__)
    env = [{"TLON_THREAD", Integer.to_string(wl.id)}, {"TLON_MCP_URL", "http://127.0.0.1:48641/mcp"}]
    # a first stop is refused with the reason on stderr
    {out, 2} =
      System.cmd("bash", ["-c", "echo '{\"stop_hook_active\":false}' | #{hook}"], env: env, stderr_to_stdout: true)

    assert out =~ "owed artifact is not committed"
    # a bounced turn is let through — never a forever loop
    {_, 0} = System.cmd("bash", ["-c", "echo '{\"stop_hook_active\":true}' | #{hook}"], env: env, stderr_to_stdout: true)
    # and a plain thread is a no-op
    {:ok, plain} = Channel.open_thread(%{title: "plain"})

    {_, 0} =
      System.cmd("bash", ["-c", "echo '{}' | #{hook}"],
        env: [{"TLON_THREAD", Integer.to_string(plain.id)} | tl(env)],
        stderr_to_stdout: true
      )
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
end
