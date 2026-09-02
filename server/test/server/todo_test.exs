defmodule Server.TodoTest do
  # The activity axis (pi doc §5 slice 3): todos are plan steps scoped to a thread,
  # open until `done_at`. The reads are the load-bearing part — TODOS capped+counted in
  # INSERTION order (NEXT is the first open one, derived), DONE the completed set — so
  # they get the tests. Shared DB, no sandbox; every assertion reads back through SQLite.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier
  alias Server.Repo
  alias Server.Todo

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "wire the composer"})
    %{thread: thread}
  end

  describe "add_todo/1 and complete_todo/1" do
    test "add_todo opens an open todo (done_at nil) that reads back", %{thread: thread} do
      assert {:ok, todo} = Dossier.add_todo(%{thread_id: thread.id, text: "wire Channel.post"})
      assert todo.text == "wire Channel.post"
      assert is_nil(todo.done_at)

      row = Repo.get(Todo, todo.id)
      assert row.thread_id == thread.id
      assert is_nil(row.done_at)
    end

    test "add_todo requires text and thread_id", %{thread: thread} do
      assert {:error, _} = Dossier.add_todo(%{thread_id: thread.id})
      assert {:error, _} = Dossier.add_todo(%{text: "no thread"})
    end

    test "complete_todo stamps done_at (and is idempotent on the stamp)", %{thread: thread} do
      {:ok, todo} = Dossier.add_todo(%{thread_id: thread.id, text: "do it"})
      assert {:ok, done} = Dossier.complete_todo(todo)
      assert done.done_at

      first_stamp = done.done_at
      {:ok, again} = Dossier.complete_todo(Repo.get(Todo, todo.id))
      assert again.done_at == first_stamp
    end
  end

  describe "open_todos_for_thread/1 — TODOS, capped + counted, insertion order" do
    test "open todos in insertion order, cut at five with a count", %{thread: thread} do
      todos = for i <- 1..7, do: elem(Dossier.add_todo(%{thread_id: thread.id, text: "step #{i}"}), 1)
      # complete the second — it drops out of the open set
      Dossier.complete_todo(Enum.at(todos, 1))

      %{shown: shown, more: more} = Dossier.open_todos_for_thread(thread)
      assert length(shown) == 5
      assert more == 1
      # NEXT is the head: earliest open todo, never the completed step 2
      assert hd(shown).text == "step 1"
      refute Enum.any?(shown, &(&1.text == "step 2"))
    end

    test "only this thread's open todos (thread-scoped)", %{thread: thread} do
      {:ok, other} = Channel.open_thread(%{title: "other"})
      Dossier.add_todo(%{thread_id: other.id, text: "elsewhere"})
      Dossier.add_todo(%{thread_id: thread.id, text: "here"})

      %{shown: shown, more: more} = Dossier.open_todos_for_thread(thread)
      assert Enum.map(shown, & &1.text) == ["here"]
      assert more == 0
    end
  end

  describe "done_todos_for_thread/1 — the completed set for the DONE merge" do
    test "returns only completed todos, scoped to the thread", %{thread: thread} do
      {:ok, a} = Dossier.add_todo(%{thread_id: thread.id, text: "a"})
      {:ok, _b} = Dossier.add_todo(%{thread_id: thread.id, text: "b open"})
      Dossier.complete_todo(a)

      done = Dossier.done_todos_for_thread(thread)
      assert Enum.map(done, & &1.text) == ["a"]
      assert Enum.all?(done, &(not is_nil(&1.done_at)))
    end
  end
end
