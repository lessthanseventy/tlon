defmodule Server.WorklineSendBackTest do
  # A workline moves backwards on the same thread and branch, so what was built and reviewed comes
  # with it: back to build by the stage's lead, back to plan or spec only by the tech lead (a
  # coherence call) or the operator. A reviewer's non-blocking findings become follow-up tickets,
  # held until the workline merges, then handed to intake.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline

  defmodule AllPresent do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, {:file, name}), do: {:ok, "committed #{name}"}
    def check(_thread, :branch), do: {:ok, "work/x @ abc123"}
    def check(_thread, :checks), do: {:ok, "1 verify check_passed"}
  end

  defmodule Merges do
    @moduledoc false
    def merge(_repo, _slug, _opts \\ []), do: {:ok, %{from: "a", to: "b"}}
  end

  setup do
    Server.TestDB.clean!()
    :ok
  end

  # hronir is the bench's first builder, so its tech lead
  defp at_review(slug) do
    roster = [
      %{"archetype" => "builder", "name" => "hronir"},
      %{"archetype" => "builder", "name" => "emma"},
      %{"archetype" => "planner", "name" => "yu"},
      %{"archetype" => "reviewer", "name" => "lonnrot"}
    ]

    {:ok, ws} = Server.Workspaces.register(%{name: "Back #{slug}", roster: roster})
    {:ok, built} = Workline.open(%{title: "bench: #{slug}", slug: slug, stage: "build", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(built.id, "emma")
    {:ok, verifying} = Workline.advance(Repo.get!(Thread, built.id), artifacts: AllPresent)
    {:ok, reviewing} = Workline.advance(verifying, artifacts: AllPresent)
    reviewing
  end

  defp bodies(thread), do: thread |> Channel.thread_messages() |> Enum.map(& &1.body)

  defp last_move(thread) do
    Repo.one(
      from e in Server.Event,
        where: e.thread_id == ^thread.id and e.kind == "stage_advanced",
        order_by: [desc: e.id],
        limit: 1,
        select: e.detail
    )
  end

  describe "send_back/4" do
    test "the tech lead sends it back to plan: a planner leads, told the build stays to be improved" do
      thread = at_review("wrong-shape")

      assert {:ok, back} = Workline.send_back(thread, "plan", "the fixtures share one db", "hronir")
      assert %Thread{stage: "plan", awaiting: nil, state: "open"} = back
      assert Channel.thread_lead(thread.id) == "yu"

      brief = thread |> bodies() |> Enum.find(&(&1 =~ "back to plan"))
      assert brief =~ "the fixtures share one db"
      assert brief =~ "hronir"
      assert brief =~ "keeps the build"
    end

    test "a reviewer can't send it back past build — it names the tech lead to ask" do
      thread = at_review("not-mine")

      assert {:error, {:not_yours, why}} = Workline.send_back(thread, "plan", "design", "lonnrot")
      assert why =~ "hronir"
      assert %Thread{stage: "review"} = Repo.get!(Thread, thread.id)
    end

    test "its lead sends it back to build; the operator can send it anywhere behind it" do
      thread = at_review("to-build")
      lead = Channel.thread_lead(thread.id)

      assert {:ok, %Thread{stage: "build"}} = Workline.send_back(thread, "build", "a nit that matters", lead)

      other = at_review("by-andrew")
      assert {:ok, %Thread{stage: "spec"}} = Workline.send_back(other, "spec", "wrong problem", "andrew")
    end

    test "a builder who isn't its lead can't send it back at all" do
      thread = at_review("not-lead")
      assert {:error, {:not_yours, _}} = Workline.send_back(thread, "build", "x", "emma")
    end

    test "a merged workline isn't sent back — it relands; a landing or verify in flight is let finish" do
      merged = at_review("landed")
      {:awaiting, parked} = Workline.advance(Repo.get!(Thread, merged.id), artifacts: AllPresent)
      {:ok, _} = Workline.approve(parked, artifacts: AllPresent, merge: Merges)
      landed = Repo.get!(Thread, merged.id)
      assert {:error, {:not_movable, "merged"}} = Workline.send_back(landed, "build", "x", "andrew")

      landing = at_review("landing")
      %{thread_id: landing.id} |> Server.Jobs.Land.new() |> Repo.insert!()
      assert {:error, {:in_flight, why}} = Workline.send_back(landing, "plan", "x", "hronir")
      assert why =~ "landing"
      assert %Thread{stage: "review"} = Repo.get!(Thread, landing.id)
    end

    test "a landing queued while the send-back waits on the row is seen once the lock is let go" do
      thread = at_review("racing")
      test = self()

      racer =
        Task.async(fn ->
          Repo.transaction(fn ->
            Repo.one!(from t in Thread, where: t.id == ^thread.id, lock: "FOR UPDATE")
            %{thread_id: thread.id} |> Server.Jobs.Land.new() |> Repo.insert!()
            send(test, :locked)
            Process.sleep(300)
          end)
        end)

      assert_receive :locked
      assert {:error, {:in_flight, _}} = Workline.send_back(thread, "plan", "x", "hronir")
      Task.await(racer)
      assert %Thread{stage: "review"} = Repo.get!(Thread, thread.id)
    end

    test "a landing that starts while a send-back holds the row waits, then finds it moved and does nothing" do
      thread = at_review("lands-after")
      test = self()

      sender =
        Task.async(fn ->
          Repo.transaction(fn ->
            locked = Repo.one!(from t in Thread, where: t.id == ^thread.id, lock: "FOR UPDATE")
            {:ok, _} = locked |> Thread.workline_stage_changeset(%{stage: "plan"}) |> Repo.update()
            send(test, :moving)
            Process.sleep(300)
          end)
        end)

      assert_receive :moving
      job = %Oban.Job{args: %{"thread_id" => thread.id}, attempt: 1, max_attempts: 3}
      assert :ok = Server.Jobs.Land.perform(job)
      Task.await(sender)
      assert %Thread{stage: "plan", state: "open"} = Repo.get!(Thread, thread.id)
    end

    test "a send-back and a review's request for changes record the seat that moved it back" do
      thread = at_review("by-whom")
      assert {:ok, _} = Workline.send_back(thread, "build", "the wick", "hronir")
      assert %{"by" => "hronir", "bounced" => "sent back by hronir: the wick"} = last_move(thread)

      {1, _} = Repo.update_all(from(t in Thread, where: t.id == ^thread.id), set: [stage: "review"])

      assert {:error, {:bounced, _}} =
               Workline.review_verdict(Repo.get!(Thread, thread.id), "request_changes", "lonnrot", branch_head: nil)

      assert %{"by" => "lonnrot", "bounced" => "the review requested changes"} = last_move(thread)
    end

    test "only backwards, only to a working stage" do
      thread = at_review("forward")
      assert {:error, {:not_behind, "review"}} = Workline.send_back(thread, "review", "x", "hronir")
      assert {:error, {:not_behind, "merged"}} = Workline.send_back(thread, "merged", "x", "hronir")
      assert {:error, {:not_behind, "intent"}} = Workline.send_back(thread, "intent", "x", "hronir")
    end
  end

  describe "follow_ups/4" do
    test "posts the findings on the workline for its lead, numbered, and files no ticket" do
      thread = at_review("with-nits")
      lead = Channel.thread_lead(thread.id)

      assert {:ok, [_, _]} =
               Workline.follow_ups(thread, "nolan", [
                 "clean! could clear stray 99… rows\n\nIf the BEAM dies first.",
                 "a typo in the help"
               ])

      assert [post] = Enum.filter(bodies(thread), &(&1 =~ "follow-ups from nolan's review"))

      assert post =~ "1. clean! could clear stray 99… rows" and post =~ "If the BEAM dies first." and
               post =~ "2. a typo"

      if lead, do: assert(post =~ "@#{lead}")
      assert post =~ "file_ticket"
      assert Repo.all(Server.Ticket) == []
    end

    test "blanks and repeated titles are dropped; nothing to say posts nothing" do
      thread = at_review("blank")
      assert {:ok, []} = Workline.follow_ups(thread, "lonnrot", ["  ", ""])
      refute Enum.any?(bodies(thread), &(&1 =~ "follow-ups from"))
      assert {:ok, [_]} = Workline.follow_ups(thread, "lonnrot", ["twice\n\na", "twice\n\nb"])
    end

    test "a held follow-up filed before still reaches intake when its workline closes, saying so" do
      thread = at_review("abandoned")

      {:ok, ticket} =
        Server.Tickets.file(%{
          workspace_id: thread.workspace_id || Server.Bootstrap.default_workspace_id(),
          title: "an old nit",
          labels: ["follow-up", "held", "from-review"]
        })

      {:ok, _} = Server.Tickets.tie(ticket, thread.id, "relates")

      {:ok, _} = Channel.close_thread(Repo.get!(Thread, thread.id))

      released = Repo.get!(Server.Ticket, ticket.id)
      refute "held" in released.labels
      assert released.body =~ "closed without merging"
    end
  end
end
