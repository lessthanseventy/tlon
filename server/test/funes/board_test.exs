defmodule Server.BoardTest do
  # The board's read models (aleph §4): the pure aggregates a TUI/LiveView renders.
  # IN FLIGHT is the roster (live sessions × warmth); the BRIEF is one thread's read
  # (GOAL / TODOS / NEXT / DONE / LEARNINGS / BLOCKERS / RECENT) — the SAME
  # one-call read that briefs a re-entering session (§3b), one read, two consumers.
  # DONE is a MERGED view: completed todos by their `done_at` + `work_landed` events.
  use ExUnit.Case, async: false

  alias Server.Board
  alias Server.Channel
  alias Server.Dossier
  alias Server.Repo
  alias Server.Staff

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp cold(session), do: set_active(session, 7200)

  defp set_active(session, seconds_ago) do
    at = DateTime.utc_now() |> DateTime.shift(second: -seconds_ago) |> DateTime.truncate(:second)
    {:ok, s} = session |> Ecto.Changeset.change(last_active_at: at) |> Repo.update()
    s
  end

  describe "recent_activity/1 — the cockpit NOW backfill" do
    test "merges recent messages, facts, and events as {tag, row}, each carrying a thread_id" do
      {:ok, thread} = Channel.open_thread(%{title: "seed"})
      {:ok, _msg} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "shipping it"})
      {:ok, _fact} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "use sqlite", provenance: "derived"})
      {:ok, _event} = Dossier.record_event(%{thread_id: thread.id, kind: "work_landed", detail: %{"summary" => "landed"}})

      feed = Board.recent_activity(50)
      tags = Enum.map(feed, fn {tag, _row} -> tag end)

      assert :message_posted in tags
      assert :fact_banked in tags
      assert :event_recorded in tags
      # every seeded row carries thread_id so the cockpit's scope_activity/2 can filter by workspace
      assert Enum.all?(feed, fn {_tag, row} -> row.thread_id == thread.id end)
    end

    test "forgotten facts are left out of the seed" do
      {:ok, thread} = Channel.open_thread(%{title: "forget"})
      {:ok, fact} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "temporary", provenance: "derived"})

      fact
      |> Ecto.Changeset.change(forgotten_at: DateTime.truncate(DateTime.utc_now(), :second))
      |> Repo.update!()

      refute Enum.any?(Board.recent_activity(50), &match?({:fact_banked, _}, &1))
    end

    test "caps at the requested limit" do
      {:ok, thread} = Channel.open_thread(%{title: "many"})
      for i <- 1..8, do: {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: "m#{i}"})

      assert length(Board.recent_activity(3)) == 3
    end
  end

  describe "Staff.roster/0 — IN FLIGHT" do
    test "lists live sessions across threads with a warm/cold flag, omitting ended ones" do
      {:ok, thread} = Channel.open_thread(%{title: "one"})
      {:ok, other} = Channel.open_thread(%{title: "two"})
      {:ok, sandra} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      {:ok, robert} = Staff.register_agent(%{name: "Robert", mandate: "m", engine: "e"})

      {:ok, _warm} =
        Staff.start_session(%{agent_id: sandra.id, thread_id: thread.id, pane_ref: "wS"})

      {:ok, chilly} =
        Staff.start_session(%{agent_id: robert.id, thread_id: thread.id, pane_ref: "wR"})

      # Sandra's ended session lives on a SECOND thread — a second live session on
      # the same (thread, agent) would be superseded, not coexist (the zombie guard).
      {:ok, gone} =
        Staff.start_session(%{agent_id: sandra.id, thread_id: other.id, pane_ref: "wG"})

      cold(chilly)
      {:ok, _} = Staff.end_session(gone)

      roster = Staff.roster()
      refs = Enum.map(roster, & &1.pane_ref)
      assert "wS" in refs
      assert "wR" in refs
      refute "wG" in refs

      assert Enum.find(roster, &(&1.pane_ref == "wS")).warm? == true
      assert Enum.find(roster, &(&1.pane_ref == "wR")).warm? == false
      assert Enum.find(roster, &(&1.pane_ref == "wS")).agent == "Sandra"
    end
  end

  describe "Board.brief/1 — BRIEF" do
    test "assembles GOAL, lead, TODOS/NEXT/DONE, LEARNINGS, BLOCKERS, RECENT" do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
      {:ok, sandra} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      {:ok, _} = Staff.assign(thread, sandra)

      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "starting"})

      {:ok, _} =
        Dossier.bank_fact(%{
          thread_id: thread.id,
          kind: "learned",
          text: "a lesson",
          provenance: "derived"
        })

      {:ok, _} =
        Dossier.record_event(%{
          thread_id: thread.id,
          kind: "work_landed",
          detail: %{"summary" => "merged"}
        })

      {:ok, _} = Dossier.raise_issue(%{thread_id: thread.id, summary: "a blocker"})
      {:ok, _} = Dossier.raise_question(%{thread_id: thread.id, text: "does raxol embed?"})
      {:ok, _} = Dossier.record_check(%{thread_id: thread.id, cmd: "mise run check", exit: 0, tail: "ok"})

      {:ok, planned} = Dossier.add_todo(%{thread_id: thread.id, text: "planned step"})
      {:ok, _done} = Dossier.complete_todo(planned)
      {:ok, _} = Dossier.add_todo(%{thread_id: thread.id, text: "open step"})

      scope = Board.brief(thread)
      assert scope.goal == "review PR 329"
      assert scope.lead == "Sandra"
      # DONE is a MERGED view: the completed todo AND the work_landed event, tagged by source
      assert Enum.any?(scope.done.shown, &(&1.source == :event and &1.row.kind == "work_landed"))
      assert Enum.any?(scope.done.shown, &(&1.source == :todo and &1.row.text == "planned step"))
      # the open steps, and NEXT — the first open todo, derived
      assert Enum.any?(scope.todos.shown, &(&1.text == "open step"))
      assert scope.next.text == "open step"
      assert Enum.any?(scope.learnings.shown, &(&1.text == "a lesson"))
      assert Enum.any?(scope.unknowns.shown, &(&1.text == "does raxol embed?"))
      assert Enum.any?(scope.checks.shown, &(&1.kind == "check_passed"))
      assert Enum.any?(scope.blockers.shown, &(&1.summary == "a blocker"))
      assert Enum.any?(scope.recent, &(&1.body == "starting"))
    end

    test "DONE is capped WITH a count; LEARNINGS is budget-bounded, not row-capped" do
      # The silent-cap failure (pi doc §2b): for an agent whose only window into its memory is this
      # brief, a cut with no number reads as "this is everything." DONE still caps at five WITH a
      # count. LEARNINGS is now the token-budgeted working set — bounded by budget, not a row count
      # (design) — so under the generous default budget all seven small facts fit and `more` is 0;
      # the below-budget cut (still counted) is proven in the working-set describe block above.
      {:ok, thread} = Channel.open_thread(%{title: "t"})

      for n <- 1..7 do
        {:ok, _} =
          Dossier.bank_fact(%{
            thread_id: thread.id,
            kind: "learned",
            text: "fact #{n}",
            provenance: "derived"
          })
      end

      for n <- 1..6 do
        {:ok, _} =
          Dossier.record_event(%{
            thread_id: thread.id,
            kind: "work_landed",
            detail: %{"summary" => "landed #{n}"}
          })
      end

      scope = Board.brief(thread)
      assert length(scope.learnings.shown) == 7
      assert scope.learnings.more == 0
      # DONE here is 6 work_landed events (no todos) — capped at five with the count.
      assert length(scope.done.shown) == 5
      assert scope.done.more == 1
    end

    test "an unassigned thread has a nil lead, and empty sections count zero" do
      {:ok, thread} = Channel.open_thread(%{title: "unstaffed"})
      scope = Board.brief(thread)
      assert scope.lead == nil
      assert scope.learnings == %{shown: [], more: 0}
      assert scope.unknowns == %{shown: [], more: 0}
      assert scope.checks == %{shown: [], more: 0}
      assert scope.done == %{shown: [], more: 0}
      assert scope.todos == %{shown: [], more: 0}
      assert scope.next == nil
    end
  end

  describe "Board.brief/1 LEARNINGS — the forgetting engine's working set" do
    test "LEARNINGS ranks by strength, not recency" do
      {:ok, thread} = Channel.open_thread(%{title: "t"})

      # `proven` is banked FIRST (older), `plain` second (newer) — recency would surface `plain`
      # first, so an order that puts `proven` first proves strength drove the ranking.
      {:ok, proven} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "proven", provenance: "derived"})
      {:ok, _plain} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "plain", provenance: "derived"})
      {:ok, _} = Dossier.record_event(%{thread_id: thread.id, kind: "check_passed", correlation: "fact:#{proven.id}"})

      texts = Enum.map(Board.brief(thread).learnings.shown, & &1.text)
      assert Enum.find_index(texts, &(&1 == "proven")) < Enum.find_index(texts, &(&1 == "plain"))
    end

    test "a below-budget fact falls out of context and is COUNTED, not silently cut" do
      # A budget that fits ~one small fact (each is ~1 token) — the weaker one drops out of the
      # working set but is still on disk (get_facts returns it); `more` must own the cut. Budget
      # stays a config knob (the cost breaker's memory lever); the read path itself is unconditional.
      Application.put_env(:server, :recall, budget: 1)
      on_exit(fn -> Application.delete_env(:server, :recall) end)

      {:ok, thread} = Channel.open_thread(%{title: "t"})
      {:ok, _a} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "aaaa", provenance: "derived"})
      {:ok, b} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "bbbb", provenance: "derived"})
      {:ok, _} = Dossier.record_event(%{thread_id: thread.id, kind: "check_passed", correlation: "fact:#{b.id}"})

      learnings = Board.brief(thread).learnings
      assert length(learnings.shown) == 1
      assert hd(learnings.shown).text == "bbbb"
      assert learnings.more == 1
    end
  end

  describe "machine_overview/0 — the Orbis Tertius cross-leaf read" do
    test "every OPEN machine thread as a compact brief; project + closed threads never leak in" do
      {:ok, _root} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      {:ok, leaf} = Channel.open_thread(%{title: "reaper fix", scope: "machine"})
      {:ok, _proj} = Channel.open_thread(%{title: "a project thread"})
      {:ok, closed} = Channel.open_thread(%{title: "done leaf", scope: "machine"})
      {:ok, _} = Channel.close_thread(closed)

      {:ok, _agent} = Staff.register_agent(%{name: "claude-machine", mandate: "machine", engine: "claude"})
      Server.assign_lead(leaf.id, "claude-machine")
      {:ok, _} = Dossier.add_todo(%{thread_id: leaf.id, text: "wire the reaper"})
      {:ok, _} = Dossier.raise_issue(%{thread_id: leaf.id, summary: "port 4041 held"})
      {:ok, _} = Channel.post(%{thread_id: leaf.id, author: "claude-machine", body: "on it"})

      overview = Board.machine_overview()
      titles = Enum.map(overview, & &1.title)
      assert "Tlön" in titles
      assert "reaper fix" in titles
      # scope isolation (a machine agent never peeks at project work) + open-only
      refute "a project thread" in titles
      refute "done leaf" in titles

      leaf_row = Enum.find(overview, &(&1.title == "reaper fix"))
      assert leaf_row.lead == "claude-machine"
      assert leaf_row.next == "wire the reaper"
      assert "port 4041 held" in leaf_row.blockers
      assert Enum.any?(leaf_row.recent, &(&1.body == "on it"))
    end

    test "root-first ordering — the founding thread (oldest id) leads the overview" do
      {:ok, _root} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      {:ok, _leaf} = Channel.open_thread(%{title: "leaf", scope: "machine"})
      assert [%{title: "Tlön"} | _] = Board.machine_overview()
    end
  end
end
