defmodule Server.Office.NeedsTest do
  # Everything waiting on the operator, as one list built from the state that already says so —
  # blocking first, then what to decide when convenient.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Office.Needs

  setup do
    Server.TestDB.clean!()
    # Rollout's notes are global process state (a drifted main files one); the list must start without them
    for n <- Server.Rollout.pending(), do: Server.Rollout.dismiss(n.id)
    {:ok, ws} = Server.Workspaces.register(%{name: "Needy"})
    %{ws: ws}
  end

  defp kinds(ws), do: Needs.list() |> Enum.filter(&(&1.workspace_id in [ws.id, nil])) |> Enum.map(&{&1.kind, &1.level})

  test "a coworker's question is blocking, and answering it takes it off the list", %{ws: ws} do
    {:ok, t} = Channel.open_thread(%{title: "q", workspace_id: ws.id})
    {:ok, _} = Server.Attention.ask(t.id, "daneri", "A or B?")
    assert [%{kind: "question", level: "blocking", thread_id: tid, text: "A or B?"}] = Needs.list()
    assert tid == t.id
    {:ok, _} = Server.Attention.respond(t.id, "andrew", "A")
    assert Needs.list() == []
  end

  test "a pane dialog or the release gate is a dialog, carrying its prompt's id to answer by", %{ws: ws} do
    {:ok, t} = Channel.open_thread(%{title: "root", workspace_id: ws.id})

    gate =
      Server.Repo.insert!(%Server.Message{
        thread_id: t.id,
        author: "tlon",
        kind: "prompt",
        body: "⚑ release abc1234",
        payload: %{
          "release" => "abc1234",
          "summary" => "release abc1234",
          "options" => [%{"key" => "a", "label" => "approve"}]
        },
        created_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    assert [%{kind: "dialog", ref: ref}] = Needs.list()
    assert ref == gate.id
  end

  test "a workline at its gate is a gate; one red at verify is a failed verify", %{ws: ws} do
    # a machine-born intent parks at its gate before any artifact, by design
    {:ok, _} =
      Server.Workline.flag(
        %{title: "g", slug: "gate-#{System.unique_integer([:positive])}", workspace_id: ws.id},
        "a breach"
      )

    {:ok, red} =
      Server.Workline.open(%{
        title: "r",
        slug: "red-#{System.unique_integer([:positive])}",
        stage: "verify",
        workspace_id: ws.id
      })

    {:ok, _} =
      Server.Dossier.record_check(%{
        thread_id: red.id,
        cmd: "mise run check",
        exit: 1,
        tail: "boom",
        correlation: "workline:#{red.slug}:verify"
      })

    assert Enum.sort(kinds(ws)) == Enum.sort([{"gate", "blocking"}, {"verify_failed", "blocking"}])
  end

  test "an @mention of the operator nobody has answered is to decide; a reply after it settles it", %{ws: ws} do
    {:ok, t} = Channel.open_thread(%{title: "m", workspace_id: ws.id})

    {:ok, _} =
      Channel.post(%{thread_id: t.id, author: "tertius", body: "@andrew I'll raise the EPIPE as its own ticket?"})

    assert [{"mention", "decide"}] = kinds(ws)
    {:ok, _} = Channel.post(%{thread_id: t.id, author: "andrew", body: "yes please"})
    assert kinds(ws) == []
  end

  test "an @mention older than 12 hours has left the list — it stays on its thread", %{ws: ws} do
    {:ok, t} = Channel.open_thread(%{title: "old", workspace_id: ws.id})
    {:ok, m} = Channel.post(%{thread_id: t.id, author: "sonny", body: "Good morning @andrew! a pumpkin"})
    at = DateTime.add(DateTime.utc_now(), -13 * 3600, :second)
    Server.Repo.update_all(from(x in Server.Message, where: x.id == ^m.id), set: [created_at: at])

    assert kinds(ws) == []
  end

  test "a workline that advances past a mention settles it — the question was about a stage now done",
       %{ws: ws} do
    {:ok, t} =
      Server.Workline.open(%{
        title: "w",
        slug: "mention-#{System.unique_integer([:positive])}",
        stage: "spec",
        workspace_id: ws.id
      })

    {:ok, _} = Channel.post(%{thread_id: t.id, author: "yu", body: "@andrew spec is in — good to advance?"})
    assert {"mention", "decide"} in kinds(ws)

    {:ok, _} =
      Server.Dossier.record_event(%{
        thread_id: t.id,
        kind: "stage_advanced",
        correlation: "workline:#{t.slug}",
        detail: %{"from" => "spec", "to" => "plan"}
      })

    refute {"mention", "decide"} in kinds(ws)
  end

  test "blocking comes before deciding, oldest first within each", %{ws: ws} do
    {:ok, a} = Channel.open_thread(%{title: "a", workspace_id: ws.id})
    {:ok, b} = Channel.open_thread(%{title: "b", workspace_id: ws.id})
    {:ok, _} = Channel.post(%{thread_id: a.id, author: "yu", body: "@andrew fyi"})
    {:ok, _} = Server.Attention.ask(b.id, "yu", "blocked on you")
    assert [%{level: "blocking"}, %{level: "decide"}] = Needs.list()
  end

  test "a coworker's suggestion is an idea, not a request: it stays in the suggestion box, out of the list",
       %{ws: ws} do
    {:ok, _} = Channel.open_thread(%{title: "standing", scope: "machine", workspace_id: ws.id})
    {:ok, work} = Channel.open_thread(%{title: "work", workspace_id: ws.id})

    {:ok, _} = Server.Office.Corkboard.suggest(ws.id, "lonnrot", "a north wall for the lobby", work.id)
    assert [%{author: "lonnrot"}] = Server.Office.Corkboard.suggestions(ws.id)
    assert kinds(ws) == []
  end

  test "a margin note that names the operator is not a mention", %{ws: ws} do
    {:ok, t} = Channel.open_thread(%{title: "work", workspace_id: ws.id})
    {:ok, _} = Channel.post(%{thread_id: t.id, author: "uqbar", body: "@andrew #1 back to build", kind: "margin"})
    assert kinds(ws) == []
  end

  describe "putting an item away" do
    test "a mention put away stays away until a newer one comes", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "m", workspace_id: ws.id})
      {:ok, _} = Channel.post(%{thread_id: t.id, author: "sonny", body: "@andrew a pumpkin"})
      [%{key: key}] = Needs.list()

      assert :ok = Needs.dismiss(key)
      assert Needs.list() == []

      Process.sleep(1100)
      {:ok, _} = Channel.post(%{thread_id: t.id, author: "sonny", body: "@andrew a real question"})
      assert [%{kind: "mention", text: "sonny: @andrew a real question"}] = Needs.list()
    end

    test "an ask names its asker, so the office can keep uqbar's own from uqbar", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "lobby", workspace_id: ws.id})
      {:ok, _} = Server.Attention.ask(t.id, "uqbar", "run it?", ["run", "hold"])
      assert [%{kind: "ask", ask: "uqbar"}] = Needs.list()
    end

    test "an ask put away is withdrawn, and its asker is told", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "lobby", workspace_id: ws.id})
      {:ok, a} = Server.Attention.ask(t.id, "tertius", "hold new work?", ["hold", "carry on"])

      assert :ok = Needs.dismiss("ask:#{a.id}")
      assert Needs.list() == []
      assert %{resolved_at: %DateTime{}} = Server.Repo.get!(Server.Message, a.id)
      assert List.last(Channel.thread_messages(t)).body =~ "@tertius andrew put your ask away"
    end

    test "a put-away whose item is gone is forgotten, so a later one under its key shows", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "m", workspace_id: ws.id})
      {:ok, _} = Channel.post(%{thread_id: t.id, author: "sonny", body: "@andrew a pumpkin"})
      [%{key: key}] = Needs.list()
      :ok = Needs.dismiss(key)
      {:ok, _} = Channel.post(%{thread_id: t.id, author: "andrew", body: "nice"})

      assert Needs.list() == []
      assert Server.Repo.aggregate("need_dismissal", :count) == 0
    end

    test "a key the list does not hold is refused, not remembered" do
      assert {:error, :not_found} = Needs.dismiss("stranded:/nowhere:t9")
      assert {:error, :not_found} = Needs.dismiss("ask:abc")
      assert Server.Repo.aggregate("need_dismissal", :count) == 0
    end

    test "work waits on a question: it is never put away", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "q", workspace_id: ws.id})
      {:ok, _} = Server.Attention.ask(t.id, "daneri", "A or B?")
      [%{key: key}] = Needs.list()
      assert {:error, :blocking} = Needs.dismiss(key)
      assert [_] = Needs.list()
    end

    test "an open issue on an open thread is to decide; resolved, it goes", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "i", workspace_id: ws.id})
      {:ok, issue} = Server.Dossier.raise_issue(%{thread_id: t.id, summary: "the fixture is flaky", found_by: "cruz"})
      assert [%{kind: "issue", level: "decide", ref: ref, text: "cruz: the fixture is flaky"}] = Needs.list()
      assert ref == issue.id
      {:ok, _} = Server.Dossier.resolve_issue(issue, "fixed in #12")
      assert Needs.list() == []
    end
  end

  describe "asks, seats and failed jobs — each with its answers" do
    test "every ask is its own blocking item, answered by its own id", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "lobby", workspace_id: ws.id})
      {:ok, a} = Server.Attention.ask(t.id, "tertius", "weather: start now?", ["go", "hold"])
      {:ok, b} = Server.Attention.ask(t.id, "tertius", "north wall?", ["go", "drop it"])

      assert [
               %{
                 kind: "ask",
                 level: "blocking",
                 ref: ra,
                 text: "tertius: weather: start now?",
                 options: [%{"key" => "1", "label" => "go"}, _]
               },
               %{kind: "ask", ref: rb}
             ] = Needs.list()

      assert {ra, rb} == {a.id, b.id}
      {:ok, _} = Server.Attention.answer_prompt(a.id, "andrew", "1")
      assert [%{kind: "ask", ref: ^rb}] = Needs.list()
    end

    test "threads parked on the leaf cap are one seats item that offers a bigger cap" do
      {:ok, ws} =
        Server.Workspaces.register(%{
          name: "Seats",
          roster: [%{archetype: "builder", name: "hronir"}, %{archetype: "planner", name: "borges"}]
        })

      for who <- ["hronir", "borges"] do
        {:ok, t} = Channel.open_thread(%{title: "for #{who}", scope: "machine", workspace_id: ws.id})
        {:ok, _} = Channel.assign_lead(t.id, who)
        :ok = Server.Staffing.note_parked(t.id)
      end

      cap = Server.OperatorConfig.max_leaves()

      assert [%{kind: "seats", level: "decide", workspace_id: wid, ref: target, text: text, options: [%{"key" => "1"}]}] =
               Needs.list()

      assert wid == ws.id
      assert target == min(cap + 2, 12)
      assert text =~ "2 threads wait for a seat"
    end

    test "a job discarded today is to decide until it is dismissed" do
      {:ok, job} = %{} |> Oban.Job.new(worker: "Server.Jobs.KeepUp", queue: "default") |> Server.Repo.insert()

      job
      |> Ecto.Changeset.change(
        state: "discarded",
        attempted_at: DateTime.utc_now(),
        errors: [%{"error" => "** (RuntimeError) boom"}]
      )
      |> Server.Repo.update!()

      assert [
               %{
                 kind: "job_failed",
                 level: "decide",
                 ref: ref,
                 title: "Server.Jobs.KeepUp failed",
                 text: "** (RuntimeError) boom"
               }
             ] =
               Needs.list()

      assert ref == job.id
      assert Server.Office.Room.health().failed_jobs == 1
      :ok = Needs.dismiss_job(job.id)
      assert Needs.list() == []
      assert Server.Office.Room.health().failed_jobs == 0
    end

    test "a job failing the same way run after run is one item, dismissed as one" do
      failed = fn worker, error, ago ->
        {:ok, job} = %{} |> Oban.Job.new(worker: worker, queue: "default") |> Server.Repo.insert()

        job
        |> Ecto.Changeset.change(
          state: "discarded",
          attempted_at: DateTime.add(DateTime.utc_now(), -ago),
          errors: [%{"error" => error}]
        )
        |> Server.Repo.update!()
      end

      for ago <- [600, 300], do: failed.("Server.Jobs.KeepUp", "keep_up /r: gh not found", ago)
      newest = failed.("Server.Jobs.KeepUp", "keep_up /r: gh not found", 0)
      other = failed.("Server.Jobs.KeepUp", "keep_up /r: git won't run", 0)

      items = Needs.list()
      assert [repeated] = Enum.filter(items, &(&1.text == "keep_up /r: gh not found"))
      assert repeated.ref == newest.id
      assert repeated.title == "Server.Jobs.KeepUp failed 3 times"
      assert [%{ref: other_ref}] = Enum.filter(items, &(&1.text == "keep_up /r: git won't run"))
      assert other_ref == other.id

      :ok = Needs.dismiss_job(newest.id)
      assert [%{ref: ^other_ref}] = Needs.list()
    end
  end

  describe "quota and no seat — each a Need with its answers" do
    defmodule Spent do
      @moduledoc false
      def clocked_out?(_agent), do: true
      def spent, do: [%{provider: "ollama-cloud", until: ~U[2030-01-01 09:00:00Z]}]
    end

    test "a spent plan is a quota Need in each workspace seating a coworker on it, with the other crews" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Ollama crew"})
      {:ok, seat} = Server.Workspaces.seat(ws.id, %{name: "glmer", archetype: "builder", crew: "day"})
      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "claudia", archetype: "builder", crew: "night"})
      glm = %{"provider" => "ollama-cloud", "model" => "glm-5.2", "thinking" => "medium"}
      {:ok, _} = Server.Workspaces.set_policy(ws.id, seat.agent_id, %{model: glm})
      Application.put_env(:server, :engine_presence, Spent)
      on_exit(fn -> Application.delete_env(:server, :engine_presence) end)

      assert [need] = Enum.filter(Needs.list(), &(&1.kind == "quota"))
      assert need.workspace_id == ws.id and need.level == "blocking"
      assert need.text =~ "ollama-cloud"
      assert need.options == [%{"key" => "night", "label" => "night crew on"}]

      assert [%{actions: [%{label: "night crew on", path: "/api/office/shift", body: body} | _]}] =
               Server.Alerts.build([need], [], DateTime.utc_now())

      assert body == %{workspace_id: ws.id, shift: "night"}
    end

    test "a workline at a stage whose kind the bench lacks, and nobody leads, is no_seat: hire one or hand it on",
         %{ws: ws} do
      {:ok, t} =
        Server.Workline.open(%{
          title: "p",
          slug: "noseat-#{System.unique_integer([:positive])}",
          stage: "plan",
          workspace_id: ws.id
        })

      assert [need] = Enum.filter(Needs.list(), &(&1.kind == "no_seat"))
      assert need.thread_id == t.id and need.level == "blocking" and need.archetype == "planner"

      assert [%{actions: [hire, hand | _]}] = Server.Alerts.build([need], [], DateTime.utc_now())
      assert %{label: "Hire a planner…", body: %{archetype: "planner"}, input: "name"} = hire
      assert hire.path == "/api/workspaces/#{ws.id}/coworkers"
      assert %{label: "Reassign…", input: "agent"} = hand
      assert hand.path == "/api/threads/#{t.id}/hand-off"

      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "planck", archetype: "planner"})
      refute Enum.any?(Needs.list(), &(&1.kind == "no_seat"))
    end

    test "a workline nobody can lead, quiet past the window, is no_seat, not stalled", %{ws: ws} do
      {:ok, t} =
        Server.Workline.open(%{
          title: "p",
          slug: "noseat-quiet-#{System.unique_integer([:positive])}",
          stage: "plan",
          workspace_id: ws.id
        })

      age(t, 5)

      assert [%{kind: "no_seat"}] = Enum.filter(Needs.list(), &(&1.thread_id == t.id))
    end
  end

  describe "a stop with no kind of its own is a stalled Need until the workline moves" do
    # a seat of every stage's kind, so no workline here is short of one (`no_seat`)
    setup %{ws: ws} do
      for {name, kind} <- [{"planck", "planner"}, {"bauer", "builder"}, {"revel", "reviewer"}],
          do: {:ok, _} = Server.Workspaces.seat(ws.id, %{name: name, archetype: kind})

      :ok
    end

    defp workline(ws, stage, hours_ago) do
      {:ok, t} =
        Server.Workline.open(%{
          title: "w-#{stage}",
          slug: "stall-#{System.unique_integer([:positive])}",
          stage: stage,
          workspace_id: ws.id
        })

      age(t, hours_ago)
    end

    defp age(t, hours_ago) do
      at = DateTime.utc_now() |> DateTime.add(-hours_ago * 3600, :second) |> DateTime.truncate(:second)
      Server.Repo.update_all(from(x in Server.Thread, where: x.id == ^t.id), set: [created_at: at])
      Server.Repo.update_all(from(e in Server.Event, where: e.thread_id == ^t.id), set: [created_at: at])
      Server.Repo.update_all(from(m in Server.Message, where: m.thread_id == ^t.id), set: [created_at: at])
      Server.Repo.get!(Server.Thread, t.id)
    end

    test "a workline nothing has moved for past the quiet window is blocking, with its last word", %{ws: ws} do
      t = workline(ws, "review", 4)
      {:ok, _} = Channel.post(%{thread_id: t.id, author: "treviranus", body: "QA is blocked: release:smoke was denied"})
      age(t, 4)

      assert [%{kind: "stalled", level: "blocking", thread_id: tid, text: text}] = Needs.list()
      assert tid == t.id
      assert text =~ "nothing has moved"
      assert text =~ "treviranus: QA is blocked"
    end

    defp deny(t, n) do
      for _ <- 1..n do
        {:ok, _} =
          Server.Dossier.record_event(%{
            thread_id: t.id,
            kind: "tool_denied",
            correlation: "tool_denied:#{t.id}",
            detail: %{
              "agent" => "nolan",
              "tool" => "Bash",
              "summary" => "Bash · mise run release:smoke",
              "reason" => "Auto-Mode Bypass"
            }
          })
      end
    end

    test "a seat refused its tool twice, with nobody working, is tool_denied with its answers", %{ws: ws} do
      t = workline(ws, "review", 3)
      deny(t, 2)

      assert [%{kind: "tool_denied", level: "blocking", thread_id: tid, text: text, rule: rule}] = Needs.list()
      assert tid == t.id
      assert text =~ "nolan" and text =~ "refused Bash 2 times" and text =~ "release:smoke"
      assert text =~ "Auto-Mode Bypass"
      assert rule == "Bash(mise run release:smoke)"

      actions = for a <- Server.Alerts.list(), a.thread_id == t.id, x <- a.actions, do: x
      labels = Enum.map(actions, & &1.label)
      assert Enum.any?(labels, &(&1 =~ "by hand")) and "Hand it to Uqbar" in labels
      assert Enum.any?(labels, &(&1 =~ "Back to build"))

      # the operator adds the rule to their own Claude Code settings (the server never writes them):
      # the verb says which rule, and posting it is the movement that clears the item
      allowed = Enum.find(actions, &(&1.label =~ "Allowed it"))
      assert allowed.path == "/api/threads/#{t.id}/messages"
      assert allowed.body.body =~ "Bash(mise run release:smoke)"
    end

    test "a refusal of another tool, or with no reason, is said as it came", %{ws: ws} do
      t = workline(ws, "review", 3)

      for _ <- 1..2 do
        {:ok, _} =
          Server.Dossier.record_event(%{
            thread_id: t.id,
            kind: "tool_denied",
            correlation: "tool_denied:#{t.id}",
            detail: %{"agent" => "nolan", "tool" => "mcp__tlon__record_check", "summary" => "record_check"}
          })
      end

      assert [%{kind: "tool_denied", text: text, rule: nil}] = Needs.list()
      assert text == "nolan on #{t.slug} was refused mcp__tlon__record_check 2 times: record_check"

      labels = for a <- Server.Alerts.list(), a.thread_id == t.id, x <- a.actions, do: x.label
      refute Enum.any?(labels, &(&1 =~ "Allowed it"))
    end

    test "a plain thread, which has no slug, is named by its number", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "release smoke", workspace_id: ws.id})
      t = age(t, 1)
      deny(t, 2)

      assert [%{kind: "tool_denied", text: text}] = for(n <- Needs.list(), n.kind == "tool_denied", do: n)
      assert text =~ "nolan on ##{t.id} was refused Bash 2 times"
    end

    test "one refusal is a seat finding another way, not a Need", %{ws: ws} do
      t = workline(ws, "review", 3)
      deny(t, 1)
      refute Enum.any?(Needs.list(), &(&1.kind == "tool_denied"))
    end

    test "an answer clears it; a refusal after the answer is a new item", %{ws: ws} do
      t = workline(ws, "review", 3)
      deny(t, 2)
      {:ok, m} = Channel.post(%{thread_id: t.id, author: "andrew", body: "allowed"})
      assert [] = for(n <- Needs.list(), n.kind == "tool_denied", do: n)

      back = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      Server.Repo.update_all(from(e in Server.Event, where: e.thread_id == ^t.id), set: [created_at: back])
      Server.Repo.update_all(from(x in Server.Message, where: x.id == ^m.id), set: [created_at: back])
      deny(t, 2)
      assert [%{kind: "tool_denied"}] = for(n <- Needs.list(), n.kind == "tool_denied", do: n)
    end

    test "a fresh workline is not stalled", %{ws: ws} do
      _ = workline(ws, "build", 0)
      assert kinds(ws) == []
    end

    test "an answer gives the lead the quiet window, then the workline is a Need again", %{ws: ws} do
      t = workline(ws, "review", 4)
      {:ok, _} = Channel.post(%{thread_id: t.id, author: "andrew", body: "allow it"})
      assert kinds(ws) == []

      age(t, 2)
      assert [%{kind: "stalled", text: text}] = Needs.list()
      assert text =~ "andrew: allow it"
    end

    test "a landing, a queued verify or a coworker mid-turn is on duty, not stalled", %{ws: ws} do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      landing = workline(ws, "review", 4)
      {:ok, _} = %{thread_id: landing.id} |> Server.Jobs.Land.new() |> Oban.insert()
      verifying = workline(ws, "verify", 4)
      {:ok, _} = %{thread_id: verifying.id, slug: verifying.slug} |> Server.Jobs.Verify.new() |> Oban.insert()
      building = workline(ws, "build", 4)

      {:ok, a} =
        Server.Staff.register_agent(%{name: "emma-#{System.unique_integer([:positive])}", mandate: "m", engine: "e"})

      {:ok, _} = Server.Staff.start_session(%{agent_id: a.id, thread_id: building.id})
      :ok = Server.Staff.mark_thinking(building.id, a.name, DateTime.truncate(DateTime.utc_now(), :second))

      assert kinds(ws) == []
    end

    test "a prompt the machine closed is not an answer; a mid-turn mark gone stale is not on duty", %{ws: ws} do
      t = workline(ws, "build", 4)

      Server.Repo.insert!(%Server.Message{
        thread_id: t.id,
        author: "tlon",
        kind: "prompt",
        body: "a pane dialog",
        created_at: DateTime.truncate(DateTime.utc_now(), :second),
        resolved_at: DateTime.truncate(DateTime.utc_now(), :second),
        resolution: "window closed"
      })

      {:ok, a} =
        Server.Staff.register_agent(%{name: "yu-#{System.unique_integer([:positive])}", mandate: "m", engine: "e"})

      {:ok, _} = Server.Staff.start_session(%{agent_id: a.id, thread_id: t.id})

      old =
        DateTime.utc_now()
        |> DateTime.add(-(Server.Presence.Thinking.stale_turn_seconds() + 60), :second)
        |> DateTime.truncate(:second)

      :ok = Server.Staff.mark_thinking(t.id, a.name, old)

      assert [{"stalled", "blocking"}] = kinds(ws)
    end

    test "a mid-turn mark is on duty only while it is younger than the shared stale-turn setting", %{ws: ws} do
      on_exit(fn -> Application.delete_env(:server, :stale_turn_seconds) end)
      t = workline(ws, "build", 4)

      {:ok, a} =
        Server.Staff.register_agent(%{name: "ts-#{System.unique_integer([:positive])}", mandate: "m", engine: "e"})

      {:ok, _} = Server.Staff.start_session(%{agent_id: a.id, thread_id: t.id})
      marked = DateTime.utc_now() |> DateTime.add(-1_200, :second) |> DateTime.truncate(:second)
      :ok = Server.Staff.mark_thinking(t.id, a.name, marked)

      Application.put_env(:server, :stale_turn_seconds, 3600)
      assert kinds(ws) == []
      Application.put_env(:server, :stale_turn_seconds, 600)
      assert [{"stalled", "blocking"}] = kinds(ws)
    end

    test "a turn older than the stale-turn clock that reported activity within it is on duty", %{ws: ws} do
      on_exit(fn -> Application.delete_env(:server, :stale_turn_seconds) end)
      Application.put_env(:server, :stale_turn_seconds, 600)
      t = workline(ws, "build", 4)

      {:ok, a} =
        Server.Staff.register_agent(%{name: "lt-#{System.unique_integer([:positive])}", mandate: "m", engine: "e"})

      {:ok, _} = Server.Staff.start_session(%{agent_id: a.id, thread_id: t.id})
      on_exit(fn -> Server.Presence.Thinking.idle(t.id, a.name) end)
      Server.Presence.Thinking.thinking(t.id, a.name)
      long_ago = DateTime.utc_now() |> DateTime.add(-1_200, :second) |> DateTime.truncate(:second)
      :ok = Server.Staff.mark_thinking(t.id, a.name, long_ago)
      assert [{"stalled", "blocking"}] = kinds(ws)

      Server.Presence.Thinking.doing(t.id, a.name, "bash")
      assert kinds(ws) == []
    end

    test "the quiet window is the operator's quiet_workline_minutes knob", %{ws: ws} do
      _ = workline(ws, "build", 2)
      path = Path.join(Path.expand("tmp"), "needs-quiet-#{System.pid()}-#{System.unique_integer([:positive])}.json")
      prior = Application.get_env(:server, :operator_config_path)
      Application.put_env(:server, :operator_config_path, path)
      on_exit(fn -> Application.put_env(:server, :operator_config_path, prior) end)

      File.write!(path, ~s({"quiet_workline_minutes": 180}))
      assert kinds(ws) == []
      File.write!(path, ~s({"quiet_workline_minutes": 60}))
      assert [{"stalled", "blocking"}] = kinds(ws)
    end

    test "a commit on work/<slug> is movement, read for every workline in one git call", %{ws: ws} do
      repo = Path.join(System.tmp_dir!(), "needs-tips-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(repo)
      on_exit(fn -> File.rm_rf!(repo) end)
      git = fn args -> {_, 0} = System.cmd("git", ["-C", repo, "-c", "user.email=t@t", "-c", "user.name=t" | args]) end
      git.(["init", "-q"])
      git.(["commit", "-q", "--allow-empty", "-m", "seed"])
      prior = Application.get_env(:server, :workline_root)
      Application.put_env(:server, :workline_root, repo)
      test = self()

      Application.put_env(:server, :git_cmd, fn cmd, args, opts ->
        send(test, {:git, args})
        System.cmd(cmd, args, opts)
      end)

      on_exit(fn ->
        Application.put_env(:server, :workline_root, prior)
        Application.delete_env(:server, :git_cmd)
      end)

      moving = workline(ws, "build", 4)
      quiet = workline(ws, "build", 4)
      git.(["branch", "work/#{moving.slug}"])

      assert [%{kind: "stalled", thread_id: id}] = Needs.list()
      assert id == quiet.id
      assert [_] = for({:git, args} <- self() |> Process.info(:messages) |> elem(1), do: args)
    end

    test "under pencils down nothing is stalled: the operator stopped it", %{ws: ws} do
      _ = workline(ws, "build", 4)
      path = Path.join(Path.expand("tmp"), "needs-pause-#{System.pid()}-#{System.unique_integer([:positive])}.json")
      File.write!(path, ~s({"pause": "pencils_down"}))
      prior = Application.get_env(:server, :operator_config_path)
      Application.put_env(:server, :operator_config_path, path)
      on_exit(fn -> Application.put_env(:server, :operator_config_path, prior) end)
      assert kinds(ws) == []
    end

    test "put away, it stays away until the workline moves and stalls again", %{ws: ws} do
      t = workline(ws, "build", 4)
      assert [%{key: key}] = Needs.list()
      :ok = Needs.dismiss(key)
      assert Needs.list() == []

      {:ok, _} = Server.Dossier.record_check(%{thread_id: t.id, cmd: "mise run check", exit: 0, tail: "ok"})
      assert Needs.list() == []
      age(t, 4)
      assert [%{kind: "stalled"}] = Needs.list()
    end

    test "red at verify shows whether or not the workspace has a sheriff — the sheriff takes a copy", %{ws: ws} do
      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
      t = workline(ws, "verify", 0)

      {:ok, _} =
        Server.Dossier.record_check(%{
          thread_id: t.id,
          cmd: "mise run check",
          exit: 1,
          tail: "boom",
          correlation: "workline:#{t.slug}:verify"
        })

      assert [{"verify_failed", "blocking"}] = kinds(ws)
    end

    test "a red verify whose re-run is queued or running is on duty, not listed", %{ws: ws} do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      t = workline(ws, "verify", 0)

      {:ok, _} =
        Server.Dossier.record_check(%{
          thread_id: t.id,
          cmd: "mise run check",
          exit: 1,
          tail: "boom",
          correlation: "workline:#{t.slug}:verify"
        })

      {:ok, _} = %{thread_id: t.id, slug: t.slug} |> Server.Jobs.Verify.new() |> Oban.insert()
      assert kinds(ws) == []
    end

    # the invariant: any open thread holding work with no movement past the quiet window is a Need
    # (or someone is on duty for it) — the inbox can never read empty over a stopped workline
    test "every open workline left alone past the quiet window is on the list", %{ws: ws} do
      for stage <- ~w(intent spec plan build verify review), do: workline(ws, stage, 5)

      idle =
        Server.Repo.all(
          from t in Server.Thread, where: t.state == "open" and not is_nil(t.stage) and t.stage != "merged"
        )

      listed = MapSet.new(Needs.list(), & &1.thread_id)
      assert idle != []
      for t <- idle, do: assert(MapSet.member?(listed, t.id), "##{t.id} at #{t.stage} is idle and not a Need")
    end

    test "a stalled workline carries its answers: nudge the lead, hand it off, close it", %{ws: ws} do
      t = workline(ws, "review", 4)
      assert [need] = Enum.filter(Needs.list(), &(&1.kind == "stalled"))

      assert [%{actions: [nudge, hand, close | _]}] = Server.Alerts.build([need], [], DateTime.utc_now())
      assert %{label: "Nudge the lead", path: path, body: %{body: body}} = nudge
      assert path == "/api/threads/#{t.id}/messages" and body =~ "Nothing has moved"
      assert %{label: "Reassign…", input: "agent", path: hand_path} = hand
      assert hand_path == "/api/threads/#{t.id}/hand-off"
      assert %{label: "Close the thread…", input: "abandoned", path: close_path} = close
      assert close_path == "/api/threads/#{t.id}/close"
    end
  end

  describe "surface/1 — who acts on each kind" do
    test "the table: phone owes an answer, the machine is information, the clipboard is the crew's" do
      phone = ~w(gate question dialog ask seats quota no_seat tool_denied)
      machine = ~w(mention rollout)
      clipboard = ~w(issue stalled verify_failed pr_blocked publish_failed release_failed job_failed stranded)

      for k <- phone, do: assert(Needs.surface(k) == "phone")
      for k <- machine, do: assert(Needs.surface(k) == "machine")
      for k <- clipboard, do: assert(Needs.surface(k) == "clipboard")
      assert Enum.sort(Needs.kinds()) == Enum.sort(phone ++ machine ++ clipboard)
    end

    test "every kind has a surface" do
      for k <- Needs.kinds(), do: assert(Needs.surface(k) in ~w(phone machine clipboard))
    end

    test "an unlisted kind is not routed" do
      assert_raise FunctionClauseError, fn -> Needs.surface("brand_new") end
    end
  end
end
