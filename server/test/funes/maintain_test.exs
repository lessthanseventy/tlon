defmodule Server.MaintainTest do
  # Worklines slice 6: the Maintain back-edge. Deterministic monitors detect control-band
  # breaches and act with NO human in the invocation path — but everything they open lands
  # GATED (machine-born), so the loop closes without ever acting unsupervised.
  use ExUnit.Case, async: false

  alias Server.Maintain.Monitor
  alias Server.Message
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline
  alias Server.Workline.Artifacts

  defmodule AllPresent do
    @moduledoc false
    @behaviour Artifacts

    @impl true
    def check(_thread, _requirement), do: {:ok, "present"}
  end

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp start_monitor(opts) do
    defaults = [name: nil, sweep_interval_ms: to_timeout(hour: 1), gate_stale_ms: 0, stalled_ms: 0]
    start_supervised!({Monitor, Keyword.merge(defaults, opts)})
  end

  defp drain(pid), do: Monitor.drain(pid)

  test "flag opens a machine-born workline already parked at the intent gate, evidence first" do
    {:ok, flagged} = Workline.flag(%{title: "maintain: x stalled", slug: "maint-x"}, "breach: no advance in 3d")

    assert flagged.born == "machine"
    assert flagged.stage == "intent"
    assert flagged.awaiting == "andrew"
    bodies = Message |> Repo.all() |> Enum.filter(&(&1.thread_id == flagged.id)) |> Enum.map(& &1.body)
    assert Enum.any?(bodies, &(&1 =~ "breach"))
  end

  defmodule NonePresent do
    @moduledoc false
    @behaviour Artifacts

    @impl true
    def check(_thread, requirement), do: {:error, "missing #{inspect(requirement)}"}
  end

  test "approve re-verifies the owed artifact — a vanished artifact keeps the gate parked" do
    thread = open_parked_gate("reverify")

    assert {:error, {:artifact_missing, _}} = Workline.approve(thread, artifacts: NonePresent)
    assert Repo.get!(Thread, thread.id).awaiting == "andrew"

    assert {:ok, approved} = Workline.approve(thread, artifacts: AllPresent)
    assert approved.stage == "plan"
  end

  test "approving a machine-born intent materializes intent.md from the evidence — one verb, chain intact" do
    tmp = Path.join(System.tmp_dir!(), "workline-flag-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    {_, 0} = System.cmd("git", ["-C", tmp, "init", "-q"], stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["-C", tmp, "config", "user.email", "t@t"], stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["-C", tmp, "config", "user.name", "t"], stderr_to_stdout: true)
    previous = Application.get_env(:server, :workline_root)
    Application.put_env(:server, :workline_root, tmp)

    on_exit(fn ->
      Application.put_env(:server, :workline_root, previous)
      File.rm_rf!(tmp)
    end)

    {:ok, flagged} = Workline.flag(%{title: "no artifact", slug: "maint-bare"}, "breach evidence text")

    assert {:ok, approved} = Workline.approve(flagged)
    assert approved.stage == "spec"
    assert File.read!(Path.join(tmp, "work/maint-bare/intent.md")) =~ "breach evidence text"
  end

  test "a stale parked gate gets a reminder post, once per nag interval" do
    thread = open_parked_gate("stale-gate")
    monitor = start_monitor(renag_ms: to_timeout(day: 1))

    send(monitor, :sweep)
    :ok = drain(monitor)
    send(monitor, :sweep)
    :ok = drain(monitor)

    reminders =
      Message |> Repo.all() |> Enum.filter(&(&1.thread_id == thread.id and &1.body =~ "still parked"))

    assert length(reminders) == 1
  end

  test "a stalled workline is flagged as a machine-born intent, once per slug" do
    {:ok, stalled} = Workline.open(%{title: "going nowhere", slug: "stuck"})
    monitor = start_monitor([])

    send(monitor, :sweep)
    :ok = drain(monitor)
    send(monitor, :sweep)
    :ok = drain(monitor)

    flags = Thread |> Repo.all() |> Enum.filter(&(&1.slug == "maint-stuck"))
    assert [flag] = flags
    assert flag.born == "machine"
    assert flag.awaiting == "andrew"
    assert stalled.id != flag.id
  end

  test "a merged workline never breaches" do
    thread = walk_to_merged("done-line")
    monitor = start_monitor([])

    send(monitor, :sweep)
    :ok = drain(monitor)

    assert Thread |> Repo.all() |> Enum.filter(&(&1.slug == "maint-done-line")) == []
    assert Repo.get!(Thread, thread.id).stage == "merged"
  end

  defp open_parked_gate(slug) do
    {:ok, thread} = Workline.open(%{title: slug, slug: slug})
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
    parked
  end

  defp walk_to_merged(slug) do
    {:ok, t} = Workline.open(%{title: slug, slug: slug})
    {:ok, t} = Workline.advance(t, artifacts: AllPresent)
    {:awaiting, t} = Workline.advance(t, artifacts: AllPresent)
    {:ok, t} = Workline.approve(t, artifacts: AllPresent)
    {:ok, t} = Workline.advance(t, artifacts: AllPresent)
    {:ok, t} = Workline.advance(t, artifacts: AllPresent)
    {:ok, t} = Workline.advance(t, artifacts: AllPresent)
    {:awaiting, t} = Workline.advance(t, artifacts: AllPresent)
    {:ok, t} = Workline.approve(t, artifacts: AllPresent)
    t
  end
end
