defmodule Server.Jobs.PassesTest do
  # The per-tick passes' durations, read off the rows Oban stamps (attempted_at, completed_at), and
  # the slow ones that skip ticks.
  use ExUnit.Case, async: false

  alias Server.Jobs.Passes

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp pass!(worker, took_s, ago_s \\ 60) do
    done = DateTime.add(DateTime.utc_now(), -ago_s)

    %{}
    |> Oban.Job.new(worker: worker, queue: "default")
    |> Ecto.Changeset.change(state: "completed", attempted_at: DateTime.add(done, -took_s), completed_at: done)
    |> Server.Repo.insert!()
  end

  test "recent: each pass worker's last durations in ms, newest first" do
    pass!("Server.Jobs.Staff", 2, 300)
    pass!("Server.Jobs.Staff", 41, 60)
    pass!("Server.Jobs.Drain", 1)

    assert %{"Staff" => [41_000, 2_000], "Drain" => [1_000]} = Map.new(Passes.recent())
  end

  test "slow: a worker whose newest pass took over 30 s, gone once a faster pass follows" do
    pass!("Server.Jobs.Staff", 41, 120)
    pass!("Server.Jobs.Dispatch", 3, 120)
    assert [{"Staff", 41_000}] = Passes.slow()

    pass!("Server.Jobs.Staff", 2, 30)
    assert Passes.slow() == []
  end

  test "slow: a pass long done is not news" do
    pass!("Server.Jobs.Staff", 41, 3600)
    assert Passes.slow() == []
  end

  defp running!(worker, for_s) do
    %{}
    |> Oban.Job.new(worker: worker, queue: "default")
    |> Ecto.Changeset.change(state: "executing", attempted_at: DateTime.add(DateTime.utc_now(), -for_s))
    |> Server.Repo.insert!()
  end

  test "slow: a pass still executing past 30 s counts, by how long it has run so far" do
    running!("Server.Jobs.Staff", 45)
    running!("Server.Jobs.Drain", 5)
    assert [{"Staff", ms}] = Passes.slow()
    assert ms >= 45_000 and ms < 50_000
  end

  test "slow_cached: read once, then served for 30 s without touching the table" do
    Passes.forget()
    assert Passes.slow_cached() == []
    pass!("Server.Jobs.Staff", 41, 60)
    assert Passes.slow_cached() == []
    Passes.forget()
    assert [{"Staff", 41_000}] = Passes.slow_cached()
    Passes.forget()
  end

  test "Maintain runs half a minute by design and is not a pass to watch" do
    pass!("Server.Jobs.Maintain", 50)
    assert Passes.slow() == []
  end
end
