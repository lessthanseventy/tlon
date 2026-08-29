defmodule Console.CockpitWorkspacesTest do
  @moduledoc """
  D2, Chunk 1: `Console.Cockpit.register_workspace!/3` (D2.3) and `remove_workspace!/2` (D2.5) — the author
  face's `n`/`d` funes writes. Exercises the REAL `Server.Workspaces` write pipe (register/remove)
  through the cockpit's public, pure-ish wrappers (like `cycle_pane_view/2`/`attach_leaf/2`),
  mirroring `Console.WorkspacesTest`'s temp-DB setup — aleph's `config/test.exs` keeps funes' Repo down,
  so this suite boots it itself. One of the few aleph suites touching the DB → `async: false`.
  """
  use ExUnit.Case, async: false

  alias Console.Cockpit
  alias Ecto.Adapters.SQLite3
  alias Server.Repo
  alias Server.Workspace
  alias Server.Workspaces

  setup_all do
    db = Path.join(System.tmp_dir!(), "aleph_cockpit_workspaces_test_#{System.unique_integer([:positive])}.db")
    Application.put_env(:server, Repo, Keyword.merge(Application.get_env(:server, Repo, []), database: db, pool_size: 1))

    config = Repo.config()
    _ = SQLite3.storage_down(config)
    :ok = SQLite3.storage_up(config)
    {:ok, _repo} = Repo.start_link()
    Ecto.Migrator.run(Repo, :up, all: true)

    on_exit(fn ->
      if Process.whereis(Repo), do: Repo.stop()
      _ = SQLite3.storage_down(config)
    end)

    :ok
  end

  setup do
    # A clean workspace table per test — this suite writes rows (mirrors Console.WorkspacesTest).
    Repo.delete_all(Workspace)
    :ok
  end

  defp state(overrides), do: Map.merge(%{active_key: :orbis, author_cursor: 0, flash: nil, input: nil}, overrides)

  describe "register_workspace!/3 — the author face's `n` verb (D2.3)" do
    test "a valid template + name registers a workspace, clears the input, and flashes success" do
      s = state(%{input: %{kind: :new_workspace, buffer: "Ficciones2", cursor: 10, template: :code}})
      next = Cockpit.register_workspace!(s, :code, "Ficciones2")

      assert next.input == nil
      assert next.flash =~ "created Ficciones2"
      assert [%{name: "Ficciones2", type: "code"}] = Workspaces.all()
    end

    test "the end-to-end release-bar chain: register_workspace! → Server.Workspaces gets a 2nd row" do
      {:ok, _tlon} = Workspaces.register(%{name: "Tlön", type: "code"})
      next = Cockpit.register_workspace!(state(%{}), :blank, "Ficciones2")

      assert next.flash =~ "created"
      names = Workspaces.all() |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["Ficciones2", "Tlön"]
    end

    test "a duplicate name (UNIQUE(name)) flashes an error and keeps the input open — no 2nd insert" do
      {:ok, _} = Workspaces.register(%{name: "Tlön", type: "code"})
      s = state(%{input: %{kind: :new_workspace, buffer: "Tlön", cursor: 4, template: :code}})

      next = Cockpit.register_workspace!(s, :code, "Tlön")

      assert next.input == %{kind: :new_workspace, buffer: "Tlön", cursor: 4, template: :code}
      assert next.flash =~ "couldn't create"
      assert length(Workspaces.all()) == 1
    end

    test "a blank name flashes and keeps the input open (the funes required-name changeset)" do
      s = state(%{input: %{kind: :new_workspace, buffer: "", cursor: 0, template: :blank}})
      next = Cockpit.register_workspace!(s, :blank, "")

      assert next.input.kind == :new_workspace
      assert next.flash =~ "couldn't create"
      assert Workspaces.all() == []
    end
  end

  describe "remove_workspace!/2 — the author face's two-key `d` confirm (D2.5)" do
    test "removes the workspace and flashes success" do
      {:ok, _keep} = Workspaces.register(%{name: "Home", type: "blank"})
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.remove_workspace!(state(%{}), w.id)

      assert next.flash =~ "deleted Freedonia"
      assert Enum.map(Workspaces.all(), & &1.name) == ["Home"]
    end

    test "the LAST workspace is refused with a flash (threads must have a home)" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.remove_workspace!(state(%{}), w.id)

      assert next.flash =~ "last workspace"
      assert length(Workspaces.all()) == 1
    end

    test "removing the ACTIVE workspace resolves active_key to :orbis — never stranded on a dead space" do
      {:ok, _keep} = Workspaces.register(%{name: "Home", type: "blank"})
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.remove_workspace!(state(%{active_key: w.id}), w.id)

      assert next.active_key == :orbis
    end

    test "removing a workspace that ISN'T active leaves active_key untouched" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.remove_workspace!(state(%{active_key: :orbis}), w.id)

      assert next.active_key == :orbis
    end

    test "author_cursor clamps to the shrunk list" do
      {:ok, w1} = Workspaces.register(%{name: "A", type: "blank"})
      {:ok, _w2} = Workspaces.register(%{name: "B", type: "blank"})

      next = Cockpit.remove_workspace!(state(%{author_cursor: 1}), w1.id)

      assert next.author_cursor == 0
    end

    test "a missing workspace (already gone) flashes, never crashes" do
      next = Cockpit.remove_workspace!(state(%{}), 999_999)
      assert next.flash =~ "already gone"
    end
  end

  describe "edit_workspace!/3 — the field editor's immediate apply (D2.4 Chunk 2a)" do
    test "a valid attrs map updates the row and flashes success" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "code"})
      next = Cockpit.edit_workspace!(state(%{}), w.id, %{type: "life"})

      assert next.flash =~ "updated Freedonia"
      assert [%{name: "Freedonia", type: "life"}] = Workspaces.all()
    end

    test "scope, paths, and roster all apply through the same wrapper" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      Cockpit.edit_workspace!(state(%{}), w.id, %{scope: "machine"})
      Cockpit.edit_workspace!(state(%{}), w.id, %{paths: ["a", "b"]})
      next = Cockpit.edit_workspace!(state(%{}), w.id, %{roster: [%{"archetype" => "assistant", "name" => "amy"}]})

      assert next.flash =~ "updated"

      assert [%{scope: "machine", paths: ["a", "b"], roster: [%{"archetype" => "assistant", "name" => "amy"}]}] =
               Workspaces.all()
    end

    test "a missing workspace (already gone) flashes, never crashes" do
      next = Cockpit.edit_workspace!(state(%{}), 999_999, %{type: "life"})
      assert next.flash =~ "already gone"
    end

    test "name is immutable — edit_changeset drops it, no error, no rename" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.edit_workspace!(state(%{}), w.id, %{name: "Ignored"})

      assert next.flash =~ "updated Freedonia"
      assert [%{name: "Freedonia"}] = Workspaces.all()
    end

    test "an invalid type (outside the DB CHECK's closed set) flashes, never crashes" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.edit_workspace!(state(%{}), w.id, %{type: "nonsense"})

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

      next = Cockpit.apply_coworker_knob!(roster_edit_state(w.id), "amy", :model)

      assert next.flash =~ "amy driver"
      assert next.flash =~ "applies on next spawn"
      override = Console.Config.coworker_model("amy", path)
      assert override
      # cycling again lands on the FOLLOWING ring entry — proves it's a cycle, not a fixed write.
      next2 = Cockpit.apply_coworker_knob!(roster_edit_state(w.id), "amy", :model)
      assert Console.Config.coworker_model("amy", path) == Console.Profiles.next_model(override)
      assert next2.flash =~ "amy driver"
    end

    test ":yolo flips the coworker's permission policy and persists via Config", %{path: path} do
      {:ok, w} =
        Workspaces.register(%{name: "Freedonia", type: "blank", roster: [%{"archetype" => "surveyor", "name" => "amy"}]})

      next =
        Cockpit.apply_coworker_knob!(
          roster_edit_state(w.id, %{author_edit: %{id: w.id, field: 3, sub: 0, mode: :sub, knob: :yolo}}),
          "amy",
          :yolo
        )

      assert next.flash =~ "amy permissions"
      assert Console.Config.coworker_yolo("amy", path) == true

      next2 = Cockpit.apply_coworker_knob!(next, "amy", :yolo)
      assert Console.Config.coworker_yolo("amy", path) == false
      assert next2.flash =~ "ask"
    end

    test "a roster entry that's vanished (renamed/removed mid-edit) flashes, never crashes" do
      {:ok, w} = Workspaces.register(%{name: "Freedonia", type: "blank"})
      next = Cockpit.apply_coworker_knob!(roster_edit_state(w.id), "ghost", :model)

      assert next.flash =~ "roster entry not found"
    end

    test "an already-gone workspace flashes, never crashes" do
      next = Cockpit.apply_coworker_knob!(roster_edit_state(999_999), "amy", :model)
      assert next.flash =~ "roster entry not found"
    end
  end
end
