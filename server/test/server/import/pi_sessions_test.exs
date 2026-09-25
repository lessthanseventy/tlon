defmodule Server.Import.PiSessionsTest do
  # pi transcripts (~/.pi/{agent,profiles/*}/sessions/*/*.jsonl) → closed, backdated threads,
  # the same shape the Claude Code import makes.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Import.PiSessions
  alias Server.Message
  alias Server.Projects
  alias Server.Repo
  alias Server.Thread
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    dir = Path.join(System.tmp_dir!(), "pi-sessions-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, ws} = Workspaces.register(%{name: "Home"})
    {:ok, exc} = Projects.register(%{workspace_id: ws.id, name: "exc", repos: [%{"path" => "/p/exc"}]})
    {:ok, ws: ws, exc: exc, dir: dir}
  end

  defp transcript(dir, where, id, cwd, messages) do
    path = Path.join([dir, where, "sessions", "--p-exc--", id <> ".jsonl"])
    File.mkdir_p!(Path.dirname(path))
    head = %{"type" => "session", "version" => 3, "id" => id, "timestamp" => "2026-09-09T01:00:00.000Z", "cwd" => cwd}
    File.write!(path, Enum.map_join([head | messages], "\n", &JSON.encode!/1))
  end

  defp user(text, ts),
    do: %{
      "type" => "message",
      "timestamp" => ts,
      "message" => %{"role" => "user", "content" => [%{"type" => "text", "text" => text}]}
    }

  defp said(text, ts),
    do: %{
      "type" => "message",
      "timestamp" => ts,
      "message" => %{
        "role" => "assistant",
        "content" => [%{"type" => "thinking", "thinking" => "hm"}, %{"type" => "text", "text" => text}]
      }
    }

  defp tool_result(ts),
    do: %{
      "type" => "message",
      "timestamp" => ts,
      "message" => %{"role" => "toolResult", "content" => [%{"type" => "text", "text" => "ok"}]}
    }

  test "a pi session becomes a closed thread on the cwd's project, pi answering", ctx do
    transcript(ctx.dir, "agent", "p1", "/p/exc", [
      user("could excessibility tie into phoenix_test?", "2026-09-09T01:14:58.000Z"),
      said("Looking.", "2026-09-09T01:15:00.000Z"),
      tool_result("2026-09-09T01:15:01.000Z"),
      said("Yes: wrap its visit/2.", "2026-09-09T01:15:10.000Z")
    ])

    assert {:ok, %{imported: 1}} = PiSessions.import_dir(ctx.dir, ctx.ws.id)

    thread = Repo.one!(Thread)
    assert %{title: "could excessibility tie into phoenix_test?", state: "closed", repo: "/p/exc"} = thread
    assert thread.project_id == ctx.exc.id

    assert [
             {"tlon", "↳ imported from pi session p1"},
             {"andrew", "could excessibility tie into phoenix_test?"},
             {"pi", "Yes: wrap its visit/2."}
           ] = Repo.all(from m in Message, where: m.thread_id == ^thread.id, order_by: m.id, select: {m.author, m.body})
  end

  test "coworker profiles are read too; machine-driven sessions are skipped; a re-run imports nothing twice", ctx do
    transcript(ctx.dir, "profiles/tlon", "p1", "/p/exc", [
      user("you are pi running in tlon", "2026-09-09T01:00:01.000Z"),
      said("hi", "2026-09-09T01:00:02.000Z")
    ])

    transcript(ctx.dir, "agent", "p2", "/p/exc", [
      user("you have 1 unread message(s) on your threads", "2026-09-09T01:00:01.000Z")
    ])

    transcript(ctx.dir, "agent", "p3", "/p/exc", [
      user(Path.expand("~/.pi/agent/npm/node_modules/pi-research/x"), "2026-09-09T01:00:01.000Z")
    ])

    transcript(ctx.dir, "agent", "p4", "/p/exc", [user("[tlon thread #9] andrew: a joke", "2026-09-09T01:00:01.000Z")])

    assert {:ok, %{imported: 1, skipped: 3}} = PiSessions.import_dir(ctx.dir, ctx.ws.id)
    assert {:ok, %{imported: 0, skipped: 4}} = PiSessions.import_dir(ctx.dir, ctx.ws.id)
  end
end
