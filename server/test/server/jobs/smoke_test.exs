defmodule Server.Jobs.SmokeTest do
  # QA's held smoke is run by the service: the tool queues the job, the job runs the release script
  # (stubbed: it prints the line the real one prints when it holds) and posts the url on the thread.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  alias Server.Channel
  alias Server.Smoke

  @stub """
  #!/usr/bin/env bash
  trap 'exit 0' TERM
  echo "smoke: abc1234 on :4999"
  echo "smoke: holding http://127.0.0.1:4999 up — TLON_URL=http://127.0.0.1:4999 mise run office:drive -- <keys>"
  while true; do sleep 0.1; done
  """

  setup do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    script = Path.join(System.tmp_dir!(), "smoke-stub-#{System.pid()}-#{System.unique_integer([:positive])}.sh")
    File.write!(script, @stub)
    Application.put_env(:server, :smoke_script, script)

    on_exit(fn ->
      Application.delete_env(:server, :smoke_script)
      File.rm(script)
    end)

    {:ok, thread} = Server.Workline.open(%{title: "office: a thing", slug: "a-thing", stage: "review"})
    %{thread: thread}
  end

  defp bodies(tid), do: tid |> Channel.thread() |> Channel.thread_messages() |> Enum.map(& &1.body)

  defp wait_for(fun, n \\ 100) do
    cond do
      fun.() -> :ok
      n == 0 -> flunk("timed out")
      true -> Process.sleep(50) && wait_for(fun, n - 1)
    end
  end

  test "start queues the job for the workline's branch; a bad ref is refused", %{thread: t} do
    assert {:ok, _} = Smoke.start(t, nil)
    assert_enqueued(worker: Server.Jobs.Smoke, args: %{thread_id: t.id, ref: "work/a-thing"})
    assert {:error, "not a ref: " <> _} = Smoke.start(t, "--upload-pack=x")
  end

  test "the job posts the held url on the thread, and stop tears it down", %{thread: t} do
    {:ok, _} = Smoke.start(t, nil)
    task = Task.async(fn -> Oban.drain_queue(queue: :smoke) end)

    wait_for(fn -> Enum.any?(bodies(t.id), &(&1 =~ "http://127.0.0.1:4999")) end)
    assert Enum.any?(bodies(t.id), &(&1 =~ "drive_smoke"))
    assert {:error, "a smoke is already up" <> _} = Smoke.start(t, nil)

    assert :ok = Smoke.stop(t.id)
    assert %{success: 1} = Task.await(task, 10_000)
    assert Smoke.held(t.id) == nil
    assert {:error, "no smoke is up for this thread"} = Smoke.stop(t.id)
  end

  test "a smoke that fails posts its last lines", %{thread: t} do
    File.write!(Smoke.script(), "#!/usr/bin/env bash\necho 'smoke FAILED: no build'\nexit 1\n")
    {:ok, _} = Smoke.start(t, nil)
    assert %{success: 1} = Oban.drain_queue(queue: :smoke)
    assert Enum.any?(bodies(t.id), &(&1 =~ "smoke FAILED: no build"))
  end
end
