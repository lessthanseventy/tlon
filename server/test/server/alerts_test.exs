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

  test "a prompt gate is a decision, each option answering that prompt by its id; a question takes a reply" do
    [d, q] =
      Alerts.build(
        [
          need("gate", %{ref: 42, options: [%{"key" => "y", "label" => "Yes"}, %{"key" => "n", "label" => "No"}]}),
          need("question", %{key: "question:8", thread_id: 8})
        ],
        [],
        @now
      )

    assert d.level == "decision"

    assert [
             %{label: "Yes", method: "POST", path: "/api/office/prompts/42", body: %{key: "y"}},
             %{label: "No", method: "POST", path: "/api/office/prompts/42", body: %{key: "n"}},
             %{label: "Other…"}
           ] = d.actions

    assert q.level == "decision"
    assert [%{label: "Reply…", input: "body", path: "/api/threads/8/messages"}] = q.actions
  end

  test "a coworker's ask is a decision, each of its answers a click that answers it by its id, then Uqbar; never Put away" do
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
             %{label: "Hold", method: "POST", path: "/api/office/asks/41", body: %{key: "2"}},
             %{label: "Hand it to Uqbar", method: "POST", path: "/api/office/prompts/41/uqbar", body: %{}}
           ] = a.actions
  end

  test "uqbar's own ask offers its answers, never handing it to Uqbar" do
    ask = need("ask", %{key: "ask:42", ref: 42, ask: "uqbar", options: [%{"key" => "1", "label" => "Ran it"}]})
    [a] = Alerts.build([ask], [], @now)
    refute Enum.any?(a.actions, &(&1.label == "Hand it to Uqbar"))
    assert Enum.any?(a.actions, &(&1.label == "Ran it"))
  end

  test "what nothing waits on is put away on the server; an issue resolves, a stranded checkout comes down" do
    [issue, stranded, mention] =
      Alerts.build(
        [
          need("mention", %{level: "decide", key: "mention:3"}),
          need("issue", %{level: "decide", key: "issue:5", ref: 5}),
          need("stranded", %{level: "decide", key: "stranded:/r:w"})
        ],
        [],
        @now
      )

    assert %{path: "/api/office/needs/dismiss", body: %{key: "mention:3"}} = List.last(mention.actions)

    assert [
             %{label: "Get it fixed", path: "/api/issues/5/fix"},
             %{label: "Resolve…", path: "/api/issues/5/resolve", input: "resolution"},
             %{label: "Dismiss"}
           ] = issue.actions

    assert [%{path: "/api/office/needs/retire", body: %{key: "stranded:/r:w"}}, %{label: "Dismiss"}] = stranded.actions
  end

  test "a landing GitHub never got republishes, or takes the url of the PR opened by hand" do
    [a] = Alerts.build([need("publish_failed", %{key: "publish_failed:7", ref: 7})], [], @now)
    assert a.level == "sticky"

    assert [
             %{label: "Republish", method: "POST", path: "/api/threads/7/republish"},
             %{label: "Opened by hand…", path: "/api/threads/7/published", input: "url"}
           ] = a.actions
  end

  test "a failed release cut is retried by its event, or put away to stay on what runs" do
    [a] = Alerts.build([need("release_failed", %{level: "decide", key: "release_failed:7", ref: 41})], [], @now)
    assert a.level == "sticky"

    assert [
             %{label: "Retry the cut", method: "POST", path: "/api/release/retry/41"},
             %{label: "Dismiss", body: %{key: "release_failed:7"}}
           ] = a.actions
  end

  test "what to decide when convenient is sticky, never an interruption" do
    alerts = Alerts.build([need("verify_failed", %{key: "verify_failed:9", thread_id: 9})], [], @now)

    assert Enum.map(alerts, & &1.level) == ["sticky"]
    assert Enum.any?(List.last(alerts).actions, &(&1.path == "/api/threads/9/verify"))
  end

  test "a mention is info: it goes by on its own, and the inbox keeps it" do
    alerts =
      Alerts.build([need("mention", %{level: "decide"}), need("verify_failed", %{key: "verify_failed:9"})], [], @now)

    assert Enum.map(alerts, &{&1.kind, &1.level}) == [{"verify_failed", "sticky"}, {"mention", "info"}]
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

  test "the home's notices are info toasts; reminders and asks are sticky" do
    pile = %{id: "3:1763560800", created_at: @now, thread_id: nil, body: "Retro in 15 — 2 things: a; b"}

    assert [
             %{
               key: "home_agenda:3:1763560800",
               level: "info",
               kind: "home_agenda",
               title: "Retro in 15 — 2 things: a; b",
               actions: []
             }
           ] =
             Alerts.build([], [], @now, home_agenda: [pile])

    told = %Server.Jot{id: 7, text: "bins", nudges: 2, nudged_at: @now}
    list = %{id: "2026-11-17", created_at: @now, thread_id: nil, body: "Still open: milk"}

    assert [
             %{key: "reminder:7:2", level: "sticky", kind: "reminder", title: "bins", actions: [done, hour, _, delete]},
             %{key: "home_list:2026-11-17", level: "info", title: "Still open: milk"}
           ] = Alerts.build([], [], @now, told: [told], home_list: [list])

    assert done == %{label: "Done", method: "POST", path: "/api/home/7/done", body: nil}
    assert hour.body == %{until: "hour"}
    assert delete == %{label: "Delete", method: "POST", path: "/api/home/7/drop", body: nil}

    asked = %{
      id: 9,
      key: "ask:9:review:1",
      at: @now,
      text: "Still want this? milk",
      choices: [{"Keep", "keep"}],
      typed: nil
    }

    assert [%{key: "reminder:7:2"}, %{key: "ask:9:review:1", level: "sticky", kind: "home_ask", actions: [keep]}] =
             Alerts.build([], [], @now, told: [told], asked: [asked])

    assert keep == %{label: "Keep", method: "POST", path: "/api/home/9/answer", body: %{choice: "keep"}}
  end

  test "alarms first, then decisions, then sticky" do
    alerts =
      Alerts.build(
        [need("verify_failed", %{key: "verify_failed:9"}), need("gate")],
        [meeting(~U[2026-10-08 16:00:00Z])],
        @now
      )

    assert Enum.map(alerts, & &1.level) == ["alarm", "decision", "sticky"]
  end
end
