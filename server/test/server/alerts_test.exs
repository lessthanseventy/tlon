defmodule Server.AlertsTest do
  # What the desktop raises, and how loudly: a choice blocking work is a decision, what should
  # stay until seen is sticky, a meeting about to start is an alarm. Each carries its actions as
  # calls on the operator API, so the surface needs no per-kind logic.
  use ExUnit.Case, async: true

  alias Server.Alerts

  @now ~U[2026-10-08 15:57:00Z]

  defp need(kind, extra \\ %{}) do
    Map.merge(
      %{
        key: "#{kind}:7",
        kind: kind,
        level: "blocking",
        thread_id: 7,
        workspace_id: 1,
        title: "the finder",
        text: "waits",
        at: @now,
        options: nil,
        ref: nil
      },
      extra
    )
  end

  defp meeting(start, extra \\ %{}) do
    Map.merge(
      %{
        uid: "m@x",
        title: "Standup",
        start: start,
        stop: DateTime.add(start, 1800),
        link: "https://meet.google.com/abc",
        calendar: "work"
      },
      extra
    )
  end

  test "a gate is a decision: approve, or say something else" do
    [a] = Alerts.build([need("gate")], [], @now)
    assert a.level == "decision" and a.key == "gate:7"

    assert [
             %{label: "Read it", read: "/api/threads/7/docs/current"},
             %{label: "Approve", method: "POST", path: "/api/threads/7/approve"},
             %{label: "Other…", path: "/api/threads/7/messages", input: "body"}
           ] = a.actions
  end

  test "a review gate can also be sent back, to build or to plan, saying why" do
    [a] = Alerts.build([need("gate", %{stage: "review"})], [], @now)

    assert [
             %{label: "Read it"},
             %{label: "Approve"},
             %{label: "Back to build…", path: "/api/threads/7/send_back", body: %{stage: "build"}, input: "why"},
             %{label: "Back to plan…", path: "/api/threads/7/send_back", body: %{stage: "plan"}, input: "why"},
             %{label: "Other…"}
           ] = a.actions
  end

  test "a dialog is a decision with its own options; a question takes a reply" do
    [d, q] =
      Alerts.build(
        [
          need("dialog", %{options: [%{"key" => "y", "label" => "Yes"}, %{"key" => "n", "label" => "No"}]}),
          need("question", %{key: "question:8", thread_id: 8})
        ],
        [],
        @now
      )

    assert d.level == "decision"
    assert [%{label: "Yes", body: %{body: "y"}}, %{label: "No", body: %{body: "n"}}, %{label: "Other…"}] = d.actions
    assert q.level == "decision"
    assert [%{label: "Reply…", input: "body", path: "/api/threads/8/messages"}] = q.actions
  end

  test "a coworker's ask is a decision, each of its answers a click that answers it by its id" do
    ask =
      need("ask", %{
        key: "ask:41",
        ref: 41,
        text: "emma: ship it?",
        options: [%{"key" => "1", "label" => "Ship"}, %{"key" => "2", "label" => "Hold"}]
      })

    [a] = Alerts.build([ask], [], @now)
    assert a.level == "decision" and a.key == "ask:41"

    assert [
             %{label: "Ship", method: "POST", path: "/api/office/asks/41", body: %{key: "1"}},
             %{label: "Hold", method: "POST", path: "/api/office/asks/41", body: %{key: "2"}}
           ] = a.actions
  end

  test "what to decide when convenient is sticky, never an interruption" do
    alerts =
      Alerts.build(
        [need("mention", %{level: "decide"}), need("verify_failed", %{key: "verify_failed:9", thread_id: 9})],
        [],
        @now
      )

    assert Enum.map(alerts, & &1.level) == ["sticky", "sticky"]
    assert Enum.any?(List.last(alerts).actions, &(&1.path == "/api/threads/9/verify"))
  end

  test "rollout notes stay in the inbox — no card on the desktop" do
    alerts =
      Alerts.build(
        [
          need("rollout", %{level: "decide"}),
          need("mention", %{level: "decide"})
        ],
        [],
        @now
      )

    assert Enum.map(alerts, & &1.kind) == ["mention"]
  end

  test "a meeting is an alarm from a few minutes before it starts until shortly after, with a way to join" do
    soon = meeting(~U[2026-10-08 16:00:00Z])
    later = meeting(~U[2026-10-08 17:00:00Z], %{uid: "later@x"})
    gone = meeting(~U[2026-10-08 15:30:00Z], %{uid: "gone@x"})

    assert [a] = Alerts.build([], [soon, later, gone], @now, alarm_minutes: 5)
    assert a.level == "alarm" and a.key == "meeting:m@x:2026-10-08T16:00:00Z"
    assert a.at == ~U[2026-10-08 16:00:00Z] and a.link == "https://meet.google.com/abc"
    assert [%{label: "Join", open: "https://meet.google.com/abc"}] = a.actions
  end

  test "a parked thread getting its seat is info: one toast per seating, nothing to do, last in the list" do
    seated = %{id: 90, thread_id: 7, body: "emma sat down on #7 — the finder", created_at: @now}

    assert [%{level: "sticky"}, info] = Alerts.build([need("mention", %{level: "decide"})], [], @now, seated: [seated])

    assert %{key: "seated:90", level: "info", kind: "seated", title: "emma sat down on #7 — the finder"} = info
    assert info.thread_id == 7 and info.at == @now and info.actions == []
  end

  test "a workline landing is info: one toast per landing, naming the thread, nothing to do" do
    landed = %{id: 51, thread_id: 185, title: "Mailbox: letters reach the street", created_at: @now}

    assert [info] = Alerts.build([], [], @now, landed: [landed])

    assert %{key: "landed:51", level: "info", kind: "landed", title: "#185 landed — Mailbox: letters reach the street"} =
             info

    assert info.thread_id == 185 and info.at == @now and info.actions == []
  end

  test "a release going live is info: one toast per boot onto a new release" do
    live = %{id: 92, thread_id: 1, body: "release 7b54006 is live — 3 changes", created_at: @now}

    assert [info] = Alerts.build([], [], @now, live: [live])
    assert %{key: "live:92", level: "info", kind: "live", title: "release 7b54006 is live — 3 changes"} = info
    assert info.actions == []
  end

  test "alarms first, then decisions, then sticky" do
    alerts =
      Alerts.build([need("mention", %{level: "decide"}), need("gate")], [meeting(~U[2026-10-08 16:00:00Z])], @now)

    assert Enum.map(alerts, & &1.level) == ["alarm", "decision", "sticky"]
  end
end
