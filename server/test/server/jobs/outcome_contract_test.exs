defmodule Server.Jobs.OutcomeContractTest do
  # Every Oban worker under lib/server/jobs/ is about a thread or about none, and either way its
  # ending is said: on its thread (Server.Jobs.Outcome) or on the standing one (Server.Jobs.Alarm).
  # A worker in neither table fails here by name.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Jobs.Alarm
  alias Server.Jobs.Outcome
  alias Server.Message
  alias Server.Repo
  alias Server.Workspaces

  # a job about a thread: the args key that names it, and what a success returns — :posted when
  # the callee posts the outcome itself, {:quiet, why} when nothing is worth a line
  @bound %{
    Server.Jobs.Continue => {"thread_id", :posted},
    Server.Jobs.EndReview =>
      {"thread_id", {:quiet, "the verdict's line is the review's ending; this only closes the window"}},
    Server.Jobs.Grade => {"thread_id", :posted},
    Server.Jobs.Land => {"thread_id", :posted},
    Server.Jobs.Retro => {"thread_id", {:quiet, "lessons are banked on a thread already closed"}},
    Server.Jobs.RunTask => {"thread_id", :posted},
    Server.Jobs.Smoke => {"thread_id", :posted},
    Server.Jobs.TurnPass => {"thread_id", {:quiet, "a memory pass after every turn"}},
    Server.Jobs.Verify => {"thread_id", :posted}
  }

  # a job about no thread, and why
  @unbound %{
    Server.Jobs.AutoResume => "the office's pause, not a thread's",
    Server.Jobs.Diary => "the week's diary for a workspace",
    Server.Jobs.Dispatch => "the schedules' minute",
    Server.Jobs.Drain => "the switchboard's redelivery",
    Server.Jobs.Intake => "the backlog as a whole",
    Server.Jobs.KeepUp => "the checkouts, not a thread",
    Server.Jobs.Maintain => "every workline's sweep",
    Server.Jobs.Release => "a cut names a sha, not a thread",
    Server.Jobs.RunSchedule => "a schedule run has its own record",
    Server.Jobs.ShiftBack => "a crew's offer back",
    Server.Jobs.Staff => "the staffing pass",
    Server.Jobs.Triage => "the tickets as a whole"
  }

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Home"})
    {:ok, general} = Channel.open_thread(%{title: "general", scope: "machine", workspace_id: ws.id})
    {:ok, work} = Channel.open_thread(%{title: "clock", workspace_id: ws.id})
    %{general: general, work: work}
  end

  defp workers do
    for file <- Path.wildcard(Path.join(__DIR__, "../../../lib/server/jobs/*.ex")),
        src = File.read!(file),
        String.contains?(src, "use Oban.Worker"),
        [_, name] = Regex.run(~r/defmodule (\S+) do/, src),
        do: {Module.concat([name]), src},
        into: %{}
  end

  defp meta(worker, args, state, result) do
    job = %Oban.Job{worker: inspect(worker), args: args, attempt: 3, max_attempts: 3}
    %{job: job, worker: inspect(worker), state: state, result: result}
  end

  defp ending(meta) do
    :ok = Outcome.handle([:oban, :job, :exception], %{}, meta, nil)
    :ok = Alarm.handle([:oban, :job, :exception], %{}, meta, nil)
  end

  defp bodies(thread), do: Repo.all(from m in Message, where: m.thread_id == ^thread.id, order_by: m.id, select: m.body)

  test "every worker is about a thread or about none" do
    found = workers() |> Map.keys() |> MapSet.new()
    listed = MapSet.union(MapSet.new(Map.keys(@bound)), MapSet.new(Map.keys(@unbound)))

    assert MapSet.equal?(found, listed),
           "in neither table: #{found |> MapSet.difference(listed) |> Enum.to_list() |> inspect()}"

    assert Map.keys(@bound) -- Map.keys(@unbound) == Map.keys(@bound)
  end

  test "a bound job's perform reads its thread key, and its bad ending is one ✗ line on that thread", ctx do
    sources = workers()

    for {worker, {key, _success}} <- @bound do
      assert String.contains?(sources[worker], ~s("#{key}")), "#{inspect(worker)} never reads #{key}"
      ending(meta(worker, %{key => ctx.work.id}, :discard, {:error, "boom #{inspect(worker)}"}))
    end

    assert bodies(ctx.work) == Enum.map(Map.keys(@bound), &"✗ #{inspect(&1)}: boom #{inspect(&1)}")
    assert bodies(ctx.general) == []
  end

  test "an unbound job's discard is one ⚠ line on the standing thread, and nothing anywhere else", ctx do
    for {worker, why} <- @unbound do
      assert is_binary(why) and why != ""
      ending(meta(worker, %{}, :discard, {:error, "boom"}))
    end

    assert length(bodies(ctx.general)) == map_size(@unbound)
    assert Enum.all?(bodies(ctx.general), &String.starts_with?(&1, "⚠ job Server.Jobs."))
    assert bodies(ctx.work) == []
  end

  test "a nil thread falls back to the standing thread; a thread gone does too", ctx do
    ending(meta(Server.Jobs.Land, %{"on_thread" => nil, "pr" => 1}, :discard, {:error, "no gate"}))
    ending(meta(Server.Jobs.Verify, %{"thread_id" => ctx.work.id + 1000}, :discard, {:error, "gone"}))
    assert bodies(ctx.general) == ["✗ Server.Jobs.Land: no gate", "✗ Server.Jobs.Verify: gone"]
  end

  test "a quiet success needs a reason; a loud one posts ✓ done; a cancel and a retry say so" do
    for {_worker, {_key, success}} <- @bound,
        do: assert(match?(:posted, success) or match?({:quiet, <<_, _::binary>>}, success))

    job = %Oban.Job{worker: "Server.Jobs.Verify", args: %{"thread_id" => 1}, attempt: 1, max_attempts: 3}
    assert Outcome.line(%{job: job, state: :success, result: :ok}) == "✓ Server.Jobs.Verify done"
    assert Outcome.line(%{job: job, state: :success, result: {:ok, "verified at abc"}}) == "✓ verified at abc"
    assert Outcome.line(%{job: job, state: :success, result: {:ok, :quiet}}) == nil
    assert Outcome.line(%{job: job, state: :success, result: {:ok, :posted}}) == nil
    assert Outcome.line(%{job: job, state: :snoozed, result: {:snooze, 60}}) == nil
    assert Outcome.line(%{job: job, state: :cancelled, result: {:cancel, "closed"}}) == "✗ Server.Jobs.Verify: closed"

    assert Outcome.line(%{job: job, state: :failure, result: {:error, "cut off"}}) ==
             "✗ Server.Jobs.Verify: cut off — retrying (1/3)"

    assert Outcome.line(%{job: job, state: :discard, result: nil, error: %RuntimeError{message: "boom\nmore"}}) ==
             "✗ Server.Jobs.Verify: boom"
  end

  test "a PR landing recorded with no thread posts its refusal on the standing thread", ctx do
    assert {:error, _} =
             Server.PRLanding.land(%{"pr" => 7, "branch" => "main", "on_thread" => nil}, repo: System.tmp_dir!())

    assert ["PR #7 (main): ✗ not landed: main is never landed" <> _] = bodies(ctx.general)
  end
end
