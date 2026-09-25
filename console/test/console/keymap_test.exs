defmodule Console.KeymapTest do
  @moduledoc """
  The keyhandling contract, tested as a pure reducer with no TTY (design §8: the cockpit's one
  brain, extracted from its paint). `Console.Keymap.handle/2` maps `(key_event, state)` to
  `{new_state, effect}`; the Cockpit interprets the effect (`:repaint` / `:quit` /
  `{:forward, key}` / `{:create_thread, title}` / `:none`).

  **Input model — tmux-style** (see `docs/plans/2026-08-16-aleph-tmux-style-input.md`): a live
  terminal in the center forwards every key by default; aleph's commands are reached through a
  `Ctrl+Space` STICKY toggle (Ctrl+B belongs to tmux in the Tlön center and forwards like any key).
  With no live terminal the same commands are bare. `center_live?` is derived by
  the cockpit; the tests set it directly. Every binding is asserted here so a regression like
  "Ctrl+C quit aleph again" or "arrows stopped moving focus" is caught headlessly.
  """
  use ExUnit.Case, async: true

  alias Console.Cockpit.Drawer
  alias Console.Keymap
  alias Console.Panel.Stack
  alias Console.Tlon.Focus

  # Workspace fixture: the hardcoded fallback Workspace is gone (reshape slice A); suites
  # that render or drive a Workspace push one through the Console.Workspaces cache-down seam.
  setup do
    Console.TestWorkspaces.put()
  end

  # The slice of cockpit state the keymap reads. Threads are anything with an `.id`.
  # `center_live?` and `composer_thread_id` are derived per keypress by the cockpit; here they're
  # set explicitly per test (`composer_thread_id` defaults to the focused thread).
  # two workspaces for the space ring — the cockpit threads the live cache in as `live_workspaces`
  defp two_workspaces,
    do: [
      %{id: 1, name: "Tlön", bench: [], type: "code", repos: [], scope: "machine"},
      %{id: 2, name: "Freedonia", bench: [], type: "code", repos: [], scope: "machine"}
    ]

  defp state(overrides \\ %{}) do
    base =
      Map.merge(
        %{
          # the server-down sentinel: a Workspace key with no space (no focus struct either, so
          # keys reach the command table directly, bare)
          active_key: 0,
          focused_id: 2,
          threads: [%{id: 1}, %{id: 2}, %{id: 3}],
          center_live?: false,
          input: nil,
          # the drawer (UX slice 1): CONFIG hosts the Author — its tests open it explicitly
          drawer: nil,
          last_drawer: :memory,
          author_cursor: 0,
          live_workspaces: [],
          pending_delete: nil,
          # The field editor's own state (D2.4 Chunk 2a) — nil off the edit screen; the "editing a
          # workspace" describe block below sets it.
          author_edit: nil
        },
        overrides
      )

    Map.put_new(base, :composer_thread_id, base.focused_id)
  end

  defp key(k, opts \\ []), do: Enum.into(opts, %{key: k})

  # Ctrl+Space: the STICKY term↔nav toggle in a workspace (it stopped being a leader in slice 2).
  defp ctrl_space, do: key(:space, ctrl: true)
  defp char(c, opts \\ []), do: Enum.into(opts, %{key: :char, char: c})

  # A workspace state with the thread stack as the focused center — the handle_tlon path.
  defp stack_ctx(over \\ %{}) do
    base = %{
      active_key: 0,
      center_view: :chat,
      opened_thread: nil,
      focus: %Focus{in_terminal?: true},
      threads: [%{id: 1}, %{id: 2}, %{id: 3}],
      focused_id: 2
    }

    state(Map.merge(base, over))
  end

  describe "Shift+Space normalizes to a plain space" do
    test "in the composer it inserts a space, not a dropped key" do
      s = state(%{input: %{kind: :compose, thread_id: 1, buffer: "a", cursor: 1}})
      {next, :repaint} = Keymap.handle(key(:space, shift: true), s)
      assert next.input.buffer == "a "
    end

    test "with a live terminal it forwards a real space char (not the modified key)" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: " "}}} = Keymap.handle(key(:space, shift: true), s)
    end

    test "Ctrl+Space is untouched — it still reaches the terminal as itself" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :space, ctrl: true}}} = Keymap.handle(key(:space, ctrl: true), s)
    end
  end

  describe "Ctrl+Space, Ctrl+B, Ctrl+C" do
    test "Ctrl+C never quits — it is unbound in nav context (no live terminal)" do
      s = state(%{center_live?: false})
      assert {^s, :none} = Keymap.handle(char("c", ctrl: true), s)
    end

    test "Ctrl+B forwards to the terminal when one is live — it is tmux's prefix, not aleph's" do
      s = state(%{center_live?: true})
      k = char("b", ctrl: true)
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end

    test "Ctrl+C forwards to the terminal when one is live — never a quit" do
      s = state(%{center_live?: true})
      k = char("c", ctrl: true)
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end
  end

  describe "bare keys in a nav-default space (no live terminal)" do
    test "q quits" do
      assert {_state, :quit} = Keymap.handle(char("q"), state())
    end

    test "Tab moves to the next workspace and repaints" do
      s = state(%{active_key: 1, live_workspaces: two_workspaces()})
      assert {%{active_key: 2}, :repaint} = Keymap.handle(key(:tab), s)
    end

    test "Shift-Tab moves to the previous workspace (wraps)" do
      s = state(%{active_key: 1, live_workspaces: two_workspaces()})
      assert {%{active_key: 2}, :repaint} = Keymap.handle(key(:tab, shift: true), s)
    end

    test "Down and j both move focus forward" do
      assert {%{focused_id: 3}, :repaint} = Keymap.handle(key(:down), state(%{focused_id: 2}))
      assert {%{focused_id: 3}, :repaint} = Keymap.handle(char("j"), state(%{focused_id: 2}))
    end

    test "Up and k both move focus backward" do
      assert {%{focused_id: 1}, :repaint} = Keymap.handle(key(:up), state(%{focused_id: 2}))
      assert {%{focused_id: 1}, :repaint} = Keymap.handle(char("k"), state(%{focused_id: 2}))
    end

    test "focus clamps at the top edge — no wrap" do
      assert {%{focused_id: 1}, :repaint} = Keymap.handle(key(:up), state(%{focused_id: 1}))
    end

    test "focus clamps at the bottom edge — no wrap" do
      assert {%{focused_id: 3}, :repaint} = Keymap.handle(key(:down), state(%{focused_id: 3}))
    end

    test "movement on an empty thread list is a no-op" do
      s = state(%{threads: [], focused_id: nil})
      assert {^s, :none} = Keymap.handle(key(:down), s)
    end
  end

  describe "Panel.Author's row cursor (D2.2: author_cursor, in the drawer's CONFIG pane)" do
    @two_author_workspaces [%{id: 11, name: "Tlön"}, %{id: 22, name: "Freedonia"}]

    defp author_state(overrides),
      do: state(Map.merge(%{drawer: :config, live_workspaces: @two_author_workspaces}, overrides))

    test "j/k (and ↑/↓) move author_cursor, clamped 0..length(live_workspaces)-1 — no wrap" do
      s = author_state(%{author_cursor: 0})
      assert {%{author_cursor: 1}, :repaint} = Keymap.handle(char("j"), s)
      assert {%{author_cursor: 1}, :repaint} = Keymap.handle(key(:down), s)

      s1 = author_state(%{author_cursor: 1})
      assert {%{author_cursor: 1}, :repaint} = Keymap.handle(char("j"), s1)
      assert {%{author_cursor: 1}, :repaint} = Keymap.handle(key(:down), s1)

      assert {%{author_cursor: 0}, :repaint} = Keymap.handle(char("k"), author_state(%{author_cursor: 0}))
      assert {%{author_cursor: 0}, :repaint} = Keymap.handle(key(:up), author_state(%{author_cursor: 0}))
    end
  end

  describe "creating a workspace — the author face's `n` verb + :new_workspace input (D2.3)" do
    @templates Console.WorkspaceTemplates.names()

    test "n in CONFIG opens :new_workspace input armed with the FIRST template" do
      s = state(%{drawer: :config})
      assert {%{input: %{kind: :new_workspace, buffer: "", template: t}}, :repaint} = Keymap.handle(char("n"), s)
      assert t == List.first(@templates)
    end

    test "n with the drawer shut still opens :new_thread — unaffected" do
      s = state()
      assert {%{input: %{kind: :new_thread, buffer: ""}}, :repaint} = Keymap.handle(char("n"), s)
    end

    test "h/l cycle input.template through WorkspaceTemplates.names/0, wrapping both ways" do
      first = List.first(@templates)
      last = List.last(@templates)
      s = state(%{input: %{kind: :new_workspace, buffer: "", cursor: 0, template: first}})

      # l steps forward through every template, wrapping back to the first.
      {s1, :repaint} = Keymap.handle(char("l"), s)
      assert s1.input.template != first

      wrapped =
        Enum.reduce(1..length(@templates), s, fn _, acc ->
          {next, :repaint} = Keymap.handle(char("l"), acc)
          next
        end)

      assert wrapped.input.template == first

      # h steps backward, wrapping to the last.
      assert {%{input: %{template: ^last}}, :repaint} = Keymap.handle(char("h"), s)
    end

    test "printable keys still accumulate into buffer (kind-agnostic reuse of the input machinery)" do
      s = state(%{input: %{kind: :new_workspace, buffer: "Fic", cursor: 3, template: List.first(@templates)}})
      assert {%{input: %{buffer: "Ficc"}}, :repaint} = Keymap.handle(char("c"), s)
    end

    test "Enter on a non-empty buffer emits {:register_workspace, template, name} and leaves input mode" do
      s = state(%{input: %{kind: :new_workspace, buffer: "Ficciones2", cursor: 10, template: :code}})
      assert {%{input: nil}, {:register_workspace, :code, "Ficciones2"}} = Keymap.handle(key(:enter), s)
    end

    test "Enter on a blank buffer no-ops — no register, same precedent as :new_thread/:compose" do
      s = state(%{input: %{kind: :new_workspace, buffer: "", cursor: 0, template: :code}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:enter), s)
    end

    test "Esc cancels the create flow, registering nothing" do
      s = state(%{input: %{kind: :new_workspace, buffer: "half typed", cursor: 10, template: :code}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:escape), s)
    end
  end

  describe "deleting a workspace — the author face's `d` verb, two-key confirm (D2.5)" do
    defp author_state2(overrides),
      do: state(Map.merge(%{drawer: :config, live_workspaces: @two_author_workspaces}, overrides))

    test "d on the cursor workspace arms the confirm: {:arm_delete, id, name}" do
      s = author_state2(%{author_cursor: 1})
      assert {^s, {:arm_delete, 22, "Freedonia"}} = Keymap.handle(char("d"), s)
    end

    test "a second d while armed on the SAME id confirms: {:remove_workspace, id}, and clears the arm" do
      s = author_state2(%{author_cursor: 1, pending_delete: 22})
      assert {%{pending_delete: nil}, {:remove_workspace, 22}} = Keymap.handle(char("d"), s)
    end

    test "any other key while armed cancels — clears pending_delete, no remove effect" do
      s = author_state2(%{author_cursor: 1, pending_delete: 22})
      assert {%{pending_delete: nil}, :repaint} = Keymap.handle(char("j"), s)
      assert {%{pending_delete: nil}, :repaint} = Keymap.handle(key(:escape), author_state2(%{pending_delete: 22}))
    end
  end

  describe "editing a workspace — `e` opens the field editor, h/l cycle type/scope rings (D2.4 Chunk 2a)" do
    defp editor_state(overrides),
      do: state(Map.merge(%{drawer: :config, live_workspaces: @two_author_workspaces}, overrides))

    test "e on the author cursor workspace opens author_edit at field 0, sub 0" do
      s = editor_state(%{author_cursor: 1})
      assert {%{author_edit: %{id: 22, field: 0, sub: 0, mode: :field}}, :repaint} = Keymap.handle(char("e"), s)
    end

    test "e on an empty workspace list is a no-op" do
      s = editor_state(%{live_workspaces: [], author_cursor: 0})
      assert {^s, :none} = Keymap.handle(char("e"), s)
    end

    test "e while already editing is a no-op — doesn't re-arm onto a different cursor workspace" do
      s = editor_state(%{author_cursor: 0, author_edit: %{id: 22, field: 1, sub: 0, mode: :field}})
      assert {^s, :none} = Keymap.handle(char("e"), s)
    end

    test "j/k move the field cursor 0..3, clamped, no wrap" do
      s = editor_state(%{author_edit: %{id: 22, field: 0, sub: 0, mode: :field}})
      assert {%{author_edit: %{field: 1}}, :repaint} = Keymap.handle(char("j"), s)
      assert {%{author_edit: %{field: 1}}, :repaint} = Keymap.handle(key(:down), s)

      top = editor_state(%{author_edit: %{id: 22, field: 3, sub: 0, mode: :field}})
      assert {%{author_edit: %{field: 3}}, :repaint} = Keymap.handle(char("j"), top)

      bottom = editor_state(%{author_edit: %{id: 22, field: 0, sub: 0, mode: :field}})
      assert {%{author_edit: %{field: 0}}, :repaint} = Keymap.handle(char("k"), bottom)
      assert {%{author_edit: %{field: 0}}, :repaint} = Keymap.handle(key(:up), bottom)
    end

    test "h/l on field 0 (type) emits {:edit_workspace, id, %{type: next}}, cycling the ring, wrapping" do
      workspaces = [%{id: 22, name: "Freedonia", type: "code", scope: "machine", repos: [], bench: []}]
      s = editor_state(%{live_workspaces: workspaces, author_edit: %{id: 22, field: 0, sub: 0, mode: :field}})

      assert {_s, {:edit_workspace, 22, %{type: "life"}}} = Keymap.handle(char("l"), s)
      assert {_s, {:edit_workspace, 22, %{type: "blank"}}} = Keymap.handle(char("h"), s)

      blank = %{s | live_workspaces: [%{Enum.at(workspaces, 0) | type: "blank"}]}
      assert {_s, {:edit_workspace, 22, %{type: "code"}}} = Keymap.handle(char("l"), blank)
    end

    test "h/l on field 1 (scope) emits {:edit_workspace, id, %{scope: next}}" do
      # A 2-element ring: from "project" (index 0) BOTH directions land on "machine" (index 1) —
      # only a 3+ element ring (type) shows h/l diverge, asserted above.
      workspaces = [%{id: 22, name: "Freedonia", type: "code", scope: "project", repos: [], bench: []}]
      s = editor_state(%{live_workspaces: workspaces, author_edit: %{id: 22, field: 1, sub: 0, mode: :field}})

      assert {_s, {:edit_workspace, 22, %{scope: "machine"}}} = Keymap.handle(char("l"), s)
      assert {_s, {:edit_workspace, 22, %{scope: "machine"}}} = Keymap.handle(char("h"), s)

      machine = %{s | live_workspaces: [%{Enum.at(workspaces, 0) | scope: "machine"}]}
      assert {_s, {:edit_workspace, 22, %{scope: "project"}}} = Keymap.handle(char("l"), machine)
      assert {_s, {:edit_workspace, 22, %{scope: "project"}}} = Keymap.handle(char("h"), machine)
    end

    test "h/l on field 2/3 (repos/roster) are a no-op — those rings don't apply to lists" do
      s = editor_state(%{author_edit: %{id: 22, field: 2, sub: 0, mode: :field}})
      assert {^s, :none} = Keymap.handle(char("h"), s)
      assert {^s, :none} = Keymap.handle(char("l"), s)

      s2 = editor_state(%{author_edit: %{id: 22, field: 3, sub: 0, mode: :field}})
      assert {^s2, :none} = Keymap.handle(char("h"), s2)
      assert {^s2, :none} = Keymap.handle(char("l"), s2)
    end

    test "Esc in field-list mode clears author_edit — back to the list" do
      s = editor_state(%{author_edit: %{id: 22, field: 1, sub: 0, mode: :field}})
      assert {%{author_edit: nil}, :repaint} = Keymap.handle(key(:escape), s)
    end

    test "n/d/a are blocked while author_edit is set — Chunk 1's create/delete/toggle stay list-only" do
      s = editor_state(%{author_edit: %{id: 22, field: 0, sub: 0, mode: :field}})
      assert {^s, :none} = Keymap.handle(char("n"), s)
      assert {^s, :none} = Keymap.handle(char("d"), s)
      assert {^s, :none} = Keymap.handle(char("a"), s)
    end

    test "Chunk 1 create/delete/toggle are untouched when author_edit is nil (list view)" do
      s = editor_state(%{author_cursor: 1, author_edit: nil})
      assert {_s, {:arm_delete, 22, "Freedonia"}} = Keymap.handle(char("d"), s)
      # `a` has no list verb in CONFIG (the face toggle died with Orbis) — a no-op, not a habit verb
      assert {^s, :none} = Keymap.handle(char("a"), s)
    end
  end

  describe "editing a workspace's repos — the field 2 sub-list, add/remove (D2.4 Chunk 2b; rows since UX slice 5)" do
    @workspace_with_repos %{
      id: 22,
      name: "Freedonia",
      type: "code",
      scope: "machine",
      repos: [%{id: 7, path: "a"}, %{id: 8, path: "b"}],
      bench: []
    }

    defp repos_state(overrides),
      do: state(Map.merge(%{drawer: :config, live_workspaces: [@workspace_with_repos]}, overrides))

    test "Enter on field 2 drops into the sub-list: mode: :sub, sub: 0" do
      s = repos_state(%{author_edit: %{id: 22, field: 2, sub: 0, mode: :field}})
      assert {%{author_edit: %{mode: :sub, sub: 0, field: 2}}, :repaint} = Keymap.handle(key(:enter), s)
    end

    test "Enter on field 0/1 (rings) stays in field-list mode — nothing to drop into" do
      s = repos_state(%{author_edit: %{id: 22, field: 0, sub: 0, mode: :field}})
      assert {^s, :none} = Keymap.handle(key(:enter), s)
    end

    test "j/k move sub, clamped to the repo-row count — no wrap" do
      s = repos_state(%{author_edit: %{id: 22, field: 2, sub: 0, mode: :sub}})
      assert {%{author_edit: %{sub: 1}}, :repaint} = Keymap.handle(char("j"), s)

      top = repos_state(%{author_edit: %{id: 22, field: 2, sub: 1, mode: :sub}})
      assert {%{author_edit: %{sub: 1}}, :repaint} = Keymap.handle(char("j"), top)

      bottom = repos_state(%{author_edit: %{id: 22, field: 2, sub: 0, mode: :sub}})
      assert {%{author_edit: %{sub: 0}}, :repaint} = Keymap.handle(char("k"), bottom)
    end

    test "a opens a :new_path input buffer for the edited workspace" do
      s = repos_state(%{author_edit: %{id: 22, field: 2, sub: 0, mode: :sub}})

      assert {%{input: %{kind: :new_path, buffer: "", cursor: 0, workspace_id: 22}}, :repaint} =
               Keymap.handle(char("a"), s)
    end

    test "printable keys accumulate into the :new_path buffer (kind-agnostic reuse)" do
      s = state(%{input: %{kind: :new_path, buffer: "mo", cursor: 2, workspace_id: 22}})
      assert {%{input: %{buffer: "mod"}}, :repaint} = Keymap.handle(char("d"), s)
    end

    test "Enter on a non-empty :new_path buffer emits {:add_repo, id, buffer} — a ROW, not a list overwrite" do
      s =
        state(%{
          drawer: :config,
          live_workspaces: [@workspace_with_repos],
          input: %{kind: :new_path, buffer: "c", cursor: 1, workspace_id: 22}
        })

      assert {%{input: nil}, {:add_repo, 22, "c"}} = Keymap.handle(key(:enter), s)
    end

    test "Enter on a blank :new_path buffer no-ops — same cancel-not-create precedent" do
      s = state(%{input: %{kind: :new_path, buffer: "", cursor: 0, workspace_id: 22}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:enter), s)
    end

    test "Esc cancels the :new_path buffer" do
      s = state(%{input: %{kind: :new_path, buffer: "half", cursor: 4, workspace_id: 22}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:escape), s)
    end

    test "x or d removes the sub-selected repo BY ROW ID, not by index" do
      s = repos_state(%{author_edit: %{id: 22, field: 2, sub: 1, mode: :sub}})
      assert {^s, {:remove_repo, 22, 8}} = Keymap.handle(char("x"), s)
      assert {^s, {:remove_repo, 22, 8}} = Keymap.handle(char("d"), s)
    end

    test "x or d on a vanished row is a no-op, never a delete aimed at nothing" do
      s = repos_state(%{author_edit: %{id: 22, field: 2, sub: 9, mode: :sub}})
      assert {^s, :none} = Keymap.handle(char("x"), s)
    end

    test "Esc in sub-list mode steps back to field-list mode, field unchanged" do
      s = repos_state(%{author_edit: %{id: 22, field: 2, sub: 1, mode: :sub}})
      assert {%{author_edit: %{mode: :field, field: 2}}, :repaint} = Keymap.handle(key(:escape), s)
    end
  end

  describe "editing a workspace's bench — the field 3 sub-list, seat/unseat (D2.4 Chunk 2c; rows since UX slice 5)" do
    @archetypes Map.keys(Server.Profiles.archetypes())
    @workspace_with_roster %{
      id: 22,
      name: "Freedonia",
      type: "code",
      scope: "machine",
      repos: [],
      bench: [
        %Server.Coworker{id: 7, agent_id: 70, archetype: "surveyor", name: "tertius"},
        %Server.Coworker{id: 8, agent_id: 80, archetype: "builder", name: "hronir"}
      ]
    }

    defp roster_state(overrides),
      do: state(Map.merge(%{drawer: :config, live_workspaces: [@workspace_with_roster]}, overrides))

    test "Enter on field 3 drops into the sub-list: mode: :sub, sub: 0" do
      s = roster_state(%{author_edit: %{id: 22, field: 3, sub: 0, mode: :field}})
      assert {%{author_edit: %{mode: :sub, sub: 0, field: 3}}, :repaint} = Keymap.handle(key(:enter), s)
    end

    test "j/k move sub, clamped to the roster length — no wrap" do
      s = roster_state(%{author_edit: %{id: 22, field: 3, sub: 0, mode: :sub}})
      assert {%{author_edit: %{sub: 1}}, :repaint} = Keymap.handle(char("j"), s)

      bottom = roster_state(%{author_edit: %{id: 22, field: 3, sub: 1, mode: :sub}})
      assert {%{author_edit: %{sub: 1}}, :repaint} = Keymap.handle(char("j"), bottom)
    end

    test "a opens a :new_roster input armed with the FIRST archetype" do
      s = roster_state(%{author_edit: %{id: 22, field: 3, sub: 0, mode: :sub}})

      assert {%{input: %{kind: :new_roster, buffer: "", cursor: 0, workspace_id: 22, archetype: arch}}, :repaint} =
               Keymap.handle(char("a"), s)

      assert arch == List.first(@archetypes)
    end

    test "h/l cycle input.archetype through Profiles.archetypes/0's keys, wrapping both ways" do
      first = List.first(@archetypes)
      last = List.last(@archetypes)
      s = state(%{input: %{kind: :new_roster, buffer: "", cursor: 0, workspace_id: 22, archetype: first}})

      {s1, :repaint} = Keymap.handle(char("l"), s)
      assert s1.input.archetype != first

      wrapped =
        Enum.reduce(1..length(@archetypes), s, fn _, acc ->
          {next, :repaint} = Keymap.handle(char("l"), acc)
          next
        end)

      assert wrapped.input.archetype == first
      assert {%{input: %{archetype: ^last}}, :repaint} = Keymap.handle(char("h"), s)
    end

    test "printable keys accumulate into the :new_roster buffer (kind-agnostic reuse)" do
      s = state(%{input: %{kind: :new_roster, buffer: "am", cursor: 2, workspace_id: 22, archetype: :assistant}})
      assert {%{input: %{buffer: "amy"}}, :repaint} = Keymap.handle(char("y"), s)
    end

    test "Enter on a non-empty :new_roster buffer SEATS a coworker — a row, not a list overwrite" do
      s =
        state(%{
          drawer: :config,
          live_workspaces: [@workspace_with_roster],
          input: %{kind: :new_roster, buffer: "amy", cursor: 3, workspace_id: 22, archetype: :assistant}
        })

      assert {%{input: nil}, {:seat, 22, %{name: "amy", archetype: "assistant"}}} = Keymap.handle(key(:enter), s)
    end

    test "Enter on a blank :new_roster buffer no-ops — same cancel-not-create precedent" do
      s = state(%{input: %{kind: :new_roster, buffer: "", cursor: 0, workspace_id: 22, archetype: :assistant}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:enter), s)
    end

    test "Esc cancels the :new_roster buffer" do
      s = state(%{input: %{kind: :new_roster, buffer: "half", cursor: 4, workspace_id: 22, archetype: :assistant}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:escape), s)
    end

    test "x or d UNSEATS the sub-selected coworker BY ROW ID, not by index" do
      s = roster_state(%{author_edit: %{id: 22, field: 3, sub: 1, mode: :sub}})

      assert {^s, {:unseat, 22, 8}} = Keymap.handle(char("x"), s)
      assert {^s, {:unseat, 22, 8}} = Keymap.handle(char("d"), s)
    end

    test "x or d on a vanished seat is a no-op, never an unseat aimed at nothing" do
      s = roster_state(%{author_edit: %{id: 22, field: 3, sub: 9, mode: :sub}})
      assert {^s, :none} = Keymap.handle(char("x"), s)
    end

    test "Esc in sub-list mode steps back to field-list mode, field unchanged" do
      s = roster_state(%{author_edit: %{id: 22, field: 3, sub: 1, mode: :sub}})
      assert {%{author_edit: %{mode: :field, field: 3}}, :repaint} = Keymap.handle(key(:escape), s)
    end
  end

  describe "the roster sub-list's model/yolo knob (D2.4 Chunk 2b, absorbs Settings)" do
    @workspace_with_roster %{
      id: 22,
      name: "Freedonia",
      type: "code",
      scope: "machine",
      repos: [],
      bench: [
        %Server.Coworker{id: 7, agent_id: 70, archetype: "surveyor", name: "tertius"},
        %Server.Coworker{id: 8, agent_id: 80, archetype: "builder", name: "hronir"}
      ]
    }

    defp roster_knob_state(overrides),
      do: state(Map.merge(%{drawer: :config, live_workspaces: [@workspace_with_roster]}, overrides))

    test "Tab flips the armed knob :model <-> :yolo" do
      s = roster_knob_state(%{author_edit: %{id: 22, field: 3, sub: 0, mode: :sub, knob: :model}})
      assert {%{author_edit: %{knob: :yolo}}, :repaint} = Keymap.handle(key(:tab), s)

      s2 = roster_knob_state(%{author_edit: %{id: 22, field: 3, sub: 0, mode: :sub, knob: :yolo}})
      assert {%{author_edit: %{knob: :model}}, :repaint} = Keymap.handle(key(:tab), s2)
    end

    test "Tab defaults the knob to :model when the state predates the field" do
      s = roster_knob_state(%{author_edit: %{id: 22, field: 3, sub: 0, mode: :sub}})
      assert {%{author_edit: %{knob: :yolo}}, :repaint} = Keymap.handle(key(:tab), s)
    end

    test "Tab in field-list mode is untouched by the knob clause (author_edit unchanged)" do
      s = roster_knob_state(%{author_edit: %{id: 22, field: 3, sub: 0, mode: :field}})
      {next, :none} = Keymap.handle(key(:tab), s)
      assert next.author_edit == s.author_edit
    end

    # (Tab is unbound in the drawer — it used to fall through to the space switch — so the effect
    # is :none; the assertion is about the edit state.)
    test "Tab in the repos sub-list (field 2) is untouched by the knob clause (author_edit unchanged)" do
      s = roster_knob_state(%{author_edit: %{id: 22, field: 2, sub: 0, mode: :sub}})
      {next, :none} = Keymap.handle(key(:tab), s)
      assert next.author_edit == s.author_edit
    end

    test "Enter applies the armed :model knob to the sub-selected coworker" do
      s = roster_knob_state(%{author_edit: %{id: 22, field: 3, sub: 1, mode: :sub, knob: :model}})
      assert {^s, {:coworker_knob, "hronir", :model}} = Keymap.handle(key(:enter), s)
    end

    test "Space (both wire forms) applies the armed :yolo knob to the sub-selected coworker" do
      s = roster_knob_state(%{author_edit: %{id: 22, field: 3, sub: 0, mode: :sub, knob: :yolo}})
      assert {^s, {:coworker_knob, "tertius", :yolo}} = Keymap.handle(char(" "), s)
      assert {^s, {:coworker_knob, "tertius", :yolo}} = Keymap.handle(key(:space), s)
    end

    test "Enter on an empty roster is a no-op, never crashes" do
      s =
        roster_knob_state(%{
          live_workspaces: [%{@workspace_with_roster | bench: []}],
          author_edit: %{id: 22, field: 3, sub: 0, mode: :sub, knob: :model}
        })

      assert {^s, :none} = Keymap.handle(key(:enter), s)
    end
  end

  describe "the live terminal owns the keys by default" do
    test "a printable key forwards, not acted on locally" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: "q"}}} = Keymap.handle(char("q"), s)
    end

    test "arrows forward while a terminal is live (the app scrolls/moves), not a thread move" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :up}}} = Keymap.handle(key(:up), s)
    end

    test "Tab forwards while a terminal is live (shell completion), not a space switch" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :tab}}} = Keymap.handle(key(:tab), s)
    end

    test "Enter forwards while a terminal is live, not an enter-or-spawn" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :enter}}} = Keymap.handle(key(:enter), s)
    end

    test "bare q forwards to the terminal (you might be typing q), not a quit" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: "q"}}} = Keymap.handle(char("q"), s)
    end
  end

  # The arm-the-next-key leader is RETIRED (UX slice 2). It had been unreachable: every live
  # keypress enters through handle_tlon (Space.workspace?/1 is is_integer/1, satisfied even by the
  # server-down sentinel 0, and the cockpit always carries a Focus), so the prefix clauses were
  # reached only by tests like the ones this block replaces. Its verbs are in Console.Verbs, each
  # with a sentence, behind ^⇧P.
  describe "the retired Ctrl+Space leader" do
    test "Ctrl+Space arms nothing — no prefix state is left behind" do
      {next, _effect} = Keymap.handle(key(:space, ctrl: true), state(%{center_live?: true}))
      refute Map.has_key?(next, :leader_pending?)
    end

    test "with a live terminal it forwards as an ordinary key" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :space, ctrl: true}}} = Keymap.handle(key(:space, ctrl: true), s)
    end

    test "with no live terminal it is simply unbound" do
      s = state(%{center_live?: false})
      assert {^s, :none} = Keymap.handle(key(:space, ctrl: true), s)
    end

    test "the verbs it used to reach are still bare in a nav-default state" do
      s = state(%{center_live?: false})

      assert {_quit, :quit} = Keymap.handle(char("q"), s)
      assert {%{input: %{kind: :new_thread}}, :repaint} = Keymap.handle(char("n"), s)
      assert {%{focused_id: 3}, :repaint} = Keymap.handle(char("j"), s)
    end

    test "and each of them is in the palette, so retiring the prefix hid nothing" do
      labels = Enum.map(Console.Verbs.all(), & &1.label)
      assert "quit" in labels
      assert "new thread" in labels
      assert "term / nav" in labels
    end
  end

  describe "creating — the `n` verb" do
    test "n in a WORKSPACE focuses the new-thread input" do
      s = state(%{active_key: 1})
      assert {%{input: %{kind: :new_thread, buffer: ""}}, :repaint} = Keymap.handle(char("n"), s)
    end

    test "n on Orbis' survey face opens the title input (empty buffer) and repaints" do
      assert {%{input: %{kind: :new_thread, buffer: ""}}, :repaint} = Keymap.handle(char("n"), state())
    end

    test "n forwards to the terminal when one is live (use ^B n to open a new thread)" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: "n"}}} = Keymap.handle(char("n"), s)
    end

    test "printable keys accumulate into the buffer, not acted on locally" do
      s = state(%{input: %{kind: :new_thread, buffer: "fab"}})
      assert {%{input: %{buffer: "fabl"}}, :repaint} = Keymap.handle(char("l"), s)
      s2 = state(%{input: %{kind: :new_thread, buffer: "fabl"}})
      assert {%{input: %{buffer: "fable"}}, :repaint} = Keymap.handle(char("e"), s2)
    end

    test "keys that are bindings in normal mode are captured as text while typing (q does not quit)" do
      s = state(%{input: %{kind: :new_thread, buffer: "re"}})
      assert {%{input: %{buffer: "req"}}, :repaint} = Keymap.handle(char("q"), s)
    end

    test "backspace deletes the last character" do
      s = state(%{input: %{kind: :new_thread, buffer: "fable"}})
      assert {%{input: %{buffer: "fabl"}}, :repaint} = Keymap.handle(key(:backspace), s)
    end

    test "Enter on a non-empty buffer submits {:create_thread, title, project} and leaves input mode" do
      s = state(%{input: %{kind: :new_thread, buffer: "fable review"}})
      assert {%{input: nil}, {:create_thread, "fable review", nil}} = Keymap.handle(key(:enter), s)
    end

    test "Enter on an empty buffer cancels (never creates a blank thread)" do
      s = state(%{input: %{kind: :new_thread, buffer: ""}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:enter), s)
    end

    test "Esc cancels input mode, creating nothing" do
      s = state(%{input: %{kind: :new_thread, buffer: "half typed"}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:escape), s)
    end

    test "Tab in the new-thread box cycles the workspace's projects from the default, wrapping" do
      choice = %{projects: [%{id: 1, name: "ficciones"}, %{id: 2, name: "excessibility"}], default: 1}
      s = state(%{input: %{kind: :new_thread, buffer: "fix it"}, project_choice: choice})
      {s, :repaint} = Keymap.handle(key(:tab), s)
      assert s.input.project_id == 2
      {s, :repaint} = Keymap.handle(key(:tab), s)
      assert s.input.project_id == 1
      assert {%{input: nil}, {:create_thread, "fix it", 1}} = Keymap.handle(key(:enter), s)
    end

    test "Tab with no projects in the workspace changes nothing" do
      s = state(%{input: %{kind: :new_thread, buffer: "x"}, project_choice: %{projects: [], default: nil}})
      assert {^s, :none} = Keymap.handle(key(:tab), s)
    end
  end

  describe "the tertius command line — the `:` verb + orchestrate mode (Slice 1)" do
    test ": (bare, nav context) opens the orchestrate line (empty buffer) and repaints" do
      assert {%{input: %{kind: :orchestrate, buffer: ""}}, :repaint} = Keymap.handle(char(":"), state())
    end

    test ": forwards to the terminal when one is live — the centre owns the key" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: ":"}}} = Keymap.handle(char(":"), s)
    end

    test "printable keys accumulate into the orchestrate buffer" do
      s = state(%{input: %{kind: :orchestrate, buffer: "file "}})
      assert {%{input: %{buffer: "file a"}}, :repaint} = Keymap.handle(char("a"), s)
    end

    test "Enter on a non-empty buffer submits {:orchestrate, text} and leaves input mode" do
      s = state(%{input: %{kind: :orchestrate, buffer: "file a ticket auth is broken"}})
      assert {%{input: nil}, {:orchestrate, "file a ticket auth is broken"}} = Keymap.handle(key(:enter), s)
    end

    test "Enter on an empty buffer cancels (dispatches nothing)" do
      s = state(%{input: %{kind: :orchestrate, buffer: ""}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:enter), s)
    end

    test "Esc cancels the orchestrate line" do
      s = state(%{input: %{kind: :orchestrate, buffer: "half typed"}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:escape), s)
    end

    test "z forwards to the terminal when one is live — the centre owns the key" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: "z"}}} = Keymap.handle(char("z"), s)
    end
  end

  describe "the tertius y/n confirm gate — a consequential verb is armed, waiting on y/n (Slice 3.5)" do
    # The arm is `%{action, ctx, summary}` — the routed action to fire, the dispatch ctx, and the
    # human summary. `y` fires it (`:confirm_orchestrate`, apply_effect reads the arm); anything else
    # backs out. This gate precedes the space routing — a consequential intent can be armed from
    # either, and every key belongs to the gate until it's answered.
    @arm %{action: {:open, "build", "a cache"}, ctx: %{}, summary: "open [build] “a cache”"}
    defp armed(over \\ %{}), do: state(Map.merge(%{pending_confirm: @arm}, over))

    test "y while armed fires {:confirm_orchestrate, arm} (payload rides the effect) and clears the arm" do
      assert {%{pending_confirm: nil}, {:confirm_orchestrate, @arm}} = Keymap.handle(char("y"), armed())
    end

    test "n while armed cancels — clears the arm, no fire" do
      assert {%{pending_confirm: nil}, :repaint} = Keymap.handle(char("n"), armed())
    end

    test "any other key while armed cancels (Esc, or a stray nav key)" do
      assert {%{pending_confirm: nil}, :repaint} = Keymap.handle(key(:escape), armed())
      assert {%{pending_confirm: nil}, :repaint} = Keymap.handle(char("j"), armed())
    end

    test "the gate precedes a live terminal — an armed confirm captures y even with center_live?" do
      assert {%{pending_confirm: nil}, {:confirm_orchestrate, @arm}} =
               Keymap.handle(char("y"), armed(%{center_live?: true}))
    end

    test "not armed (nil): y is not the confirm gate — it falls through to ordinary routing" do
      refute match?({_s, {:confirm_orchestrate, _}}, Keymap.handle(char("y"), state()))
    end
  end

  describe "thread stack keyboard nav in a workspace (handle_tlon, center_view :chat)" do
    test "j/k move the stack cursor instead of forwarding to a (hidden) terminal" do
      assert {%{focused_id: 3}, :repaint} = Keymap.handle(char("j"), stack_ctx())
      assert {%{focused_id: 1}, :repaint} = Keymap.handle(char("k"), stack_ctx())
    end

    test "↑/↓ also move the cursor" do
      assert {%{focused_id: 3}, :repaint} = Keymap.handle(key(:down), stack_ctx())
      assert {%{focused_id: 1}, :repaint} = Keymap.handle(key(:up), stack_ctx())
    end

    test "g/G jump to top/bottom" do
      assert {%{focused_id: 1}, :repaint} = Keymap.handle(char("g"), stack_ctx())
      assert {%{focused_id: 3}, :repaint} = Keymap.handle(char("G"), stack_ctx())
    end

    test "Enter opens the focused thread's conversation (two-step center)" do
      assert {_s, :open_focused_thread} = Keymap.handle(key(:enter), stack_ctx())
    end

    test "in conversation mode the reply box owns typing: j/k type, PgUp/PgDn scroll, Esc backs out" do
      # A thread is open ⇒ the reply input is present, so the modal owns keys (j/k type into it).
      s = stack_ctx(%{opened_thread: 2, input: %{kind: :reply, thread_id: 2, buffer: "", cursor: 0}})
      assert {%{input: %{buffer: "j"}}, :repaint} = Keymap.handle(char("j"), s)
      assert {%{input: %{buffer: "k"}}, :repaint} = Keymap.handle(char("k"), s)
      # Backlog scroll rides PgUp/PgDn (+ wheel, tested via the cockpit) — j/k are the buffer's now.
      assert {_s, {:scroll_conversation, -3}} = Keymap.handle(key(:page_up), s)
      assert {_s, {:scroll_conversation, 3}} = Keymap.handle(key(:page_down), s)
      # Esc steps back to the list AND clears the reply so no draft leaks into the next thread.
      assert {%{input: nil}, :close_thread_view} = Keymap.handle(key(:escape), s)
    end

    test ": focuses the tertius line from the stack" do
      assert {%{input: %{kind: :orchestrate}}, :repaint} = Keymap.handle(char(":"), stack_ctx())
    end

    test "with a live terminal center (center_view :terminal), keys still forward" do
      s = stack_ctx(%{center_view: :terminal, center_live?: true})
      assert {^s, {:forward, %{key: :char, char: "j"}}} = Keymap.handle(char("j"), s)
    end

    # The chat view has NO live terminal in the center (the cockpit derives center_live? false there),
    # so an unlisted key must be a no-op — never forwarded to the hidden machine PTY underneath.
    test "in the chat view an unlisted key is :none, not a forward to the hidden PTY" do
      s = stack_ctx()
      refute s.center_live?

      for k <- [char("v"), char("y"), char("q"), key(:tab), key(:f5)] do
        assert {^s, :none} = Keymap.handle(k, s), "#{inspect(k)} leaked"
      end
    end
  end

  describe "the per-thread reply input (:reply — the persistent thread-scope box)" do
    defp reply_ctx(over \\ %{}),
      do: stack_ctx(Map.merge(%{opened_thread: 2, input: %{kind: :reply, thread_id: 2, buffer: "", cursor: 0}}, over))

    test "typing inserts into the reply buffer (the box is always focused)" do
      assert {%{input: %{kind: :reply, buffer: "hi"}}, :repaint} =
               Keymap.handle(char("i"), reply_ctx(%{input: %{kind: :reply, thread_id: 2, buffer: "h", cursor: 1}}))
    end

    test "Enter on a non-empty buffer posts to the thread AND keeps the box focused (buffer cleared)" do
      s = reply_ctx(%{input: %{kind: :reply, thread_id: 2, buffer: "ship it", cursor: 7}})

      assert {%{input: %{kind: :reply, thread_id: 2, buffer: "", cursor: 0}}, {:post_message, 2, "ship it"}} =
               Keymap.handle(key(:enter), s)
    end

    test "Enter on an empty buffer is a no-op — never posts blank, never closes the box" do
      s = reply_ctx()
      assert {^s, :repaint} = Keymap.handle(key(:enter), s)
    end

    test "Shift+Enter inserts a newline (a multiline reply) instead of sending" do
      s = reply_ctx(%{input: %{kind: :reply, thread_id: 2, buffer: "one", cursor: 3}})
      assert {%{input: %{kind: :reply, buffer: "one\n"}}, :repaint} = Keymap.handle(key(:enter, shift: true), s)
    end

    test "Esc sends nothing, backs out to the list, and clears the draft" do
      s = reply_ctx(%{input: %{kind: :reply, thread_id: 2, buffer: "half typed", cursor: 10}})
      assert {%{input: nil}, :close_thread_view} = Keymap.handle(key(:escape), s)
    end
  end

  describe "composing a message — the `c` verb + composer mode" do
    test "c (bare, nav context) opens a composer on the focused thread" do
      assert {%{input: %{kind: :compose, thread_id: 2, buffer: ""}}, :repaint} =
               Keymap.handle(char("c"), state())
    end

    test "c with no focused thread is a no-op" do
      s = state(%{focused_id: nil, threads: []})
      assert {^s, :none} = Keymap.handle(char("c"), s)
    end

    test "in Tlön, c composes onto the MACHINE thread, not a stale project focused_id" do
      # The cockpit derives composer_thread_id from the machine thread in Tlön (a per-keypress
      # injection), so a focused_id carried over from Orbis must not receive the post.
      s = state(%{active_key: 0, focused_id: 2, composer_thread_id: 99})
      assert {%{input: %{kind: :compose, thread_id: 99, buffer: ""}}, :repaint} = Keymap.handle(char("c"), s)
    end

    test "c forwards to the terminal when one is live (use ^B c to open a composer)" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: "c"}}} = Keymap.handle(char("c"), s)
    end

    test "Alt+c opens a composer even when a terminal is live — the chord is the door now" do
      s = state(%{center_live?: true, focused_id: 2})

      assert {%{input: %{kind: :compose, thread_id: 2, buffer: ""}}, :repaint} =
               Keymap.handle(char("c", alt: true), s)
    end

    test "printable keys accumulate into the buffer, not acted on locally" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "sh"}})
      assert {%{input: %{buffer: "shi"}}, :repaint} = Keymap.handle(char("i"), s)
      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "shi"}})
      assert {%{input: %{buffer: "ship"}}, :repaint} = Keymap.handle(char("p"), s2)
    end

    test "binding letters are captured as text while composing (q does not quit)" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "the "}})
      assert {%{input: %{buffer: "the q"}}, :repaint} = Keymap.handle(char("q"), s)
    end

    test "a :space key event inserts a space (Kitty CSI-u Shift+Space has no char)" do
      # Under [>1u disambiguation Shift+Space arrives as %{key: :space, shift: true} — no `char` —
      # so it must not fall to the drop-everything catch-all. Plain space (a :char " ") still works.
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "two"}})
      assert {%{input: %{buffer: "two "}}, :repaint} = Keymap.handle(key(:space, shift: true), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "two"}})
      assert {%{input: %{buffer: "two "}}, :repaint} = Keymap.handle(key(:space), s2)
    end

    test "backspace deletes the last character" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "ship"}})
      assert {%{input: %{buffer: "shi"}}, :repaint} = Keymap.handle(key(:backspace), s)
    end

    test "Shift+Enter inserts a newline instead of submitting" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one"}})
      assert {%{input: %{buffer: "one\n"}}, :repaint} = Keymap.handle(key(:enter, shift: true), s)

      # a printable key after the newline lands on the second line
      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\n"}})
      assert {%{input: %{buffer: "one\nt"}}, :repaint} = Keymap.handle(char("t"), s2)
    end

    test "Shift+Enter in the new-thread input inserts a newline (it's a multi-line message now)" do
      s = state(%{input: %{kind: :new_thread, buffer: "fable"}})
      assert {%{input: %{buffer: "fable\n", kind: :new_thread}}, :repaint} = Keymap.handle(key(:enter, shift: true), s)
    end

    test "plain Enter in the new-thread input submits (creates the thread)" do
      s = state(%{input: %{kind: :new_thread, buffer: "fable"}})
      assert {%{input: nil}, {:create_thread, "fable", nil}} = Keymap.handle(key(:enter), s)
    end

    test "Enter on a non-empty buffer posts {:post_message, thread_id, body} and leaves input mode" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "shipped"}})
      assert {%{input: nil}, {:post_message, 2, "shipped"}} = Keymap.handle(key(:enter), s)
    end

    test "Enter on a multiline buffer posts the whole body (newlines intact)" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo"}})
      assert {%{input: nil}, {:post_message, 2, "one\ntwo"}} = Keymap.handle(key(:enter), s)
    end

    test "Enter on an empty buffer cancels (never posts a blank message)" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: ""}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:enter), s)
    end

    # HEALTH demoted to the footer (reshape slice D) — /status in the composer is the full
    # readout: a slash command, never posted as a chat message.
    test "Enter on /status emits {:show_status, thread_id} instead of posting" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "/status"}})
      assert {%{input: nil}, {:show_status, 2}} = Keymap.handle(key(:enter), s)

      # surrounding whitespace still reads as the command
      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "  /status "}})
      assert {%{input: nil}, {:show_status, 2}} = Keymap.handle(key(:enter), s2)
    end

    test "a message merely mentioning /status still posts normally" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "try /status sometime"}})
      assert {%{input: nil}, {:post_message, 2, "try /status sometime"}} = Keymap.handle(key(:enter), s)
    end

    test "Esc cancels the composer, posting nothing" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "half typed"}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:escape), s)
    end

    test "Left/Right move the cursor, and typing inserts there instead of at the end" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "sip", cursor: 1}})
      assert {%{input: %{buffer: "ship", cursor: 2}}, :repaint} = Keymap.handle(char("h"), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "ship", cursor: 2}})
      assert {%{input: %{cursor: 1}}, :repaint} = Keymap.handle(key(:left), s2)

      s3 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "ship", cursor: 1}})
      assert {%{input: %{cursor: 2}}, :repaint} = Keymap.handle(key(:right), s3)
    end

    test "Left/Right clamp at the buffer's edges" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "hi", cursor: 0}})
      assert {%{input: %{cursor: 0}}, :repaint} = Keymap.handle(key(:left), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "hi", cursor: 2}})
      assert {%{input: %{cursor: 2}}, :repaint} = Keymap.handle(key(:right), s2)
    end

    test "backspace deletes BEFORE the cursor, not always the buffer's last character" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "ship", cursor: 2}})
      assert {%{input: %{buffer: "sip", cursor: 1}}, :repaint} = Keymap.handle(key(:backspace), s)
    end

    test "backspace at the start of the buffer is a no-op" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "ship", cursor: 0}})
      assert {%{input: %{buffer: "ship", cursor: 0}}, :repaint} = Keymap.handle(key(:backspace), s)
    end

    test "Home/End jump to the start/end of the CURRENT line, not the whole buffer" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 5}})
      assert {%{input: %{cursor: 4}}, :repaint} = Keymap.handle(key(:home), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 4}})
      assert {%{input: %{cursor: 7}}, :repaint} = Keymap.handle(key(:end), s2)
    end

    test "Up/Down move a line, preserving column where possible" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 6}})
      assert {%{input: %{cursor: 2}}, :repaint} = Keymap.handle(key(:up), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 1}})
      assert {%{input: %{cursor: 5}}, :repaint} = Keymap.handle(key(:down), s2)
    end

    test "Up/Down clamp the column to a shorter target line" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "a\nlong line", cursor: 8}})
      assert {%{input: %{cursor: 1}}, :repaint} = Keymap.handle(key(:up), s)
    end

    test "Up/Down are a no-op at the buffer's top/bottom line" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 1}})
      assert {%{input: %{cursor: 1}}, :repaint} = Keymap.handle(key(:up), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 5}})
      assert {%{input: %{cursor: 5}}, :repaint} = Keymap.handle(key(:down), s2)
    end

    test "Ctrl+P/Ctrl+N alias Up/Down — hosts that swallow arrow keys still get vertical movement" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 6}})
      assert {%{input: %{cursor: 2}}, :repaint} = Keymap.handle(char("p", ctrl: true), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 1}})
      assert {%{input: %{cursor: 5}}, :repaint} = Keymap.handle(char("n", ctrl: true), s2)
    end

    test "typing after moving the cursor with Ctrl+P lands where the cursor moved, not at the end" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 6}})
      {moved, :repaint} = Keymap.handle(char("p", ctrl: true), s)
      assert {%{input: %{buffer: "onXe\ntwo", cursor: 3}}, :repaint} = Keymap.handle(char("X"), moved)
    end

    test "Ctrl+A/Ctrl+E alias Home/End on the current line" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 5}})
      assert {%{input: %{cursor: 4}}, :repaint} = Keymap.handle(char("a", ctrl: true), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 4}})
      assert {%{input: %{cursor: 7}}, :repaint} = Keymap.handle(char("e", ctrl: true), s2)
    end

    test "Ctrl+U kills from the start of the current line to the cursor, leaving other lines intact" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 6}})
      assert {%{input: %{buffer: "one\no", cursor: 4}}, :repaint} = Keymap.handle(char("u", ctrl: true), s)
    end

    test "Ctrl+K kills from the cursor to the end of the current line, cursor unmoved" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 5}})
      assert {%{input: %{buffer: "one\nt", cursor: 5}}, :repaint} = Keymap.handle(char("k", ctrl: true), s)
    end

    test "Ctrl+W kills the word behind the cursor, past trailing whitespace" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "post the update ", cursor: 16}})
      assert {%{input: %{buffer: "post the ", cursor: 9}}, :repaint} = Keymap.handle(char("w", ctrl: true), s)
    end
  end

  describe "the `m` verb — cycle the coworker driver model (the SETTINGS knob)" do
    # The fixture bench is surveyor `tertius` then builder `hronir`, and the centre coworker is the
    # LEAD — the first builder (UX slice 5's one derivation), not merely the first seat.
    test "in a coworker space (Tlön), bare `m` emits the cycle effect for the LEAD's profile" do
      s = state(%{active_key: 0})
      assert {^s, {:cycle_coworker_model, "hronir"}} = Keymap.handle(char("m"), s)
    end

    test "reachable bare when the centre is not a live terminal" do
      s = state(%{active_key: 0, center_live?: false})
      assert {^s, {:cycle_coworker_model, "hronir"}} = Keymap.handle(char("m"), s)
    end

    test "in a space without a coworker (a key no space has), `m` is a no-op" do
      s = state(%{active_key: 999})
      assert {^s, :none} = Keymap.handle(char("m"), s)
    end

    test "a modified m (Ctrl+M / Alt+M) never fires the settings verb" do
      s = state(%{active_key: 0})
      assert {^s, :none} = Keymap.handle(char("m", ctrl: true), s)
      assert {^s, :none} = Keymap.handle(char("m", alt: true), s)
    end

    test "with a live terminal, `m` types into the terminal like any key" do
      s = state(%{active_key: 0, center_live?: true})
      k = char("m")
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end
  end

  describe "unknown keys" do
    test "an unbound key in a nav-default space is a no-op" do
      s = state()
      assert {^s, :none} = Keymap.handle(key(:f5), s)
    end

    test "an unbound key forwards when a terminal is live" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :f5}}} = Keymap.handle(key(:f5), s)
    end
  end

  # Tlön's lazygit focus model (design 2026-08-20): the center is a live tmux client, so Ctrl+Space
  # is a STICKY toggle in/out of it — NOT the arm-next-key leader other spaces use. In the terminal
  # every key forwards to tmux; out of it aleph owns the keys and drives the pure `Console.Tlon.Focus`
  # SM over `tlon_layout`. Both `focus` (persistent) and `tlon_layout` (derived per keypress, like
  # center_live?) are supplied by the cockpit only for this space.
  describe "Tlön focus nav" do
    # A Tlön state: `focus` + the two-column `tlon_layout` it navigates. center_live? is true (the
    # tmux client is always live) but the focus path — not center_live? — decides key routing here.
    defp tlon(focus \\ Focus.new(), overrides \\ %{}) do
      state(
        Map.merge(
          %{
            active_key: 0,
            # counts: :a has 3 items, :b 2, :c 4 — what j/k clamps against.
            center_live?: true,
            focus: focus,
            tlon_layout: %{left: [:a, :b], right: [:c], sections: %{}, counts: %{a: 3, b: 2, c: 4}}
          },
          overrides
        )
      )
    end

    defp nav_focus(overrides \\ %{}), do: struct(Focus.new(), Map.merge(%{in_terminal?: false}, overrides))

    test "Ctrl+Space toggles OUT of the terminal into nav mode — it does not arm the leader" do
      {next, :repaint} = Keymap.handle(ctrl_space(), tlon())
      assert next.focus.in_terminal? == false
    end

    test "Ctrl+Space again toggles back INTO the terminal" do
      {next, :repaint} = Keymap.handle(ctrl_space(), tlon(nav_focus()))
      assert next.focus.in_terminal? == true
    end

    test "in the terminal, every key forwards to tmux (unchanged tmux ownership)" do
      s = tlon()
      k = char("j")
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end

    test "in nav mode, l/h move the focus down/up the current column" do
      {n1, :repaint} = Keymap.handle(char("l"), tlon(nav_focus(%{column: :left, pane: 0})))
      assert n1.focus.pane == 1
      {n2, :repaint} = Keymap.handle(char("h"), n1)
      assert n2.focus.pane == 0
    end

    test "in nav mode, H/L jump between the sidebar columns" do
      {n1, :repaint} = Keymap.handle(char("L"), tlon(nav_focus(%{column: :left})))
      assert n1.focus.column == :right
      {n2, :repaint} = Keymap.handle(char("H"), n1)
      assert n2.focus.column == :left
    end

    test "in nav mode, s cycles the focused pane's sections (C3.4: section-cycle moved off Tab)" do
      s = tlon(nav_focus(%{column: :left, pane: 0}), %{tlon_layout: %{left: [:a, :b], right: [:c], sections: %{a: 2}}})
      {n1, :repaint} = Keymap.handle(char("s"), s)
      assert n1.focus.section == 1
      {n2, :repaint} = Keymap.handle(char("s"), n1)
      assert n2.focus.section == 0
    end

    # Workspaces are the only spaces (UX slice 1, task 5): the ring is the keypress's workspace list.
    test "in nav mode, Tab and Shift+Tab walk the workspace ring, wrapping" do
      s = tlon(nav_focus(), %{active_key: 1, live_workspaces: two_workspaces()})
      assert {%{active_key: 2}, :repaint} = Keymap.handle(key(:tab), s)
      assert {%{active_key: 2}, :repaint} = Keymap.handle(key(:tab, shift: true), s)
      assert {%{active_key: 1}, :repaint} = Keymap.handle(key(:tab), %{s | active_key: 2})
    end

    test "in nav mode, with no workspaces Tab goes nowhere (server down is not a crash)" do
      s = tlon(nav_focus(), %{active_key: 0, live_workspaces: []})
      assert {^s, :none} = Keymap.handle(key(:tab), s)
    end

    # UX slice 1, task 2: the rail advertises `[ ]` — bind it to the space ring Tab already walks,
    # so every key the rail's hints name actually does something.
    test "in nav mode, [ and ] walk the space ring like Shift+Tab / Tab" do
      s = tlon(nav_focus(), %{active_key: 1, live_workspaces: two_workspaces()})
      assert {%{active_key: 2}, :repaint} = Keymap.handle(char("]"), s)
      assert {%{active_key: 2}, :repaint} = Keymap.handle(char("["), s)
    end

    test "in nav mode, j/k move the item cursor within the focused pane, clamped to its count" do
      {n1, :repaint} = Keymap.handle(char("j"), tlon(nav_focus(%{column: :left, pane: 0})))
      assert n1.focus.cursors[:a] == 1
      {n2, :repaint} = Keymap.handle(char("k"), n1)
      assert n2.focus.cursors[:a] == 0
    end

    test "in nav mode, Down/Up alias j/k for the item cursor" do
      {n1, :repaint} = Keymap.handle(key(:down), tlon(nav_focus(%{column: :left, pane: 0})))
      assert n1.focus.cursors[:a] == 1
      {n2, :repaint} = Keymap.handle(key(:up), n1)
      assert n2.focus.cursors[:a] == 0
    end

    test "in nav mode, Enter emits :tlon_enter (the cockpit resolves detail-vs-jump per pane)" do
      assert {_s, :tlon_enter} = Keymap.handle(key(:enter), tlon(nav_focus()))
    end

    test "in nav mode, a/r emit the habit action effect (the cockpit resolves which habit)" do
      assert {_s, {:habit_action, :approve}} = Keymap.handle(char("a"), tlon(nav_focus()))
      assert {_s, {:habit_action, :reject}} = Keymap.handle(char("r"), tlon(nav_focus()))
    end

    test "y in nav emits :yank; y in the terminal forwards" do
      assert {_s, :yank} = Keymap.handle(char("y"), tlon(nav_focus()))

      s = tlon()
      k = char("y")
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end

    test "d in nav emits :tlon_delete_arm; armed d confirms with the arm-time target; any other key cancels" do
      assert {_s, :tlon_delete_arm} = Keymap.handle(char("d"), tlon(nav_focus()))

      target = {:fact, %{id: 7}, "forget fact #7"}
      armed = tlon(nav_focus(), %{tlon_delete: target})
      assert {%{tlon_delete: nil}, {:tlon_delete, ^target}} = Keymap.handle(char("d"), armed)

      assert {%{tlon_delete: nil} = disarmed, :repaint} = Keymap.handle(char("j"), armed)
      assert disarmed.focus == armed.focus
    end

    test "d in the terminal forwards — the delete verb never fires while typing" do
      s = tlon()
      k = char("d")
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end

    test "in nav mode with no detail open, Esc returns to the terminal" do
      {next, :repaint} = Keymap.handle(key(:escape), tlon(nav_focus()))
      assert next.focus.in_terminal? == true
    end

    test "in nav mode with a detail open, Esc closes the detail first (stays in nav)" do
      {next, :repaint} = Keymap.handle(key(:escape), tlon(nav_focus(%{detail?: true})))
      assert next.focus.detail? == false
      assert next.focus.in_terminal? == false
    end

    test "in nav mode, q still quits" do
      assert {_s, :quit} = Keymap.handle(char("q"), tlon(nav_focus()))
    end

    # The center [chat]|[terminal] toggle (reshape slice D): `v` in nav flips which face the
    # Workspace center shows — the live PTY or the attached thread's conversation.
    test "in nav mode, v toggles the center view" do
      s = tlon(nav_focus())
      assert {^s, :toggle_center_view} = Keymap.handle(char("v"), s)
    end

    test "in the terminal, v forwards like any other key — no toggle hijack" do
      s = tlon(Focus.new())
      assert {_s, {:forward, _key}} = Keymap.handle(char("v"), s)
    end

    test "in nav mode, c opens the composer on the machine thread" do
      s = tlon(nav_focus(), %{composer_thread_id: 7})
      assert {%{input: %{kind: :compose, thread_id: 7}}, :repaint} = Keymap.handle(char("c"), s)
    end

    test "in nav mode, an unbound key is a no-op — nav mode never forwards to tmux" do
      s = tlon(nav_focus())
      assert {^s, :none} = Keymap.handle(char("z"), s)
    end

    test "a live composer modal still captures keys — focus never hijacks typing" do
      s = tlon(nav_focus(), %{input: %{kind: :compose, thread_id: 9, buffer: "", cursor: 0}})
      {next, :repaint} = Keymap.handle(char("l"), s)
      assert next.input.buffer == "l"
    end

    test "off a workspace key (a stale one) a present focus struct is ignored — the key forwards" do
      s = state(%{active_key: :stale, center_live?: true, focus: Focus.new()})
      assert {^s, {:forward, %{key: :space, ctrl: true}}} = Keymap.handle(key(:space, ctrl: true), s)
    end
  end

  describe "global Alt chords (clarity slice 4)" do
    # A 3-left/2-right layout (mirrors View's [Spaces, Stack, Memory] / [Health, Crew]) so digit
    # jumps land distinctly across both columns.
    defp alt_layout, do: %{left: [:a, :b, :c], right: [:d, :e], sections: %{}, counts: %{}}

    test "Alt+digit selects the Nth tmux tab (nav v2)" do
      s = tlon(Focus.new())
      assert {_next, {:select_tab, 2}} = Keymap.handle(char("2", alt: true), s)
    end

    test "Alt+0 selects the 10th tab" do
      s = tlon(Focus.new())
      assert {_next, {:select_tab, 10}} = Keymap.handle(char("0", alt: true), s)
    end

    test "Alt+Shift+digit switches to the Nth workspace (0 = the 10th)" do
      s = tlon(Focus.new())
      assert {_next, {:switch_workspace_pos, 3}} = Keymap.handle(char("3", alt: true, shift: true), s)
      assert {_next, {:switch_workspace_pos, 10}} = Keymap.handle(char("0", alt: true, shift: true), s)
    end

    test "Alt+j moves a pane down from the terminal (implicit nav)" do
      s = tlon(Focus.new(), %{tlon_layout: alt_layout()})
      {next, :repaint} = Keymap.handle(char("j", alt: true), s)
      assert next.focus.in_terminal? == false
    end

    test "Alt+c opens the composer from the terminal" do
      s = tlon(Focus.new(), %{composer_thread_id: 7})
      {next, :repaint} = Keymap.handle(char("c", alt: true), s)
      assert next.input.kind == :compose
    end

    test "Alt+\\ toggles the right session pane" do
      s = tlon(Focus.new())
      assert {_next, :toggle_session_pane} = Keymap.handle(char("\\", alt: true), s)
    end

    test "a bare digit in NAV is a no-op — pane digits are gone (nav v2)" do
      s = tlon(nav_focus(), %{tlon_layout: alt_layout()})
      assert {^s, :none} = Keymap.handle(char("4"), s)
    end

    test "a global Alt chord reaches the shared command table with the modifier stripped" do
      {next, :repaint} = Keymap.handle(char("n", alt: true), state())
      assert next.input.kind == :new_thread
    end
  end

  describe "LOCK mode (clarity slice 4)" do
    test "Alt+g locks; everything then forwards; Alt+g unlocks" do
      s = tlon(Focus.new(), %{center_live?: true, lock?: false})

      {locked, :repaint} = Keymap.handle(char("g", alt: true), s)
      assert locked.lock?

      # Alt+digit forwards under lock — readline owns it now.
      assert {_s, {:forward, %{key: :char, char: "1", alt: true}}} =
               Keymap.handle(char("1", alt: true), locked)

      # Ctrl+Space forwards too — even the mode toggle is the app's under lock.
      assert {_s, {:forward, %{key: :space, ctrl: true}}} =
               Keymap.handle(key(:space, ctrl: true), locked)

      {unlocked, :repaint} = Keymap.handle(char("g", alt: true), locked)
      refute unlocked.lock?
    end

    test "locked with no live center is a plain no-op (nothing to forward to)" do
      s = tlon(Focus.new(), %{center_live?: false, lock?: true})
      assert {^s, :none} = Keymap.handle(char("1", alt: true), s)
    end

    test "Alt+g while composing neither locks nor types — the modal blocks the arm" do
      s = state(%{input: %{kind: :compose, thread_id: 1, buffer: "hi", cursor: 2}})
      {next, :none} = Keymap.handle(char("g", alt: true), s)
      refute Map.get(next, :lock?, false)
      assert next.input.buffer == "hi"
    end
  end

  # UX slice 1, task 4: the drawer — Alt+d over the centre, its own key table while open.
  describe "the drawer (Alt+d)" do
    # The layout the focus SM walks while the drawer is open: its nine panes as one column.
    defp drawer_layout(counts \\ %{}) do
      %{left: Drawer.pane_modules(), right: [], sections: %{Console.Panel.Memory => 2}, counts: counts}
    end

    defp drawer(overrides) do
      tlon(
        %Focus{in_terminal?: true},
        Map.merge(%{drawer: nil, last_drawer: :memory, tlon_layout: drawer_layout()}, overrides)
      )
    end

    test "Alt+d opens the drawer on its last pane and Alt+d / Esc close it" do
      {s1, :repaint} = Keymap.handle(char("d", alt: true), drawer(%{last_drawer: :stack}))
      assert s1.drawer == :stack
      # the drawer has the focus by definition — the keys are its own, not the terminal's
      refute s1.focus.in_terminal?
      assert Drawer.at(s1.focus.pane) == :stack

      {s2, :repaint} = Keymap.handle(key(:escape), s1)
      assert s2.drawer == nil and s2.last_drawer == :stack
      assert s2.focus.in_terminal?

      {s3, :repaint} = Keymap.handle(char("d", alt: true), s2)
      {s4, :repaint} = Keymap.handle(char("d", alt: true), s3)
      assert s4.drawer == nil and s4.last_drawer == :stack
    end

    test "h/l walk the panes, clamped at both ends, and 1-9 jump straight to one" do
      s = drawer(%{drawer: :now, focus: %Focus{in_terminal?: false, pane: 0}})

      assert {%{drawer: :now}, :repaint} = Keymap.handle(char("h"), s)
      {right, :repaint} = Keymap.handle(char("l"), s)
      assert right.drawer == :crew
      assert Drawer.at(right.focus.pane) == :crew

      {jumped, :repaint} = Keymap.handle(char("4"), s)
      assert jumped.drawer == :stack
      assert Drawer.at(jumped.focus.pane) == :stack

      # past the last pane: nothing moves
      assert {%{drawer: :now}, :none} = Keymap.handle(char("0"), s)
    end

    test "j/k move the focused pane's own cursor" do
      s =
        drawer(%{
          drawer: :stack,
          focus: %Focus{in_terminal?: false, pane: Drawer.index(:stack)},
          tlon_layout: drawer_layout(%{Stack => 3})
        })

      {down, :repaint} = Keymap.handle(char("j"), s)
      assert down.focus.cursors[Stack] == 1
      {up, :repaint} = Keymap.handle(char("k"), down)
      assert up.focus.cursors[Stack] == 0
    end

    test "Enter is the cockpit's contextual verb, and s/y/d/a/r reach the pane's own" do
      s = drawer(%{drawer: :memory, focus: %Focus{in_terminal?: false, pane: Drawer.index(:memory)}})

      assert {_s, :tlon_enter} = Keymap.handle(key(:enter), s)
      assert {_s, :yank} = Keymap.handle(char("y"), s)
      assert {_s, :tlon_delete_arm} = Keymap.handle(char("d"), s)
      assert {_s, {:habit_action, :approve}} = Keymap.handle(char("a"), s)
      assert {_s, {:habit_action, :reject}} = Keymap.handle(char("r"), s)
      {sectioned, :repaint} = Keymap.handle(char("s"), s)
      assert sectioned.focus.section == 1
    end

    test "the TICKETS pane keeps its board verbs: n files, p advances, H/L walk the columns" do
      s = drawer(%{drawer: :tickets, focus: %Focus{in_terminal?: false, pane: Drawer.index(:tickets)}})

      assert {%{input: %{kind: :new_ticket}}, :repaint} = Keymap.handle(char("n"), s)
      assert {_s, :ticket_advance} = Keymap.handle(char("p"), s)
      assert {_s, {:ticket_move, "h"}} = Keymap.handle(char("H"), s)
      assert {_s, {:ticket_move, "l"}} = Keymap.handle(char("L"), s)
      assert {_s, {:ticket_move, "j"}} = Keymap.handle(char("j"), s)
    end

    test "the NOTES pane's n jots a note" do
      s = drawer(%{drawer: :notes, focus: %Focus{in_terminal?: false, pane: Drawer.index(:notes)}})
      assert {%{input: %{kind: :new_note}}, :repaint} = Keymap.handle(char("n"), s)
    end

    test "an unbound key is swallowed — it never leaks to the frame underneath" do
      s = drawer(%{drawer: :memory, center_live?: true})
      assert {^s, :none} = Keymap.handle(char("z"), s)
    end

    test "typing a new ticket's title takes the keys back from the drawer" do
      s = drawer(%{drawer: :tickets, input: %{kind: :new_ticket, buffer: "", cursor: 0}})
      {typed, :repaint} = Keymap.handle(char("h"), s)
      assert typed.input.buffer == "h"
      assert typed.drawer == :tickets
    end
  end

  describe "the TICKETS pane's reorder keys (UX slice 4)" do
    test "J and K reorder the selected ticket within its column" do
      s = state(%{drawer: :tickets})

      assert {^s, {:ticket_reorder, :down}} = Keymap.handle_drawer(char("J"), s)
      assert {^s, {:ticket_reorder, :up}} = Keymap.handle_drawer(char("K"), s)
    end

    test "they are the TICKETS pane's own — another pane still takes j/k as a cursor move" do
      s = state(%{drawer: :memory})

      # `J` is not a vertical key anywhere (only j/k and the arrows are), so off the TICKETS pane it
      # is simply unbound — never a reorder aimed at a board that is not on screen.
      assert {^s, :none} = Keymap.handle_drawer(char("J"), s)
    end

    test "lowercase j/k still move the kanban cursor, not the card" do
      s = state(%{drawer: :tickets})

      assert {^s, {:ticket_move, "j"}} = Keymap.handle_drawer(char("j"), s)
      assert {^s, {:ticket_move, "k"}} = Keymap.handle_drawer(char("k"), s)
    end
  end

  describe "the drawer over an open thread — the `Alt+d`-is-dead-in-the-reply-box bug" do
    # The reply box is the only PERSISTENT input: it is focused the whole time a thread is open, so
    # while it sat above the drawer clauses `Alt+d` could not reach them at all — the drawer was
    # openable from the thread LIST and nowhere else.
    defp reply_drawer(over \\ %{}),
      do:
        stack_ctx(
          Map.merge(
            %{
              opened_thread: 2,
              input: %{kind: :reply, thread_id: 2, buffer: "half typed", cursor: 10},
              drawer: nil,
              last_drawer: :stack,
              tlon_layout: %{left: Drawer.pane_modules(), right: [], sections: %{}, counts: %{}}
            },
            over
          )
        )

    test "Alt+d opens the drawer from inside the reply box, draft untouched" do
      {next, :repaint} = Keymap.handle(char("d", alt: true), reply_drawer())

      assert next.drawer == :stack
      assert next.input == %{kind: :reply, thread_id: 2, buffer: "half typed", cursor: 10}
    end

    test "with the drawer open the DRAWER owns the keys — a letter walks the strip, it does not type" do
      {open, :repaint} = Keymap.handle(char("d", alt: true), reply_drawer())
      {walked, :repaint} = Keymap.handle(char("l"), open)

      assert walked.drawer == :roster
      assert walked.input.buffer == "half typed"
    end

    test "Alt+d closes it again and the draft is still there to type into" do
      {open, :repaint} = Keymap.handle(char("d", alt: true), reply_drawer())
      {shut, :repaint} = Keymap.handle(char("d", alt: true), open)

      assert shut.drawer == nil and shut.last_drawer == :stack
      assert {%{input: %{buffer: "half typedx"}}, :repaint} = Keymap.handle(char("x"), shut)
    end

    test "Esc closes the DRAWER first, not the thread view — one Esc, one level" do
      {open, :repaint} = Keymap.handle(char("d", alt: true), reply_drawer())

      assert {%{drawer: nil, input: %{buffer: "half typed"}}, :repaint} = Keymap.handle(key(:escape), open)
    end

    test "a transient modal the drawer's own verb opens still takes the keys back" do
      s = reply_drawer(%{drawer: :tickets, input: %{kind: :new_ticket, buffer: "", cursor: 0}})

      assert {%{input: %{buffer: "l"}, drawer: :tickets}, :repaint} = Keymap.handle(char("l"), s)
    end

    test "Alt+\\\\ toggles the session pane from inside the reply box too" do
      assert {_s, :toggle_session_pane} = Keymap.handle(char("\\", alt: true), reply_drawer())
    end

    test "Ctrl+Space toggles term↔nav from inside the reply box — the way OUT of the terminal" do
      s = reply_drawer()

      {next, :repaint} = Keymap.handle(ctrl_space(), s)

      refute next.focus.in_terminal?
      assert next.input.buffer == "half typed", "the draft is focus, not text — it survives"
    end

    test "with the drawer open, Ctrl+Space belongs to the drawer, not the terminal toggle" do
      {open, :repaint} = Keymap.handle(char("d", alt: true), reply_drawer())

      assert {^open, :none} = Keymap.handle(ctrl_space(), open)
    end

    test "the LEGACY NUL encoding of Ctrl+Space toggles too — tmux never sends the Kitty form" do
      # raxol decodes a bare NUL as a ctrl-modified space CHAR; the Kitty CSI-u form is :space.
      legacy = %{key: :char, char: " ", ctrl: true}
      s = reply_drawer(%{input: nil})

      {next, :repaint} = Keymap.handle(legacy, s)
      refute next.focus.in_terminal?
    end

    test "the legacy encoding does not type a space into the reply box" do
      s = reply_drawer()

      {next, :repaint} = Keymap.handle(%{key: :char, char: " ", ctrl: true}, s)
      assert next.input.buffer == "half typed", "ctrl+space is a toggle, never text"
    end

    test "Alt+g, Alt+n and Alt+digit stay SWALLOWED while the box is live — each would break a draft" do
      s = reply_drawer()

      # LOCK would make the box a passthrough terminal mid-sentence. The fixture carries no `lock?`
      # key at all, so an unchanged state is proof the arm never fired.
      assert {^s, :none} = Keymap.handle(char("g", alt: true), s)
      # a second modal would take the screen from the draft
      assert {^s, :none} = Keymap.handle(char("n", alt: true), s)
      # a workspace switch would leave the draft pointing at another workspace's thread
      assert {^s, :none} = Keymap.handle(char("2", alt: true, shift: true), s)
    end
  end
end
