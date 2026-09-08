defmodule Server.MCP.SpawnTest do
  # The spawn-or-join primitive under the launchers (funes:spawn / funes:claude /
  # pi:*). `ensure` is the shared core — open a fresh thread or join an existing one,
  # staff the agent — with NO token. `env`/`join` add the mint + the export block (the
  # pi/human path, a static bearer). `mint_for` is the Claude-Code `headersHelper` path:
  # a fresh token for an EXISTING (thread, agent), on every connect.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.MCP.Spawn
  alias Server.MCP.Tokens
  alias Server.Repo
  alias Server.Staff
  alias Server.Thread

  setup do
    Server.TestDB.clean!()
    :ok
  end

  describe "ensure/3 — spawn or join, no token" do
    test "{:open, title} opens a thread and staffs a freshly-registered agent" do
      assert {:ok, %{thread: t, agent: a} = result} = Spawn.ensure({:open, "new work"}, "codex")
      assert t.title == "new work"
      assert a.name == "codex"
      assert Repo.get(Thread, t.id).agent_id == a.id
      # the core mints nothing — exactly the two keys
      assert result |> Map.keys() |> Enum.sort() == [:agent, :thread]
    end

    test "{:join, id} joins an existing thread and assigns the agent" do
      {:ok, existing} = Channel.open_thread(%{title: "existing"})
      assert {:ok, %{thread: t, agent: a}} = Spawn.ensure({:join, existing.id}, "kimi")
      assert t.id == existing.id
      assert Repo.get(Thread, existing.id).agent_id == a.id
    end

    test "{:join, missing} errors, never silently opens a new thread" do
      assert {:error, {:no_thread, 999_999}} = Spawn.ensure({:join, 999_999}, "kimi")
    end

    test "reuses an existing agent by name (no duplicate registration)" do
      {:ok, agent} = Staff.register_agent(%{name: "dup", mandate: "m", engine: "e"})
      assert {:ok, %{agent: a}} = Spawn.ensure({:open, "t"}, "dup")
      assert a.id == agent.id
    end

    test "assign: false ensures the agent WITHOUT staffing the thread — the lead keeps the seat" do
      {:ok, %{thread: thread, agent: lead}} = Spawn.ensure({:open, "task thread"}, "claude-machine", mandate: "machine")
      assert Repo.get(Thread, thread.id).agent_id == lead.id

      assert {:ok, %{thread: t, agent: a}} =
               Spawn.ensure({:join, thread.id}, "reviewer-machine", mandate: "machine", assign: false)

      assert a.name == "reviewer-machine"
      # thread's lead is UNCHANGED — the reviewer never became the staffed agent
      assert Repo.get(Thread, t.id).agent_id == lead.id
    end

    test "assign: true (or omitted, the default) still reassigns — no regression" do
      {:ok, %{thread: thread, agent: lead}} = Spawn.ensure({:open, "task thread 2"}, "claude-machine", mandate: "machine")
      assert Repo.get(Thread, thread.id).agent_id == lead.id

      assert {:ok, %{thread: t, agent: a}} = Spawn.ensure({:join, thread.id}, "someone-else", mandate: "machine")
      assert Repo.get(Thread, t.id).agent_id == a.id
      refute Repo.get(Thread, t.id).agent_id == lead.id
    end
  end

  describe "env/3 and join/3 — mint + exports" do
    test "env/3 opens, mints, returns a valid token and the identity-only export block" do
      assert {:ok, %{thread: t, token: tok, exports: ex}} = Spawn.env("fresh", "codex")
      assert is_binary(tok)
      # The block carries identity, NOT a frozen token — the adapter mints per connect
      # against the URL's origin (POST /mint), so a pane is never stranded by a model
      # change or a secret regeneration.
      assert ex =~ ~s(TLON_MCP_URL="http://127.0.0.1:4040/mcp")
      assert ex =~ ~s(TLON_THREAD="#{t.id}")
      assert ex =~ ~s(TLON_AUTHOR="codex")
      refute ex =~ "TLON_TOKEN"
      assert {:ok, _binding} = Tokens.resolve(tok)
    end

    test "join/3 joins an existing thread and mints a token bound to it" do
      {:ok, existing} = Channel.open_thread(%{title: "join me"})
      assert {:ok, %{thread: t, token: tok, exports: ex}} = Spawn.join(existing.id, "codex")
      assert t.id == existing.id
      assert ex =~ ~s(TLON_THREAD="#{existing.id}")
      assert {:ok, _binding} = Tokens.resolve(tok)
    end

    test "join/3 errors on a missing thread" do
      assert {:error, {:no_thread, 999_999}} = Spawn.join(999_999, "codex")
    end

    # A coworker never writes in the main tree (Andrew, 2026-09-08): the block carries the
    # thread's worktree, ensured on the spot, for the boot script to cd into.
    test "the exports carry TLON_CWD = the thread's ensured worktree when its workspace has a repo" do
      %{repo: repo, ws: ws, project: p} = Server.TestRepoDir.with_project()
      {:ok, thread} = Channel.open_thread(%{title: "wt", workspace_id: ws.id, project_id: p.id})
      assert {:ok, %{exports: ex}} = Spawn.join(thread.id, "codex")
      wt = Server.Worktree.path(repo, "t#{thread.id}")
      assert ex =~ ~s(TLON_CWD="#{wt}")
      assert File.exists?(Path.join(wt, ".git"))
    end

    test "no repo anywhere → no TLON_CWD line, and the spawn still succeeds" do
      {:ok, thread} = Channel.open_thread(%{title: "no repo"})
      assert {:ok, %{exports: ex}} = Spawn.join(thread.id, "codex")
      refute ex =~ "TLON_CWD"
    end

    test "join/3 with assign: false mints a valid token/exports without staffing the thread" do
      {:ok, %{thread: existing, agent: lead}} = Spawn.ensure({:open, "leaded"}, "claude-machine", mandate: "machine")

      assert {:ok, %{thread: t, agent: a, token: tok, exports: ex}} =
               Spawn.join(existing.id, "reviewer-machine", mandate: "machine", assign: false)

      assert t.id == existing.id
      assert a.name == "reviewer-machine"
      assert ex =~ ~s(TLON_THREAD="#{existing.id}")
      assert ex =~ ~s(TLON_AUTHOR="reviewer-machine")
      # the token mints fine even though the reviewer never became the staffed lead
      assert {:ok, _binding} = Tokens.resolve(tok)
      assert Repo.get(Thread, existing.id).agent_id == lead.id
    end
  end

  describe "mint_for/2 — a fresh token for an EXISTING (thread, agent)" do
    test "mints for an existing thread + agent (the headersHelper path)" do
      {:ok, %{thread: t}} = Spawn.ensure({:open, "hh"}, "claude-code")
      assert {:ok, tok} = Spawn.mint_for(t.id, "claude-code")
      assert {:ok, _binding} = Tokens.resolve(tok)
    end

    test "a second mint_for yields the SAME token — deterministic, so a connect survives a restart" do
      # With stateless signed tokens the headersHelper re-mint is idempotent: the same (thread,
      # agent) always signs to the same token, which is exactly why it stays valid across a hub
      # restart (no random per-connect grant to invalidate).
      {:ok, %{thread: t}} = Spawn.ensure({:open, "hh"}, "claude-code")
      {:ok, first} = Spawn.mint_for(t.id, "claude-code")
      {:ok, second} = Spawn.mint_for(t.id, "claude-code")
      assert first == second
    end

    test "errors on a missing thread or agent" do
      {:ok, %{thread: t}} = Spawn.ensure({:open, "hh2"}, "claude-code")
      assert {:error, {:no_thread, 999_999}} = Spawn.mint_for(999_999, "claude-code")
      assert {:error, {:no_agent, "ghost"}} = Spawn.mint_for(t.id, "ghost")
    end
  end
end
