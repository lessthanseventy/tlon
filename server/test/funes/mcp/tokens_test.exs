defmodule Server.MCP.TokensTest do
  # The identity seam (pi doc §2a): a token binds an MCP connection to its (thread, agent), so
  # identity is a property of the connection, never a call parameter. STATELESS + signed: the
  # token IS its claims (HMAC over thread/agent), so it survives a node restart — the aleph hub
  # restarts constantly and must not 401 every session. The live session is resolved at read
  # time, so a token never grants a stale one.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.MCP.Tokens
  alias Server.Staff

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
    {:ok, agent} = Staff.register_agent(%{name: "Carl", mandate: "m", engine: "e"})
    %{thread: thread, agent: agent}
  end

  test "mint/2 → resolve/1 round-trips the binding; no session until register", %{thread: thread, agent: agent} do
    token = Tokens.mint(thread, agent)

    assert {:ok, binding} = Tokens.resolve(token)
    assert binding.thread_id == thread.id
    assert binding.agent_id == agent.id
    assert binding.agent == "Carl"
    # No live session for the pair yet → nil, honest, never a placeholder.
    assert binding.session_id == nil
  end

  test "a garbled or unsigned token resolves to :error" do
    assert Tokens.resolve("no-such-token") == :error
    assert Tokens.resolve("only-one-part") == :error
  end

  test "a tampered payload fails the signature check", %{thread: thread, agent: agent} do
    [_payload, sig] = thread |> Tokens.mint(agent) |> String.split(".", parts: 2)
    forged = Base.url_encode64(~s({"t":999,"a":999,"n":"mallory"}), padding: false) <> "." <> sig
    assert Tokens.resolve(forged) == :error
  end

  test "the token is DETERMINISTIC — same (thread, agent) → same token, so it survives a restart", %{
    thread: thread,
    agent: agent
  } do
    # A node restart re-reads the same workspace key (Server.MCP.Secret), so a token minted before it
    # verifies after: determinism IS the restart-survival property the registry lacked.
    assert Tokens.mint(thread, agent) == Tokens.mint(thread, agent)
  end

  test "resolve attaches the CURRENT live session automatically — no bind step", %{thread: thread, agent: agent} do
    token = Tokens.mint(thread, agent)
    assert {:ok, %{session_id: nil}} = Tokens.resolve(token)

    {:ok, session} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w1"})
    assert {:ok, %{session_id: sid}} = Tokens.resolve(token)
    assert sid == session.id
  end

  test "resolve follows the live session across a supersede — never a stale one", %{thread: thread, agent: agent} do
    token = Tokens.mint(thread, agent)
    {:ok, old} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w1"})
    {:ok, _} = Staff.end_session(old)
    {:ok, fresh} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w2"})

    assert {:ok, %{session_id: sid}} = Tokens.resolve(token)
    assert sid == fresh.id
  end
end
