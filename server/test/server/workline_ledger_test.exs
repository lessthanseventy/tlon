defmodule Server.WorklineLedgerTest do
  # Worklines slice 6: the value ledger — a READ-MODEL over rows the stage machine already
  # writes (stage_advanced events + thread state). No new telemetry system; the metrics are
  # a side effect of coordination.
  use ExUnit.Case, async: false

  alias Server.Workline
  alias Server.Workline.Ledger
  alias Server.Workspaces

  defmodule AllPresent do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, _requirement), do: {:ok, "present"}
  end

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "the report carries every workline's stage, transitions, and the tallies" do
    {:ok, a} = Workline.open(%{title: "one", slug: "line-a"})
    {:ok, a} = Workline.advance(a, artifacts: AllPresent)
    {:awaiting, _a} = Workline.advance(a, artifacts: AllPresent)
    {:ok, _b} = Workline.open(%{title: "two", slug: "line-b"})

    report = Ledger.report()

    assert report.summary.open == 2
    assert report.summary.gated == 1
    assert report.summary.merged == 0

    line_a = Enum.find(report.worklines, &(&1.slug == "line-a"))
    assert line_a.stage == "spec"
    assert line_a.awaiting == "andrew"
    assert [%{from: "intent", to: "spec", at: %DateTime{}}] = line_a.transitions

    rendered = Ledger.render(report)
    assert rendered =~ "line-a"
    assert rendered =~ "spec"
    assert rendered =~ "gated"
  end

  test "an empty machine renders honestly" do
    report = Ledger.report()
    assert report.worklines == []
    assert Ledger.render(report) =~ "no worklines"
  end

  describe "status_for/1" do
    test "a workline with no verify checks yet has no blocking status" do
      {:ok, t} = Workline.open(%{title: "one", slug: "line-c"})

      status = Ledger.status_for(t)

      assert status.stage == "intent"
      assert status.awaiting == nil
      assert status.blocking == nil
    end

    test "the latest failing verify check is blocking, carrying its cmd and tail" do
      {:ok, t} = Workline.open(%{title: "one", slug: "line-d"})

      Server.Dossier.record_check(%{
        thread_id: t.id,
        cmd: "mix test",
        exit: 1,
        tail: "1 failure",
        correlation: "workline:line-d:verify"
      })

      status = Ledger.status_for(t)

      assert status.blocking == %{cmd: "mix test", tail: "1 failure"}
    end

    test "a passing check after a failing one clears the blocking status" do
      {:ok, t} = Workline.open(%{title: "one", slug: "line-e"})

      Server.Dossier.record_check(%{
        thread_id: t.id,
        cmd: "mix test",
        exit: 1,
        tail: "1 failure",
        correlation: "workline:line-e:verify"
      })

      Server.Dossier.record_check(%{
        thread_id: t.id,
        cmd: "mix test",
        exit: 0,
        tail: "ok",
        correlation: "workline:line-e:verify"
      })

      status = Ledger.status_for(t)

      assert status.blocking == nil
    end
  end

  describe "statuses/0" do
    test "every open workline's status, in id order" do
      {:ok, _a} = Workline.open(%{title: "one", slug: "line-f"})
      {:ok, b} = Workline.open(%{title: "two", slug: "line-g"})

      Server.Dossier.record_check(%{
        thread_id: b.id,
        cmd: "mix test",
        exit: 1,
        tail: "boom",
        correlation: "workline:line-g:verify"
      })

      [a, b] = Ledger.statuses()

      assert a.slug == "line-f"
      assert a.blocking == nil
      assert b.slug == "line-g"
      assert b.blocking == %{cmd: "mix test", tail: "boom"}
    end

    test "statuses/1 scopes to a workspace; nil is global" do
      {:ok, wsa} = Workspaces.register(%{name: "wsa", type: "code", scope: "machine", paths: [], roster: []})
      {:ok, wsb} = Workspaces.register(%{name: "wsb", type: "code", scope: "machine", paths: [], roster: []})
      {:ok, _a} = Workline.open(%{title: "one", slug: "line-h", workspace_id: wsa.id})
      {:ok, _b} = Workline.open(%{title: "two", slug: "line-i", workspace_id: wsb.id})

      assert [%{slug: "line-h"}] = Ledger.statuses(wsa.id)
      assert [%{slug: "line-i"}] = Ledger.statuses(wsb.id)
      assert length(Ledger.statuses()) == 2
    end
  end
end
