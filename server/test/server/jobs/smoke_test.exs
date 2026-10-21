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

  test "a thread with no slug and no ref is refused; it never queues the bare work/ ref", %{thread: t} do
    assert {:error, "no ref" <> _} = Smoke.start(%{t | slug: nil}, nil)
    refute_enqueued(worker: Server.Jobs.Smoke, args: %{ref: "work/"})
  end

  test "a ref ending in / is refused", %{thread: t} do
    assert {:error, "not a ref: " <> _} = Smoke.start(t, "work/")
    refute_enqueued(worker: Server.Jobs.Smoke, args: %{ref: "work/"})
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

  test "the smoke's notices go to whoever started it, not the thread's lead", %{thread: t} do
    {:ok, _} = Smoke.start(t, nil, "nolan")
    task = Task.async(fn -> Oban.drain_queue(queue: :smoke) end)

    wait_for(fn -> Enum.any?(bodies(t.id), &(&1 =~ "http://127.0.0.1:4999")) end)
    assert Enum.any?(bodies(t.id), &String.starts_with?(&1, "@nolan the smoke is up"))

    assert :ok = Smoke.stop(t.id)
    assert %{success: 1} = Task.await(task, 10_000)
  end

  test "the hold line names the smoke's build dir beside its url" do
    re = Server.Jobs.Smoke.hold_line()

    assert [_, "http://127.0.0.1:4999", "/tmp/tlon-smoke/Ab1"] =
             Regex.run(re, "smoke: holding http://127.0.0.1:4999 up (dir /tmp/tlon-smoke/Ab1) — x")

    assert [_, "http://127.0.0.1:4999"] = Regex.run(re, "smoke: holding http://127.0.0.1:4999 up — x")
  end

  test "drive runs the candidate's script from the smoke's dir, through the smoke's launcher", %{thread: t} do
    dir = Path.join(System.tmp_dir!(), "smoke-dir-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "scripts"))
    drive = Path.join(dir, "scripts/office-drive.sh")

    File.write!(
      drive,
      ~s(#!/usr/bin/env bash\necho "cwd=$PWD argv=$* yes=$MISE_YES url=$TLON_URL"\necho "wide=$OFFICE_WIDE text=$OFFICE_TEXT sandbox=$OFFICE_SANDBOX"\n)
    )

    File.chmod!(drive, 0o755)
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, _} =
      %{thread_id: t.id, ref: "x"}
      |> Server.Jobs.Smoke.new(state: "executing", meta: %{"url" => "http://127.0.0.1:4999", "dir" => dir})
      |> Oban.insert()

    assert {:ok, out} = Smoke.drive(t.id, ["/", "Enter"])
    assert out =~ "cwd=#{dir} argv=/ Enter yes=1 url=http://127.0.0.1:4999"
    assert out =~ "wide= text= sandbox="

    assert {:ok, out} = Smoke.drive(t.id, ["E"], wide: true, sandbox: true)
    assert out =~ "wide=1 text=1 sandbox=1"
  end

  test "start carries fixtures into the job's args, and leaves them out when there are none", %{thread: t} do
    {:ok, _} = Smoke.start(t, nil, "qa1", [], ["tool_denied_need"])
    assert_enqueued(worker: Server.Jobs.Smoke, args: %{thread_id: t.id, fixtures: ["tool_denied_need"]})
    {:ok, job} = Smoke.start(t, "main", "qa1", [], [])
    refute Map.has_key?(Server.Repo.reload(job).args, "fixtures")
  end

  test "a malformed fixture name is refused", %{thread: t} do
    assert {:error, "not a fixture name: " <> _} = Smoke.start(t, nil, "qa1", [], ["Bad Name; rm"])
    refute_enqueued(worker: Server.Jobs.Smoke)
  end

  test "the job hands its fixtures to the script, space-joined", %{thread: t} do
    File.write!(Smoke.script(), "#!/usr/bin/env bash\necho \"fixtures=$TLON_SMOKE_FIXTURES.\"\nexit 1\n")
    {:ok, _} = Smoke.start(t, nil, nil, [], ["a_set", "b_set"])
    {:ok, _} = Smoke.start(t, "main", nil, [], [])
    assert %{success: 2} = Oban.drain_queue(queue: :smoke)
    assert Enum.any?(bodies(t.id), &(&1 =~ "fixtures=a_set b_set."))
    assert Enum.any?(bodies(t.id), &(&1 =~ "fixtures=."))
  end

  describe "a smoke still building" do
    setup %{thread: t} do
      {:ok, job} = Smoke.start(t, nil, "qa1")
      job |> Ecto.Changeset.change(state: "executing") |> Server.Repo.update!()
      %{job: job}
    end

    test "drive and stop say it is building, with the job, not that no smoke is up", %{thread: t, job: job} do
      assert {:error, "building since " <> _ = why} = Smoke.drive(t.id, ["/"])
      assert why =~ "(job #{job.id})"
      assert {:error, "building since " <> _} = Smoke.stop(t.id)
    end

    test "a start for the same ref returns the building job instead of a second build", %{thread: t, job: job} do
      assert {:ok, %{id: id}} = Smoke.start(t, nil, "qa1")
      assert id == job.id
      assert Smoke.building(t.id).id == job.id
    end

    test "a start for another ref still queues", %{thread: t, job: job} do
      assert {:ok, %{id: id}} = Smoke.start(t, "main", "qa1")
      refute id == job.id
    end
  end

  test "a smoke that fails posts its last lines", %{thread: t} do
    File.write!(Smoke.script(), "#!/usr/bin/env bash\necho 'smoke FAILED: no build'\nexit 1\n")
    {:ok, _} = Smoke.start(t, nil)
    assert %{success: 1} = Oban.drain_queue(queue: :smoke)
    assert Enum.any?(bodies(t.id), &(&1 =~ "smoke FAILED: no build"))
  end
end
