defmodule Server.Office.NeedsTest do
  # Everything waiting on the operator, as one list built from the state that already says so —
  # blocking first, then what to decide when convenient.
  use ExUnit.Case, async: false

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

  test "a corkboard suggestion is banter, not a request: it stays in the suggestion box, out of the list",
       %{ws: ws} do
    {:ok, _} = Channel.open_thread(%{title: "standing", scope: "machine", workspace_id: ws.id})
    {:ok, _} = Channel.open_thread(%{title: "work", workspace_id: ws.id})
    start_supervised!(Server.Office.Corkboard)

    GenServer.cast(
      Server.Office.Corkboard,
      {:pinned, ws.id, %{author: "lonnrot", kind: "suggestion", body: "a north wall for the lobby", re: nil}}
    )

    :sys.get_state(Server.Office.Corkboard)
    assert [%{author: "lonnrot"}] = Server.Office.Corkboard.suggestions(ws.id)
    assert kinds(ws) == []
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
      {:ok, _} = Server.Attention.answer_ask(a.id, "andrew", "1")
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
  end
end
