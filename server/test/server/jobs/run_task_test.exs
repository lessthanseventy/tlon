defmodule Server.Jobs.RunTaskTest do
  # a coworker's long check runs as a job (the verify script stubbed: it prints what it was handed)
  # and its verdict comes back on the thread, addressed to whoever asked
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  alias Server.Jobs.RunTask

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})

    {_, 0} =
      System.cmd("sh", ["-c", "git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m one"],
        cd: tmp
      )

    {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp)
    {:ok, thread} = Server.Channel.open_thread(%{title: "a build"})

    script = Path.join(tmp, "fake-verify.sh")

    File.write!(script, ~S"""
    #!/usr/bin/env bash
    echo "argv=$* ref=$LAND_REF task=$RUN_TASK gate=$WORKLINE_GATE label=$CHECKS_LABEL"
    exit "${FAKE_EXIT:-0}"
    """)

    File.chmod!(script, 0o755)
    Application.put_env(:server, :run_task_script, script)
    on_exit(fn -> Application.delete_env(:server, :run_task_script) end)
    %{tree: tmp, sha: String.trim(sha), thread: thread}
  end

  test "a task off the list is refused, naming the list", %{tree: tree, thread: t} do
    assert {:error, why} = RunTask.enqueue(t.id, "emma", "release:cut", tree)
    assert why =~ "release:cut" and why =~ "office:test"
    refute_enqueued(worker: RunTask)
  end

  test "a listed task is queued on the checkout's committed head", %{tree: tree, sha: sha, thread: t} do
    assert {:ok, job} = RunTask.enqueue(t.id, "emma", "office:test", tree)
    assert %{agent: "emma", task: "office:test", ref: ^sha, tree: ^tree} = job.args
  end

  test "green: the caller is told on the thread, by name, so the post wakes them", %{tree: tree, sha: sha, thread: t} do
    {:ok, job} = RunTask.enqueue(t.id, "emma", "office:test", tree)
    assert :ok = perform_job(RunTask, job.args)

    [m] = t |> Server.Channel.thread_messages() |> Enum.filter(&(&1.body =~ "mise run"))
    assert m.body =~ "@emma"
    assert m.body =~ "✓ `mise run office:test` passed on #{String.slice(sha, 0, 7)}"
  end

  test "red: the exit and the run's tail come back", %{tree: tree, thread: t} do
    System.put_env("FAKE_EXIT", "1")
    on_exit(fn -> System.delete_env("FAKE_EXIT") end)
    {:ok, job} = RunTask.enqueue(t.id, "emma", "server:test", tree)
    assert :ok = perform_job(RunTask, job.args)

    [m] = t |> Server.Channel.thread_messages() |> Enum.filter(&(&1.body =~ "mise run"))
    assert m.body =~ "✗ `mise run server:test` failed (exit 1)"
    assert m.body =~ "task=server:test gate=1"
  end
end
