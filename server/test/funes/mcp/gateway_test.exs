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
    start_supervised!({MCP.Endpoint, transport: :streamable_http})
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
end
