defmodule Server.NotesTest do
  # The `Server.Notes` context (2026-08-30): funes-native scratch, write pipe + scoped reads.
  use ExUnit.Case, async: false

  alias Server.Bus
  alias Server.Note
  alias Server.Notes

  setup do
    Server.TestDB.clean!()
    :ok
  end

  describe "write/1" do
    test "writes a global note and announces on the notes topic" do
      Bus.subscribe_notes()
      {:ok, note} = Notes.write(%{body: "remember: leads are managers", author: "andrew"})
      assert %Note{scope: "global", scope_id: nil, body: "remember: leads are managers"} = note
      assert_receive {:note_written, %Note{}}
    end

    test "writes a project-scoped note" do
      {:ok, note} = Notes.write(%{scope: "project", scope_id: 7, body: "cockpit gotcha"})
      assert %Note{scope: "project", scope_id: 7} = note
    end

    test "a scoped note WITHOUT a scope_id is refused" do
      assert {:error, %Ecto.Changeset{}} = Notes.write(%{scope: "thread", body: "x"})
    end

    test "a global note WITH a scope_id is refused" do
      assert {:error, %Ecto.Changeset{}} = Notes.write(%{scope: "global", scope_id: 3, body: "x"})
    end

    test "an unknown scope is refused (not a DB raise)" do
      assert {:error, %Ecto.Changeset{}} = Notes.write(%{scope: "galaxy", scope_id: 1, body: "x"})
    end

    test "a missing body is refused" do
      assert {:error, %Ecto.Changeset{}} = Notes.write(%{scope: "global"})
    end
  end

  describe "for_scope/2" do
    test "returns notes in that scope, newest-first, and excludes other scopes" do
      {:ok, _} = Notes.write(%{body: "g1"})
      {:ok, _} = Notes.write(%{body: "g2"})
      {:ok, _} = Notes.write(%{scope: "project", scope_id: 1, body: "p1"})

      assert Enum.map(Notes.for_scope("global", nil), & &1.body) == ["g2", "g1"]
      assert Enum.map(Notes.for_scope("project", 1), & &1.body) == ["p1"]
      assert Notes.for_scope("project", 99) == []
    end
  end

  describe "edit/2 & remove/1" do
    test "edit updates body + re-stamps, announces" do
      Bus.subscribe_notes()
      {:ok, n} = Notes.write(%{body: "draft"})
      {:ok, edited} = Notes.edit(n, %{body: "final"})
      assert edited.body == "final"
      assert_receive {:note_edited, %Note{body: "final"}}
    end

    test "remove deletes and announces" do
      Bus.subscribe_notes()
      {:ok, n} = Notes.write(%{body: "temp"})
      assert {:ok, _} = Notes.remove(n)
      assert Notes.get(n.id) == nil
      assert_receive {:note_removed, %Note{}}
    end
  end
end
