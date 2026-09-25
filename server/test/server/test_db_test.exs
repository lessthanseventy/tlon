defmodule Server.TestDBTest do
  # The suite shares one :test_pid; a background task a test started (the switchboard's opening
  # turn) must finish while that test still owns it, or it reports into the NEXT test's mailbox.
  use ExUnit.Case, async: false

  test "await_background/0 returns only once every supervised background task has finished" do
    me = self()

    {:ok, _} =
      Task.Supervisor.start_child(Server.TaskSupervisor, fn ->
        Process.sleep(100)
        send(me, :late_wake)
      end)

    Server.TestDB.await_background()

    assert Task.Supervisor.children(Server.TaskSupervisor) == []
    assert_received :late_wake
  end

  test "clean!/0 leaves no queued Oban job and no collection row for the next test to count" do
    Server.Repo.query!("INSERT INTO collection (source, last_attempt) VALUES ('leftover', '2026-08-14T00:00:00Z')")
    {:ok, _} = Server.Repo.insert(Oban.Job.new(%{thread_id: 1}, worker: "Server.Jobs.TurnPass", queue: "default"))

    Server.TestDB.clean!()

    assert %{rows: [[0]]} = Server.Repo.query!("SELECT count(*) FROM collection")
    assert %{rows: [[0]]} = Server.Repo.query!("SELECT count(*) FROM oban_jobs")
  end
end
