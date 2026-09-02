defmodule FunesTest do
  # The boundary surface (lib/funes.ex). Most exports are straight delegates covered by their
  # internal modules' tests; these cover the wrappers that add logic of their own — the id-based
  # habit write path, which loads fresh and has a not-found branch the struct-based Dossier
  # functions don't.
  use ExUnit.Case, async: false

  alias Server.Dossier

  setup do
    Server.TestDB.clean!()
    :ok
  end

  describe "approve_habit/1 & reject_habit/1 — id-based, load-fresh" do
    test "approve_habit(id) loads the pending habit and approves it" do
      {:ok, habit} = Dossier.propose_habit(%{text: "prefer the Claude bucket", proposed_by: "glm-5.2"})

      assert {:ok, approved} = Server.approve_habit(habit.id)
      assert approved.state == "approved"
      assert Enum.map(Server.pending_habits(), & &1.id) == []
    end

    test "reject_habit(id) loads the pending habit and rejects it" do
      {:ok, habit} = Dossier.propose_habit(%{text: "a bad idea", proposed_by: "glm-5.2"})

      assert {:ok, rejected} = Server.reject_habit(habit.id)
      assert rejected.state == "rejected"
    end

    test "a missing id is {:error, :not_found}, not a crash" do
      assert Server.approve_habit(999_999) == {:error, :not_found}
      assert Server.reject_habit(999_999) == {:error, :not_found}
    end
  end

  describe "pending_habits/0 & pinned/0 — the Memory pane reads" do
    test "pending_habits returns only pending habits, newest first" do
      {:ok, _} = Dossier.propose_habit(%{text: "first", proposed_by: "a"})
      {:ok, second} = Dossier.propose_habit(%{text: "second", proposed_by: "a"})

      assert Enum.map(Server.pending_habits(), & &1.text) == ["second", "first"]
      assert {:ok, _} = Server.approve_habit(second.id)
      assert Enum.map(Server.pending_habits(), & &1.text) == ["first"]
    end

    test "pinned/0 mirrors always_loaded_constraints/0" do
      assert Server.pinned() == Dossier.always_loaded_constraints()
    end
  end
end
