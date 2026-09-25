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

  test "a transcript still being written is left for a later run, not frozen half-way", ctx do
    Application.put_env(:server, :import_live_window_s, 3600)
    on_exit(fn -> Application.put_env(:server, :import_live_window_s, 0) end)

    path =
      transcript(ctx.dir, "live", [user("keep going", "2026-09-01T10:00:00Z"), said("On it.", "2026-09-01T10:00:01Z")])

    File.touch!(path, System.os_time(:second))

    assert {:ok, %{imported: 0, skipped: 1}} = ClaudeSessions.import_dir(ctx.dir, ctx.ws.id)

    File.touch!(path, System.os_time(:second) - 2 * 3600)
    assert {:ok, %{imported: 1}} = ClaudeSessions.import_dir(ctx.dir, ctx.ws.id)
  end

  test "the thread records which of its project's repos the session ran in", ctx do
    repos = [%{"name" => "ficciones", "path" => "/p/ficciones"}, %{"name" => "mix_master", "path" => "/p/mix_master"}]
    {:ok, tlon} = Projects.register(%{workspace_id: ctx.ws.id, name: "tlon", repos: repos})

    transcript(ctx.dir, "s1", [
      %{
        "type" => "user",
        "cwd" => "/p/mix_master/lib",
        "timestamp" => "2026-09-01T10:00:00Z",
        "message" => %{"role" => "user", "content" => "fix the board"}
      },
      said("Fixed.", "2026-09-01T10:00:01Z")
    ])

    assert {:ok, %{imported: 1}} = ClaudeSessions.import_dir(ctx.dir, ctx.ws.id)
    assert %{project_id: pid, repo: "/p/mix_master"} = Repo.one!(Thread)
    assert pid == tlon.id
  end

  test "a switchboard wake is not a conversation: its text already lives in the thread it woke", ctx do
    transcript(ctx.dir, "s1", [
      user("[tlon thread #9] andrew: make me laugh", "2026-09-01T10:00:00Z"),
      said("no", "2026-09-01T10:00:01Z")
    ])

    transcript(ctx.dir, "s2", [
      user("[funes thread #2] andrew: finish the joke", "2026-09-01T10:00:00Z"),
      said("no", "2026-09-01T10:00:01Z")
    ])

    assert {:ok, %{imported: 0, skipped: 2}} = ClaudeSessions.import_dir(ctx.dir, ctx.ws.id)
  end

  test "a resumed or forked session is one conversation: only its longest copy is imported", ctx do
    shared = [user("redesign the dashboard", "2026-09-01T10:00:00Z"), said("On it.", "2026-09-01T10:00:05Z")]

    transcript(
      ctx.dir,
      "branch",
      shared ++ [user("abandoned turn", "2026-09-01T10:01:00Z"), said("x", "2026-09-01T10:01:01Z")]
    )

    transcript(
      ctx.dir,
      "trunk",
      shared ++
        [
          user("keep going", "2026-09-01T10:02:00Z"),
          said("Done.", "2026-09-01T10:02:01Z"),
          user("commit", "2026-09-01T10:03:00Z"),
          said("Committed.", "2026-09-01T10:03:01Z")
        ]
    )

    assert {:ok, %{imported: 1, skipped: 1}} = ClaudeSessions.import_dir(ctx.dir, ctx.ws.id)
    thread = Repo.one!(Thread)
    assert Repo.exists?(from m in Message, where: m.thread_id == ^thread.id and m.body == "Committed.")
  end

  test "a session from outside every repo lands on the workspace's default project, whatever its name", ctx do
    {:ok, machine} = Projects.register(%{workspace_id: ctx.ws.id, name: "machine", repos: []})
    {:ok, _} = Workspaces.edit(ctx.ws, %{default_project_id: machine.id})

    transcript(ctx.dir, "s1", [
      %{
        "type" => "user",
        "cwd" => "/home/someone",
        "timestamp" => "2026-09-01T10:00:00Z",
        "message" => %{"role" => "user", "content" => "bluetooth is broken"}
      },
      said("Try re-pairing.", "2026-09-01T10:00:01Z")
    ])

    assert {:ok, %{imported: 1}} = ClaudeSessions.import_dir(ctx.dir, ctx.ws.id)
    assert Repo.one!(Thread).project_id == machine.id
  end

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
    transcript(ctx.dir, "s1", [
      user("hello, the build is red", "2026-09-01T10:00:00Z"),
      said("hi", "2026-09-01T10:00:01Z")
    ])

    transcript(ctx.dir, "s2", [user("You extract DURABLE knowledge…", "2026-09-01T10:00:00Z")])

    assert {:ok, %{imported: 1, skipped: 1}} = ClaudeSessions.import_dir(ctx.dir, ctx.ws.id)
    assert {:ok, %{imported: 0, skipped: 2}} = ClaudeSessions.import_dir(ctx.dir, ctx.ws.id)
    assert Repo.aggregate(Thread, :count) == 1
  end
end
