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

    test "only backwards, only to a working stage" do
      thread = at_review("forward")
      assert {:error, {:not_behind, "review"}} = Workline.send_back(thread, "review", "x", "hronir")
      assert {:error, {:not_behind, "merged"}} = Workline.send_back(thread, "merged", "x", "hronir")
      assert {:error, {:not_behind, "intent"}} = Workline.send_back(thread, "intent", "x", "hronir")
    end
  end

  describe "follow_ups/3" do
    test "each follow-up is a held ticket tied to the workline, handed to intake when it merges" do
      thread = at_review("with-nits")

      assert {:ok, [ticket]} =
               Workline.follow_ups(thread, "lonnrot", ["clean! could clear stray 99… rows\n\nIf the BEAM dies first."])

      assert ticket.title == "clean! could clear stray 99… rows"
      assert ticket.body =~ "If the BEAM dies first."
      assert ticket.body =~ "##{thread.id}"
      assert "held" in ticket.labels and "follow-up" in ticket.labels

      assert Repo.exists?(
               from tt in Server.TicketThread, where: tt.ticket_id == ^ticket.id and tt.thread_id == ^thread.id
             )

      {:awaiting, parked} = Workline.advance(Repo.get!(Thread, thread.id), artifacts: AllPresent)
      assert {:ok, %{stage: "merged"}} = Workline.approve(parked, artifacts: AllPresent, merge: Merges)

      released = Repo.get!(Server.Ticket, ticket.id)
      refute "held" in released.labels
      assert "follow-up" in released.labels
      assert Enum.any?(bodies(thread), &(&1 =~ "follow-up" and &1 =~ "##{ticket.id}"))
    end

    test "a blank follow-up files nothing" do
      thread = at_review("blank")
      assert {:ok, []} = Workline.follow_ups(thread, "lonnrot", ["  ", ""])
    end
  end
end
