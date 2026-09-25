defmodule Server.Import.ClaudeSessionsTest do
  # Claude Code transcripts → closed, backdated, unstaffed threads (the GEB import).
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Import.ClaudeSessions
  alias Server.Message
  alias Server.Projects
  alias Server.Repo
  alias Server.Thread
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    dir = Path.join(System.tmp_dir!(), "claude-sessions-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, ws} = Workspaces.register(%{name: "Home"})
    {:ok, general} = Projects.register(%{workspace_id: ws.id, name: "general", repos: [%{"path" => "/nowhere"}]})
    {:ok, repo} = Projects.register(%{workspace_id: ws.id, name: "exc", repos: [%{"path" => "/p/exc"}]})
    File.mkdir_p!(Path.join(dir, "-p-exc"))
    {:ok, ws: ws, general: general, repo: repo, dir: dir}
  end

  defp transcript(dir, id, entries) do
    path = Path.join([dir, "-p-exc", id <> ".jsonl"])
    File.write!(path, Enum.map_join(entries, "\n", &JSON.encode!/1))
    path
  end

  defp user(text, ts),
    do: %{"type" => "user", "cwd" => "/p/exc/lib", "timestamp" => ts, "message" => %{"role" => "user", "content" => text}}

  defp said(text, ts),
    do: %{"type" => "assistant", "timestamp" => ts, "message" => %{"content" => [%{"type" => "text", "text" => text}]}}

  defp tool_result(ts),
    do: %{
      "type" => "user",
      "timestamp" => ts,
      "message" => %{"role" => "user", "content" => [%{"type" => "tool_result"}]}
    }

  test "a session becomes a closed thread on the cwd's project: prompts, then each turn's LAST reply", ctx do
    transcript(ctx.dir, "s1", [
      user("<command-name>/model</command-name>", "2026-09-01T10:00:00Z"),
      user("fix the flaky test", "2026-09-01T10:00:01Z"),
      said("Looking.", "2026-09-01T10:00:02Z"),
      tool_result("2026-09-01T10:00:03Z"),
      said("Fixed: the sleep was the race.", "2026-09-01T10:00:04Z"),
      user("thanks, commit it", "2026-09-01T10:01:00Z"),
      said("Committed.", "2026-09-01T10:01:05Z"),
      %{"type" => "ai-title", "aiTitle" => "Flaky test fix"}
    ])

    assert {:ok, %{imported: 1}} = ClaudeSessions.import_dir(ctx.dir, ctx.ws.id)

    thread = Repo.one!(Thread)
    assert %{title: "Flaky test fix", state: "closed", agent_id: nil} = thread
    assert thread.project_id == ctx.repo.id

    bodies = Repo.all(from m in Message, where: m.thread_id == ^thread.id, order_by: m.id, select: {m.author, m.body})

    assert [
             {"tlon", "↳ imported from Claude Code session s1"},
             {"andrew", "fix the flaky test"},
             {"claude-code", "Fixed: the sleep was the race."},
             {"andrew", "thanks, commit it"},
             {"claude-code", "Committed."}
           ] = bodies

    assert Repo.all(from m in Message, where: is_nil(m.delivered_at)) == []
  end

  test "a re-run imports nothing twice; a machine-driven session is skipped", ctx do
    transcript(ctx.dir, "s1", [user("hello", "2026-09-01T10:00:00Z"), said("hi", "2026-09-01T10:00:01Z")])
    transcript(ctx.dir, "s2", [user("You extract DURABLE knowledge…", "2026-09-01T10:00:00Z")])

    assert {:ok, %{imported: 1, skipped: 1}} = ClaudeSessions.import_dir(ctx.dir, ctx.ws.id)
    assert {:ok, %{imported: 0, skipped: 2}} = ClaudeSessions.import_dir(ctx.dir, ctx.ws.id)
    assert Repo.aggregate(Thread, :count) == 1
  end
end
