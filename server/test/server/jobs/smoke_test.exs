defmodule Server.Jobs.SmokeTest do
  # The smoke of main's tip is run by the service: the job runs the release script (stubbed) to its
  # exit and keeps its log.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  alias Server.Smoke

  @sha String.duplicate("e", 40)

  setup do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    state = Path.join(System.tmp_dir!(), "xdg-state-#{System.pid()}-#{System.unique_integer([:positive])}")
    previous_state = System.get_env("XDG_STATE_HOME")
    System.put_env("XDG_STATE_HOME", state)

    on_exit(fn ->
      if previous_state,
        do: System.put_env("XDG_STATE_HOME", previous_state),
        else: System.delete_env("XDG_STATE_HOME")

      File.rm_rf(state)
    end)

    script = Path.join(System.tmp_dir!(), "smoke-stub-#{System.pid()}-#{System.unique_integer([:positive])}.sh")
    File.write!(script, ~s(#!/usr/bin/env bash\necho "ran-on: smoke $1"\n))
    Application.put_env(:server, :smoke_script, script)

    on_exit(fn ->
      Application.delete_env(:server, :smoke_script)
      File.rm(script)
    end)

    %{script: script, logs: Path.join([state, "tlon", "smoke"])}
  end

  test "a candidate smoke is about no thread: green is silent, red is the error the alarm says", %{script: script} do
    {:ok, job} = Smoke.queue_candidate(@sha)
    job = Server.Repo.reload!(job)
    assert %{"candidate" => true, "ref" => @sha} = job.args
    refute Map.has_key?(job.args, "thread_id")
    assert :ok = Server.Jobs.Smoke.perform(job)

    File.write!(script, "#!/usr/bin/env bash\necho \"smoke: the office never answered\"\nexit 3\n")
    assert {:error, why} = Server.Jobs.Smoke.perform(job)
    assert why =~ "smoke of #{String.slice(@sha, 0, 12)} failed (exit 3); the log: "
    assert File.read!(Server.Repo.reload!(job).meta["log"]) =~ "never answered"
  end

  test "the log lands in the smoke's state dir, not the OS tmp dir", %{logs: logs} do
    {:ok, job} = Smoke.queue_candidate(@sha)
    assert %{success: 1} = Oban.drain_queue(queue: :smoke)

    log = Server.Repo.reload(job).meta["log"]
    assert Path.dirname(log) == logs
    refute Path.dirname(log) == System.tmp_dir!()
    assert File.read!(log) =~ "ran-on: smoke #{@sha}"
  end

  test "each run prunes smoke logs older than 7 days and keeps fresh ones", %{logs: logs} do
    File.mkdir_p!(logs)
    stale = Path.join(logs, "old.log")
    fresh = Path.join(logs, "new.log")
    File.write!(stale, "old\n")
    File.write!(fresh, "new\n")
    File.touch!(stale, System.os_time(:second) - 8 * 86_400)

    {:ok, _} = Smoke.queue_candidate(@sha)
    assert %{success: 1} = Oban.drain_queue(queue: :smoke)

    refute File.exists?(stale)
    assert File.exists?(fresh)
  end
end
