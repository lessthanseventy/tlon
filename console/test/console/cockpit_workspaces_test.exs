defmodule Console.CockpitWorkspacesTest do
  @moduledoc """
  D2, Chunk 1: `Console.Author.register_workspace!/3` (D2.3) and `remove_workspace!/2` (D2.5) — the author
  face's `n`/`d` funes writes. Exercises the REAL `Server.Workspaces` write pipe (register/remove)
  through the cockpit's public, pure-ish wrappers against a
  `Console.TestRepo` scratch db → `async: false`.
  """
  use ExUnit.Case, async: false

  alias Console.Cockpit.Author
  alias Server.Repo
  alias Server.Workspace
  alias Server.Workspaces

  setup_all do
    Console.TestRepo.boot!("cockpit-workspaces")

    :ok
  end

  setup do
    # A clean workspace table per test — this suite writes rows (mirrors Console.WorkspacesTest).
    Repo.delete_all(Server.ChannelRow)
    Repo.delete_all(Workspace)
    :ok
  end

  defp state(overrides), do: Map.merge(%{active_key: 0, author_cursor: 0, flash: nil, input: nil}, overrides)

  describe "register_workspace!/3 — the author face's `n` verb (D2.3)" do
    test "a valid template + name registers a workspace, clears the input, and flashes success" do
      s = state(%{input: %{kind: :new_workspace, buffer: "Ficciones2", cursor: 10, template: :code}})
      next = Author.register_workspace!(s, :code, "Ficciones2")

      assert next.input == nil
      assert next.flash =~ "created Ficciones2"
      assert [%{name: "Ficciones2", type: "code"}] = Workspaces.all()
    end

    test "the end-to-end release-bar chain: register_workspace! → Server.Workspaces gets a 2nd row" do
      {:ok, _tlon} = Workspaces.register(%{name: "Tlön", type: "code"})
      next = Author.register_workspace!(state(%{}), :blank, "Ficciones2")

      assert next.flash =~ "created"
      names = Workspaces.all() |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Ficciones2", "Tlön"]
    end

    test "a duplicate name (UNIQUE(name)) flashes an error and keeps the input open — no 2nd insert" do
      {:ok, _} = Workspaces.register(%{name: "Tlön", type: "code"})
      s = state(%{input: %{kind: :new_workspace, buffer: "Tlön", cursor: 4, template: :code}})

      next = Author.register_workspace!(s, :code, "Tlön")

      assert next.input == %{kind: :new_workspace, buffer: "Tlön", cursor: 4, template: :code}
      assert next.flash =~ "couldn't create"
      assert length(Workspaces.all()) == 1
    end

    test "a blank name flashes and keeps the input open (the funes required-name changeset)" do
      s = state(%{input: %{kind: :new_workspace, buffer: "", cursor: 0, template: :blank}})
      next = Author.register_workspace!(s, :blank, "")

      assert next.input.kind == :new_workspace
      assert next.flash =~ "couldn't create"
      assert Workspaces.all() == []
    end
  end

  describe "remove_workspace!/2 — the author face's two-key `d` confirm (D2.5)" do
    test "removes the workspace and flashes success" do
      {:ok, _keep} = Workspaces.register(%{name: "Home", type: "blank"})
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Author.remove_workspace!(state(%{}), w.id)

      assert next.flash =~ "deleted Freedonia"
      assert Enum.map(Workspaces.all(), & &1.name) == ["Home"]
    end

    test "the LAST workspace is refused with a flash (threads must have a home)" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Author.remove_workspace!(state(%{}), w.id)

      assert next.flash =~ "last workspace"
      assert length(Workspaces.all()) == 1
    end

    test "removing the ACTIVE workspace lands on the first remaining one — never stranded on a dead space" do
      {:ok, keep} = Workspaces.register(%{name: "Home", type: "blank"})
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Author.remove_workspace!(state(%{active_key: w.id}), w.id)

      assert next.active_key == keep.id
    end

    test "removing a workspace that ISN'T active leaves active_key untouched" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Author.remove_workspace!(state(%{active_key: 0}), w.id)

      assert next.active_key == 0
    end

    test "author_cursor clamps to the shrunk list" do
      {:ok, w1} = Workspaces.register(%{name: "A", type: "blank"})
      {:ok, _w2} = Workspaces.register(%{name: "B", type: "blank"})

      next = Author.remove_workspace!(state(%{author_cursor: 1}), w1.id)

      assert next.author_cursor == 0
    end

    test "a missing workspace (already gone) flashes, never crashes" do
      next = Author.remove_workspace!(state(%{}), 999_999)
      assert next.flash =~ "already gone"
    end
  end

  describe "edit_workspace!/3 — the field editor's immediate apply (D2.4 Chunk 2a)" do
    test "a valid attrs map updates the row and flashes success" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "code"})
      next = Author.edit_workspace!(state(%{}), w.id, %{type: "life"})

      assert next.flash =~ "updated Freedonia"
      assert [%{name: "Freedonia", type: "life"}] = Workspaces.all()
    end

    test "scope applies through the wrapper; repos and the bench are their own verbs now" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Author.edit_workspace!(state(%{}), w.id, %{scope: "machine"})

      assert next.flash =~ "updated"
      assert [%{scope: "machine"}] = Workspaces.all()

      # Neither the scope rows nor the bench go through `edit_workspace!` any more — they are not
      # workspace columns, so a whole-list overwrite is not how either is edited (UX slice 5).
      Author.seat!(state(%{}), w.id, %{name: "amy", archetype: "assistant"})
      assert [%Server.Coworker{archetype: "assistant", name: "amy"}] = Workspaces.bench(w.id)
    end

    test "a missing workspace (already gone) flashes, never crashes" do
      next = Author.edit_workspace!(state(%{}), 999_999, %{type: "life"})
      assert next.flash =~ "already gone"
    end

    test "name is immutable — edit_changeset drops it, no error, no rename" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Author.edit_workspace!(state(%{}), w.id, %{name: "Ignored"})

      assert next.flash =~ "updated Freedonia"
      assert [%{name: "Freedonia"}] = Workspaces.all()
    end

    test "an invalid type (outside the DB CHECK's closed set) flashes, never crashes" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Author.edit_workspace!(state(%{}), w.id, %{type: "nonsense"})

      assert next.flash =~ "edit failed"
      assert [%{type: "blank"}] = Workspaces.all()
    end
  end

  describe "apply_coworker_knob!/3 — the roster sub-editor's Tab+Enter knob (D2.4 Chunk 2b, absorbs Settings)" do
    setup do
      path = Path.join(System.tmp_dir!(), "aleph_coworker_knob_test_#{System.unique_integer([:positive])}.json")
      previous = Application.get_env(:console, :config_path)
      Application.put_env(:console, :config_path, path)

      on_exit(fn ->
        Application.put_env(:console, :config_path, previous)
        File.rm(path)
      end)

      %{path: path}
    end

    defp roster_edit_state(id, overrides \\ %{}),
      do: state(Map.merge(%{author_edit: %{id: id, field: 3, sub: 0, mode: :sub, knob: :model}}, overrides))

    test ":model cycles the coworker's model ring one step and persists via Config", %{path: path} do
      {:ok, w} =
        Workspaces.register(%{name: "Freedonia", type: "blank", roster: [%{"archetype" => "surveyor", "name" => "amy"}]})

      next = Author.apply_coworker_knob!(roster_edit_state(w.id), "amy", :model)

      assert next.flash =~ "amy driver"
      assert next.flash =~ "applies on next spawn"
      override = Console.Config.coworker_model("amy", path)
      assert override
      # cycling again lands on the FOLLOWING ring entry — proves it's a cycle, not a fixed write.
      next2 = Author.apply_coworker_knob!(roster_edit_state(w.id), "amy", :model)
      assert Console.Config.coworker_model("amy", path) == Console.Profiles.next_model(override)
      assert next2.flash =~ "amy driver"
    end

    test ":yolo flips the coworker's permission policy and persists via Config", %{path: path} do
      {:ok, w} =
        Workspaces.register(%{name: "Freedonia", type: "blank", roster: [%{"archetype" => "surveyor", "name" => "amy"}]})

      next =
        Author.apply_coworker_knob!(
          roster_edit_state(w.id, %{author_edit: %{id: w.id, field: 3, sub: 0, mode: :sub, knob: :yolo}}),
          "amy",
          :yolo
        )

      assert next.flash =~ "amy permissions"
      assert Console.Config.coworker_yolo("amy", path) == true

      next2 = Author.apply_coworker_knob!(next, "amy", :yolo)
      assert Console.Config.coworker_yolo("amy", path) == false
      assert next2.flash =~ "ask"
    end

    test "a roster entry that's vanished (renamed/removed mid-edit) flashes, never crashes" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Author.apply_coworker_knob!(roster_edit_state(w.id), "ghost", :model)

      assert next.flash =~ "roster entry not found"
    end

    test "an already-gone workspace flashes, never crashes" do
      next = Author.apply_coworker_knob!(roster_edit_state(999_999), "amy", :model)
      assert next.flash =~ "roster entry not found"
    end
  end

  describe "the repos sub-list writes ROWS (UX slice 5)" do
    test "`a` adds a repo ROW — one prompt, all three columns" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia"})

      next = Author.add_repo!(state(%{}), w.id, "modules/* git@github.com:a/b.git main")

      assert next.flash =~ "added modules/*"

      assert [%{path: "modules/*", remote: "git@github.com:a/b.git", default_branch: "main"}] =
               Workspaces.repos(w.id)
    end

    test "a path alone leaves remote and branch UNANSWERED rather than inventing them" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia"})
      Author.add_repo!(state(%{}), w.id, "modules/*")

      assert [%{path: "modules/*", remote: nil, default_branch: nil}] = Workspaces.repos(w.id)
    end

    test "a blank buffer adds nothing" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia"})
      Author.add_repo!(state(%{}), w.id, "   ")

      assert Workspaces.repos(w.id) == []
    end

    test "a duplicate path flashes the changeset error instead of crashing" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", repos: ["modules/*"]})

      next = Author.add_repo!(state(%{}), w.id, "modules/*")

      assert next.flash =~ "couldn't add modules/*"
      assert length(Workspaces.repos(w.id)) == 1
    end

    test "`x`/`d` removes the row it names, by id" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", repos: ["a", "b"]})
      [a, b] = Workspaces.repos(w.id)

      next = Author.remove_repo!(state(%{}), w.id, a.id)

      assert next.flash =~ "removed a"
      assert Enum.map(Workspaces.repos(w.id), & &1.id) == [b.id]
    end

    test "removing a row that is already gone flashes, never crashes" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia"})

      next = Author.remove_repo!(state(%{}), w.id, 999_999)

      assert next.flash =~ "already gone"
    end
  end
end
