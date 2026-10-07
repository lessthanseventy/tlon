defmodule Server.SchedulesTest do
  # The operator's calendar: what is due, firing it once, and each kind's work.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  alias Server.Channel
  alias Server.Repo
  alias Server.Schedules

  # Oban up in manual mode: a run is queued, never performed behind the test's back
  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    {:ok, ws: ws}
  end

  defp schedule!(ws, attrs),
    do:
      elem(
        {:ok, _} = Schedules.create(Map.merge(%{workspace_id: ws.id, kind: "script", title: "t", body: "true"}, attrs)),
        1
      )

  defp later(min), do: DateTime.add(DateTime.utc_now(), min * 60)

  test "a schedule has a cron or a time, never both or neither, and a cron that parses", %{ws: ws} do
    base = %{workspace_id: ws.id, kind: "script", title: "t", body: "true"}
    assert {:error, _} = Schedules.create(base)
    assert {:error, _} = Schedules.create(Map.merge(base, %{cron: "* * * * *", at: later(5)}))
    assert {:error, cs} = Schedules.create(Map.put(base, :cron, "every tuesday"))
    assert cs.errors[:cron]
    assert {:ok, _} = Schedules.create(Map.put(base, :cron, "@daily"))
    assert {:error, _} = Schedules.create(Map.merge(base, %{cron: "* * * * *", kind: "cronjob"}))
  end

  test "a cron fires once per slot however many dispatchers ask; disabled never fires", %{ws: ws} do
    s = schedule!(ws, %{cron: "* * * * *"})
    off = schedule!(ws, %{cron: "* * * * *", enabled: false})
    now = later(2)

    assert [run] = Schedules.dispatch(now)
    assert run.schedule_id == s.id and run.status == "running"
    assert_enqueued(worker: Server.Jobs.RunSchedule, args: %{run_id: run.id})
    assert Schedules.dispatch(now) == []
    assert [_] = Schedules.dispatch(DateTime.add(now, 61))
    assert Schedules.runs(off.id) == []
  end

  test "a one-off fires when its time comes, then never again", %{ws: ws} do
    s = schedule!(ws, %{at: later(10)})
    assert Schedules.dispatch(later(5)) == []
    assert Schedules.next_at(s) == s.at
    assert [_] = Schedules.dispatch(later(11))
    assert Schedules.dispatch(later(30)) == []
    assert Schedules.next_at(Schedules.get(s.id)) == nil
  end

  test "an overdue slot is next now; a disabled schedule has no next", %{ws: ws} do
    s = schedule!(ws, %{cron: "* * * * *"})
    now = later(10)
    assert Schedules.next_at(s, now) == DateTime.truncate(now, :second)
    assert Schedules.next_at(%{s | enabled: false}, now) == nil
  end

  # The clocks go back in US Mountain time on 2026-11-01: 09:00 is 15:00Z the day before and 16:00Z
  # that day. The BEAM reads its zone once, at start (CI runs the suite with TZ=America/Denver).
  @mountain :calendar.universal_time_to_local_time({{2026, 10, 31}, {15, 0, 0}}) == {{2026, 10, 31}, {9, 0, 0}} and
              :calendar.universal_time_to_local_time({{2026, 11, 1}, {16, 0, 0}}) == {{2026, 11, 1}, {9, 0, 0}}
  @tag skip: if(@mountain, do: false, else: "needs TZ=America/Denver")
  test "a 9:00 cron fires at 9:00 local on both sides of a DST change; a slot that never happens is skipped", %{ws: ws} do
    nine = schedule!(ws, %{cron: "0 9 * * *"})
    before = %{nine | last_run_at: ~U[2026-10-31 15:00:00Z]}
    assert Schedules.next_at(before, ~U[2026-10-31 16:00:00Z]) == ~U[2026-11-01 16:00:00Z]

    # 2:30 on 2026-03-08 does not exist (clocks jump 2:00 → 3:00): the next real 2:30 is the 9th's
    half_two = %{schedule!(ws, %{cron: "30 2 * * *"}) | last_run_at: ~U[2026-03-07 09:30:00Z]}
    assert Schedules.next_at(half_two, ~U[2026-03-07 10:00:00Z]) == ~U[2026-03-09 08:30:00Z]
  end

  test "the days of a month it fires on", %{ws: ws} do
    mondays = schedule!(ws, %{cron: "0 9 * * 1"})
    assert Schedules.days(mondays, 2026, 10) == [5, 12, 19, 26]
    assert length(Schedules.days(schedule!(ws, %{cron: "*/5 * * * *"}), 2026, 2)) == 28
    once = schedule!(ws, %{at: ~U[2026-10-20 12:00:00Z]})
    assert [_] = Schedules.days(once, 2026, 10)
    assert Schedules.days(once, 2026, 11) == []
  end

  test "a script runs in its dir: exit and output on the run, failed when non-zero", %{ws: ws} do
    ok = schedule!(ws, %{cron: "@daily", body: "pwd; echo hello", dir: System.tmp_dir!()})
    {:ok, run} = Schedules.run_now(ok)
    done = Schedules.perform(run.id)
    assert {done.status, done.exit} == {"ok", 0}
    assert done.output =~ "hello"
    assert done.finished_at

    bad = schedule!(ws, %{cron: "@daily", body: "echo nope >&2; exit 3"})
    {:ok, run} = Schedules.run_now(bad)
    assert %{status: "failed", exit: 3, output: "nope\n"} = Schedules.perform(run.id)
  end

  test "a script that names the commit it checked records it on its run", %{ws: ws} do
    sha = String.duplicate("a1", 20)
    named = schedule!(ws, %{cron: "@daily", body: "echo ran-on: gate #{sha}; echo after"})
    {:ok, run} = Schedules.run_now(named)
    assert %{status: "ok", check_name: "gate", sha: ^sha} = Schedules.perform(run.id)

    plain = schedule!(ws, %{cron: "@daily", body: "echo hello"})
    {:ok, run} = Schedules.run_now(plain)
    assert %{check_name: nil, sha: nil} = Schedules.perform(run.id)
  end

  test "a script that reads its stdin ends instead of waiting on it", %{ws: ws} do
    s = schedule!(ws, %{cron: "@daily", body: "cat; echo done"})
    {:ok, run} = Schedules.run_now(s)
    assert %{status: "ok", output: "done\n"} = Schedules.perform(run.id)
  end

  test "a script past its timeout is killed with everything it started, and reported as exit 124", %{ws: ws} do
    Application.put_env(:server, :schedule_script_timeout_ms, 300)
    on_exit(fn -> Application.delete_env(:server, :schedule_script_timeout_ms) end)
    marker = "#{System.unique_integer([:positive])}.5"
    s = schedule!(ws, %{cron: "@daily", body: "echo started; sleep #{marker} & sleep #{marker}"})
    {:ok, run} = Schedules.run_now(s)

    assert %{status: "failed", exit: 124, output: out} = Schedules.perform(run.id)
    assert out =~ "started"
    Process.sleep(100)
    assert {_, 1} = System.cmd("pgrep", ["-f", "sleep #{marker}"])
  end

  test "a standing script posts each run's output to its one thread, without waking a lead", %{ws: ws} do
    s = schedule!(ws, %{cron: "@daily", body: "echo tick", standing: true})
    {:ok, r1} = Schedules.run_now(s)
    %{thread_id: tid} = Schedules.perform(r1.id)
    {:ok, r2} = Schedules.run_now(Schedules.get(s.id))
    assert %{thread_id: ^tid} = Schedules.perform(r2.id)

    notes = Channel.thread_messages(Channel.thread(tid))
    assert length(notes) == 2
    assert Enum.all?(notes, &(&1.author == "tlon" and &1.delivered_at != nil and &1.body =~ "tick"))
  end

  test "an agent run: a fresh thread each firing with the prompt from you; standing reuses one", %{ws: ws} do
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})
    fresh = schedule!(ws, %{kind: "agent", cron: "@daily", body: "summarise yesterday", agent: "hronir"})
    {:ok, a} = Schedules.run_now(fresh)
    {:ok, b} = Schedules.run_now(fresh)
    ra = Schedules.perform(a.id)
    rb = Schedules.perform(b.id)
    assert ra.status == "ok" and ra.thread_id != rb.thread_id

    assert [%{author: "andrew", body: "summarise yesterday"} | _] =
             Channel.thread_messages(Channel.thread(ra.thread_id))

    assert Channel.thread_lead(ra.thread_id) == "hronir"

    standing = schedule!(ws, %{kind: "agent", cron: "@daily", body: "standup", standing: true})
    {:ok, c} = Schedules.run_now(standing)
    tid = Schedules.perform(c.id).thread_id
    {:ok, _} = Channel.close_thread(Channel.thread(tid))
    {:ok, d} = Schedules.run_now(Schedules.get(standing.id))
    assert Schedules.perform(d.id).thread_id == tid
    assert Channel.thread(tid).state == "open"
  end

  test "a workline schedule opens a workline at intent; a run of a removed schedule fails", %{ws: ws} do
    s = schedule!(ws, %{kind: "workline", cron: "@weekly", title: "dependency bumps", body: "bump what is behind"})
    {:ok, run} = Schedules.run_now(s)
    %{status: "ok", thread_id: tid} = Schedules.perform(run.id)
    assert %{stage: "intent"} = Channel.thread(tid)

    {:ok, run} = Schedules.run_now(s)
    {:ok, _} = Schedules.remove(s)
    assert Repo.get(Server.ScheduleRun, run.id) == nil
  end

  test "next_occurrence/2 is the next local firing strictly after the given time" do
    after_at = DateTime.new!(~D[2026-01-01], ~T[00:00:00], "Etc/UTC")
    next = Schedules.next_occurrence("0 9 * * *", after_at)

    local =
      next
      |> DateTime.to_naive()
      |> NaiveDateTime.to_erl()
      |> :calendar.universal_time_to_local_time()
      |> NaiveDateTime.from_erl!()

    assert local.hour == 9
    assert DateTime.compare(next, after_at) == :gt
  end
end
