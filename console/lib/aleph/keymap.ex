defmodule Console.Keymap do
  @moduledoc """
  The cockpit's keyhandling as a **pure reducer** (design §8): `(key_event, state) → {new_state,
  effect}`, with no TTY, no tmux, and no paint. Extracting the decision from the side effect is
  what makes every binding testable headlessly (`Console.KeymapTest`) — the `Console.Cockpit`
  GenServer stays a thin interpreter of the returned effect.

  **Input model — tmux-style** (see `docs/plans/2026-08-16-aleph-tmux-style-input.md`): the center
  surface owns the keys by default. A **live terminal** in the center forwards every key to its PTY
  (the terminal is "normal mode"); console's own commands are reached through a `Ctrl+Space` **leader**
  that arms the *next* key as an console command. NOT Ctrl+B: that's tmux's prefix, and the Tlön
  center is literal tmux — Ctrl+B forwards like any other key so `C-b 2` reaches the real thing.
  When there's no live terminal (Orbis' chorus, or a placeholder before a session spawns), console's
  nav bindings are **bare** — the same command table, reached without the prefix. One command
  table, two doors. (Ctrl+Space arrives as Kitty CSI-u `\\e[32;5u` → `%{key: :space, ctrl: true}`
  under the disambiguate mode the cockpit arms on the host.)

  `state` is the slice of cockpit state keys touch: `active_key`, `focused_id`, `threads`,
  `center_live?` (derived per keypress by the cockpit — true when a live terminal is in the
  center), `composer_thread_id` (also derived per keypress — the thread the `c` verb composes
  onto: the focused thread, or the machine thread in Tlön), `leader_pending?` (the prefix is
  armed), `input` (the typing modal), `orbis_focus` (`:survey | :threads` — which cursor Orbis'
  `j/k` drives; `h`/`l` toggle it), `survey_cursor` (the Orbis survey's per-row cursor, clamped to
  the live workspace count), and `leaves` (the cached `Console.Orbis.rollup/0`, read-only here for its
  `workspaces` list — the same cache the cockpit's `orbis_workspaces/1` reads). A `key_event` is the
  `Raxol.Core.Events.Event` `data` map, e.g. `%{key: :up}` or `%{key: :char, char: "j"}`.

  Effects:

    * `:repaint` — state changed; reload server reads and paint.
    * `:quit` — tear down and stop.
    * `{:forward, key}` — send this key to the focused session's embedded terminal.
    * `{:create_thread, title}` — open a new thread AND spawn a session onto it (the `n` verb).
    * `{:post_message, thread_id, body}` — post the composer's body to the focused thread as the
      operator (the `c` verb).
    * `{:cycle_coworker_model, profile}` — advance the active space's coworker driver model one
      step round `Console.Profiles.model_ring/0` and persist it (the `m` verb — the SETTINGS knob;
      only in a space with a coworker).
    * `{:switch_space, key}` — Enter on the Orbis survey (`orbis_focus == :survey`) zooms into the
      cursor row's workspace id — the same effect a survey-row click emits (D0.2).
    * `{:toggle_orbis_face}` — `a` (Orbis, bare) flips `orbis_face` survey↔author (D2.1); Esc in
      the author face emits the same effect to step back to the survey.
    * `{:register_workspace, template_key, name}` — Enter on the `:new_workspace` input (the author
      face's `n` verb) — register a workspace from a template + the typed name (D2.3).
    * `{:arm_delete, id, name}` — `d` on the author face's cursor row arms a delete confirm (D2.5).
    * `{:remove_workspace, id}` — the second `d` while armed on the SAME id confirms the delete.
    * `{:edit_workspace, id, attrs}` — the field editor's `h`/`l` rings (type/scope) and the paths/
      roster sub-list's `a`/`x`/`d` (D2.4 Chunk 2a) — apply one attrs map to a workspace immediately.
    * `{:coworker_knob, name, knob}` — the roster sub-list's `Tab`-selected knob (`:model` |
      `:yolo`), applied by `Enter`/`Space` to the sub-selected coworker (D2.4 Chunk 2b — absorbs
      the old `,` settings modal into the roster editor; the modal itself is deleted).
    * `:none` — nothing to do.

  `state.input` is `nil` normally, or `%{kind: :new_thread, buffer, cursor}` (the `n` verb),
  `%{kind: :compose, thread_id, buffer, cursor}` (the `c` verb), or `%{kind: :new_workspace, buffer,
  cursor, template}` (the author face's `n` verb — `template` is a `WorkspaceTemplates.names/0` atom,
  `h`/`l` cycle it) while the operator is typing — a modal that captures EVERY key (so `q` types a
  "q", it does not quit) until Enter submits or Esc cancels. `cursor` is a grapheme offset into
  `buffer` (not always the end — Left/Right/Up/Down/Home/End move it, Ctrl+P/Ctrl+N alias Up/Down
  for hosts that don't deliver arrow keys, and Ctrl+A/Ctrl+E/Ctrl+U/Ctrl+K/Ctrl+W are readline's
  line-editing reflexes), and every edit (typing, Backspace, Shift+Enter's newline) acts AT the
  cursor, like a normal text box. In the composer, Shift+Enter inserts a newline (multiline
  bodies) instead of submitting.

  Orbis' AUTHOR face (D2, Chunk 1): `orbis_face :: :survey | :author` (default `:survey`) picks
  which center panel `Console.View` renders — `a` toggles it on, Esc steps back off. `author_cursor`
  is the author list's own per-row cursor (mirrors `survey_cursor`), clamped against
  `author_workspaces` — the live `Console.Workspaces.all/0` list, threaded in per keypress (like
  `composer_thread_id`) so this module stays a pure reducer with no server call of its own.
  `pending_delete` (id | nil) is the two-key delete confirm's arm.

  The field editor (D2.4 Chunk 2a): `author_edit :: nil | %{id, field, sub, mode}` — `e` on the
  list's cursor workspace opens it at `field: 0` (type), `mode: :field`. `mode` (`:field | :sub`) is
  an addition beyond the plan's 3-key shape — the field list and a field's sub-list (paths/roster
  entries) both drive `j`/`k` over a DIFFERENT cursor (`field` vs `sub`) and need a bit to tell
  which is live; everything else matches the plan verbatim. `field` cycles the 4 rows (0 type · 1
  scope · 2 paths · 3 roster) with `j`/`k`, clamped no-wrap. On fields 0/1, `h`/`l` cycle a ring
  (`@type_ring`/`@scope_ring`) and emit `{:edit_workspace, id, attrs}` immediately — no draft/commit
  step. On fields 2/3, `Enter` drops into the sub-list (`mode: :sub`, `sub` resets to 0); there
  `j`/`k` move `sub` (clamped to the live paths/roster length), `a` opens an add buffer
  (`state.input` kind `:new_path` or `:new_roster` — the latter also carries an `archetype` ring
  cycled by `h`/`l`, mirroring `:new_workspace`'s `template`), `x`/`d` removes the `sub`-selected entry
  immediately, and `Esc` steps back to `mode: :field`. `Esc` on `mode: :field` clears `author_edit`
  entirely (back to the list). While `author_edit` is set, the list's own `n`/`d`/`a` verbs are
  blocked (`:none`) — editing and list-management stay separate modes, same as `input`/`modal`.

  The roster sub-list ALSO carries `knob :: :model | :yolo` (D2.4 Chunk 2b, default `:model`,
  read tolerantly via `Map.get/3` so older literal states don't need it) — meaningless outside
  `mode: :sub, field: 3` (roster), same "meaningless-but-harmless elsewhere" idiom as
  `orbis_focus`. There `Tab` flips it; `Enter`/`Space` emit
  `{:coworker_knob, name, knob}` for the sub-selected entry (`name` resolved off the LIVE roster,
  `workspace_field/2`, same as the `a`/`x`/`d` clauses) — the Settings modal's model-ring-cycle /
  yolo-flip, now reached from here. This absorbs Settings; Chunk 2b deletes the `,` modal.
  """
  alias Console.Panel
  alias Console.Profiles
  alias Console.Space
  alias Console.Tlon.Focus
  alias Console.WorkspaceTemplates

  # `Space.workspace?/1` is a `defguard` (usable in clause-head `when`s), which requires the module,
  # not just an alias.
  require Space

  # The field editor's rings (D2.4 Chunk 2a) — `h`/`l` cycle these on fields 0/1. Match
  # `Server.Workspace`'s DB CHECK closed sets exactly (funes/lib/funes/workspace.ex).
  @type_ring ["code", "life", "blank"]
  @scope_ring ["project", "machine"]

  @type effect ::
          :repaint
          | :quit
          | {:forward, map()}
          | {:create_thread, String.t()}
          | {:file_ticket, String.t()}
          | {:write_note, String.t()}
          | {:orchestrate, String.t()}
          | {:confirm_orchestrate, map()}
          | {:toggle_fold}
          | :toggle_session_pane
          | {:zoom_thread}
          | {:post_message, term(), String.t()}
          | {:cycle_coworker_model, String.t()}
          | {:habit_action, :approve | :reject}
          | {:switch_space, atom() | non_neg_integer()}
          | {:switch_workspace_pos, pos_integer()}
          | {:select_tab, pos_integer()}
          | {:toggle_orbis_face}
          | {:register_workspace, atom(), String.t()}
          | {:arm_delete, term(), String.t()}
          | {:remove_workspace, term()}
          | {:edit_workspace, term(), map()}
          | {:coworker_knob, String.t(), :model | :yolo}
          | :tlon_enter
          | :stack_delete_arm
          | :tlon_preview
          | :yank
          | :none

  @doc "Map a key event against the current state to the next state and the effect to run."
  @spec handle(map(), map()) :: {map(), effect()}

  # --- LOCK mode (design 2026-08-23): total passthrough. Alt+g alone is console's; every other
  # key — Alt chords, the leader, Esc — forwards raw so readline/emacs keep their Alt bindings.
  # These LOCKED-state clauses precede everything; the ARM clause sits BELOW the input modal by
  # design (modal-blocked) — locking mid-compose is never intended, and no modal can open while
  # locked, so these clauses never conflict with one.
  def handle(%{key: :char, char: "g", alt: true}, %{lock?: true} = state), do: {Map.put(state, :lock?, false), :repaint}

  def handle(key, %{lock?: true, center_live?: true} = state), do: {state, {:forward, key}}
  def handle(_key, %{lock?: true} = state), do: {state, :none}

  # Shift+Space (Kitty CSI-u \e[32;2u → %{key: :space, shift: true}) is just a space — normalize it
  # to a plain char up front so EVERY downstream path treats it identically: the composer inserts it,
  # a live terminal forwards a real space byte, nav ignores it like a bare space. Without this it
  # falls through to the drop-everything tables and vanishes. Ctrl+Space (the leader, has :ctrl, not
  # :shift) never matches here, so the prefix is untouched.
  def handle(%{key: :space, shift: true} = key, state) when not is_map_key(key, :ctrl),
    do: handle(%{key: :char, char: " "}, state)

  # --- tertius y/n confirm gate (Slice 3.5): a consequential verb (open work / approve a gate) was
  # routed and is armed, waiting on the operator — the whole point is that a command line you talk into
  # NEVER fires a consequential action without a yes. While `pending_confirm` is set every key belongs
  # to the gate: `y` fires it (`:confirm_orchestrate`, apply_effect reads the arm), anything else backs
  # out. Precedes even the input modal — no modal can be open while armed (the submit cleared it). ---
  def handle(%{key: :char, char: "y"}, %{pending_confirm: pc} = state) when not is_nil(pc),
    do: {%{state | pending_confirm: nil}, {:confirm_orchestrate, pc}}

  def handle(_key, %{pending_confirm: pc} = state) when not is_nil(pc),
    do: {%{state | pending_confirm: nil}, :repaint}

  # --- input mode: a MODAL — every key belongs to the buffer until Enter/Esc, so a binding
  # letter (q, s, tab) types its character instead of firing. Must come first. ---
  def handle(%{key: :escape}, %{input: %{}} = state), do: {%{state | input: nil}, :repaint}

  # Shift+Enter in the composer inserts a newline (a multiline body) instead of submitting, AT
  # the cursor (not always the end — Up/Down can have moved it off the last line). Must precede
  # the plain-Enter clauses — %{key: :enter, shift: true} also matches %{key: :enter}.
  def handle(%{key: :enter, shift: true}, %{input: %{kind: :compose} = input} = state),
    do: {%{state | input: insert_at(input, "\n")}, :repaint}

  # Enter submits — but an empty buffer creates/posts nothing (cancel), never a blank thread/message.
  def handle(%{key: :enter}, %{input: %{buffer: ""}} = state), do: {%{state | input: nil}, :repaint}

  def handle(%{key: :enter}, %{input: %{kind: :new_thread, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:create_thread, buffer}}

  # The `new` menu's ticket/note branches (Slice C): file a workspace ticket / jot a workspace note —
  # first-class create for the two nouns that were previously only reachable via a tertius prefix.
  def handle(%{key: :enter}, %{input: %{kind: :new_ticket, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:file_ticket, buffer}}

  def handle(%{key: :enter}, %{input: %{kind: :new_note, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:write_note, buffer}}

  # The tertius command line (Slice 1): Enter dispatches the typed meta-intent to the orchestrator,
  # which routes + executes it and hands back a receipt (the cockpit flashes it).
  def handle(%{key: :enter}, %{input: %{kind: :orchestrate, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:orchestrate, buffer}}

  # A non-blank name registers a workspace from the armed template. Blank already fell into the
  # empty-buffer clause above, same cancel-not-create precedent as :new_thread.
  def handle(%{key: :enter}, %{input: %{kind: :new_workspace, template: template, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:register_workspace, template, buffer}}

  # A non-blank path appends to the edited workspace's LIVE paths list (author_workspaces, threaded per
  # keypress) and applies immediately. Blank already fell into the empty-buffer clause above.
  def handle(%{key: :enter}, %{input: %{kind: :new_path, workspace_id: id, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:edit_workspace, id, %{paths: workspace_field(state, id, :paths) ++ [buffer]}}}

  # A non-blank name appends a wire-shaped roster entry (`%{"archetype" => .., "name" => ..}`,
  # matching `WorkspaceTemplates.new_workspace_attrs/2`'s shape) to the edited workspace's LIVE roster and
  # applies immediately. Blank already fell into the empty-buffer clause above.
  def handle(%{key: :enter}, %{input: %{kind: :new_roster, workspace_id: id, archetype: arch, buffer: buffer}} = state) do
    entry = %{"archetype" => Atom.to_string(arch), "name" => buffer}
    {%{state | input: nil}, {:edit_workspace, id, %{roster: workspace_field(state, id, :roster) ++ [entry]}}}
  end

  # Slash commands are the composer's other door (reshape slice D): /status is the full HEALTH
  # readout (the panel demoted to a footer line), never posted as a chat message.
  def handle(%{key: :enter}, %{input: %{kind: :compose, thread_id: id, buffer: buffer}} = state) do
    case String.trim(buffer) do
      "/status" -> {%{state | input: nil}, {:show_status, id}}
      _body -> {%{state | input: nil}, {:post_message, id, buffer}}
    end
  end

  # Backspace deletes the grapheme BEFORE the cursor (not always the buffer's last char — the
  # cursor can sit mid-buffer once Up/Down/Left/Right have moved it). A cursor at 0 is a no-op.
  def handle(%{key: :backspace}, %{input: %{}} = state),
    do: {%{state | input: delete_before_cursor(state.input)}, :repaint}

  # Left/Right move the cursor a grapheme; Home/End jump to the start/end of the CURRENT line (not
  # the whole buffer) — the usual text-box contract for a multiline composer.
  def handle(%{key: :left}, %{input: %{}} = state), do: {%{state | input: move_cursor(state.input, -1)}, :repaint}
  def handle(%{key: :right}, %{input: %{}} = state), do: {%{state | input: move_cursor(state.input, 1)}, :repaint}
  def handle(%{key: :home}, %{input: %{}} = state), do: {%{state | input: cursor_home(state.input)}, :repaint}
  def handle(%{key: :end}, %{input: %{}} = state), do: {%{state | input: cursor_end(state.input)}, :repaint}

  # Up/Down move a line, preserving column where possible — a no-op on a single-line buffer
  # (`new_thread`'s title). Ctrl+P/Ctrl+N are the readline aliases (previous/next line — the same
  # keys readline's history recall uses): some hosts (a nested tmux/SSH hop) don't deliver arrow
  # keys reliably, so this box always has a working up/down. MUST precede the generic char clause
  # below — %{key: :char, char: "p"} also matches a bare "p" keystroke.
  def handle(%{key: :up}, %{input: %{}} = state), do: {%{state | input: move_line(state.input, -1)}, :repaint}
  def handle(%{key: :down}, %{input: %{}} = state), do: {%{state | input: move_line(state.input, 1)}, :repaint}

  def handle(%{key: :char, char: "p", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: move_line(state.input, -1)}, :repaint}

  def handle(%{key: :char, char: "n", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: move_line(state.input, 1)}, :repaint}

  # Ctrl+A/Ctrl+E: the emacs/readline aliases for Home/End (current line, not the whole buffer) —
  # some hosts deliver these more reliably than the Home/End keycaps, and they're the muscle
  # memory a shell/readline already trained. MUST precede the generic char clause below, same
  # reason as Ctrl+P/Ctrl+N.
  def handle(%{key: :char, char: "a", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: cursor_home(state.input)}, :repaint}

  def handle(%{key: :char, char: "e", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: cursor_end(state.input)}, :repaint}

  # Ctrl+U: readline's unix-line-discard — kill from the start of the CURRENT line to the cursor.
  # Ctrl+K: readline's kill-line — kill from the cursor to the END of the current line (free to
  # bind now that Ctrl+P/Ctrl+N took over up/down). Ctrl+W: unix-word-rubout — kill the word
  # behind the cursor. All three are the "undo what I just typed" reflexes a shell trains.
  def handle(%{key: :char, char: "u", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: kill_to_line_start(state.input)}, :repaint}

  def handle(%{key: :char, char: "k", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: kill_to_line_end(state.input)}, :repaint}

  def handle(%{key: :char, char: "w", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: kill_word_backward(state.input)}, :repaint}

  # `:new_workspace`'s h/l cycle the armed template (a ring, `WorkspaceTemplates.names/0`) instead of
  # inserting the letter — must precede the generic printable-insert clause below.
  def handle(%{key: :char, char: "h"}, %{input: %{kind: :new_workspace} = input} = state),
    do: {%{state | input: cycle_template(input, -1)}, :repaint}

  def handle(%{key: :char, char: "l"}, %{input: %{kind: :new_workspace} = input} = state),
    do: {%{state | input: cycle_template(input, 1)}, :repaint}

  # `:new_roster`'s h/l cycle the armed archetype (a ring, `Profiles.archetypes/0`'s keys) —
  # same precedence reasoning as `:new_workspace`'s template ring above.
  def handle(%{key: :char, char: "h"}, %{input: %{kind: :new_roster} = input} = state),
    do: {%{state | input: cycle_archetype(input, -1)}, :repaint}

  def handle(%{key: :char, char: "l"}, %{input: %{kind: :new_roster} = input} = state),
    do: {%{state | input: cycle_archetype(input, 1)}, :repaint}

  # Printable keys insert AT the cursor, not append — so typing after moving the cursor lands
  # where you moved it, like a normal text box. Alt-modified chars are chords, not text (Alt+g's
  # lock arm included) — they fall to the ignore catch-all below.
  def handle(%{key: :char, char: c} = k, %{input: %{}} = state) when is_binary(c) and not is_map_key(k, :alt),
    do: {%{state | input: insert_at(state.input, c)}, :repaint}

  # A space can arrive as %{key: :space} with no `char`: under [>1u disambiguation (which the cockpit
  # enables) Kitty CSI-u reports Shift+Space as [32;2u → %{key: :space, shift: true}. A plain space
  # is a printable %{key: :char, char: " "} caught above; this clause catches the modified form so it
  # inserts instead of falling to the drop-everything catch-all below.
  def handle(%{key: :space}, %{input: %{}} = state), do: {%{state | input: insert_at(state.input, " ")}, :repaint}

  # Any other key while typing (function keys, …) is ignored, not acted on.
  def handle(_key, %{input: %{}} = state), do: {state, :none}

  # Alt+g arms LOCK — below the modal by design: the modal's catch-all swallows it while typing,
  # so composing can never silently freeze under a lock.
  def handle(%{key: :char, char: "g", alt: true} = k, state) when not is_map_key(k, :ctrl),
    do: {Map.put(state, :lock?, true), :repaint}

  # --- Global Alt chords (design 2026-08-23): work from ANY mode — TERM included — and switch
  # mode implicitly. Workspace-only for movement (there's no pane grid elsewhere); n/c everywhere.
  # Must precede the Tlön routing clause (which would forward them to tmux from TERM). Each clears
  # an armed leader (`clear_leader/1`) — these sit above the leader-consumption clause, so without
  # it Ctrl+Space then an Alt chord would leave the prefix stuck.
  # Nav v2 (Andrew 2026-08-31): Alt+Shift+digit → switch to the Nth WORKSPACE; Alt+digit (no shift) →
  # select tmux TAB N in the active workspace. `0` is the 10th. The shift clause is first (more
  # specific). (These replace the old Alt+digit focus-pane jump — pane digits are gone.)
  def handle(%{key: :char, char: d, alt: true, shift: true} = k, %{active_key: key} = state)
      when Space.workspace?(key) and d in ~w(0 1 2 3 4 5 6 7 8 9) and not is_map_key(k, :ctrl),
      do: {clear_leader(state), {:switch_workspace_pos, digit_pos(d)}}

  def handle(%{key: :char, char: d, alt: true} = k, %{active_key: key} = state)
      when Space.workspace?(key) and d in ~w(0 1 2 3 4 5 6 7 8 9) and not is_map_key(k, :ctrl),
      do: {clear_leader(state), {:select_tab, digit_pos(d)}}

  def handle(%{key: :char, char: c, alt: true} = k, %{active_key: key, focus: %Focus{}} = state)
      when Space.workspace?(key) and c in ~w(h j k l) and not is_map_key(k, :ctrl),
      do: {state |> clear_leader() |> alt_move(c), :repaint}

  # Alt+n / Alt+c reach the shared command table with the modifier stripped (its clauses are
  # modifier-guarded on purpose — a bare-shaped key is the door).
  def handle(%{key: :char, char: "n", alt: true} = k, state) when not is_map_key(k, :ctrl),
    do: command(%{key: :char, char: "n"}, clear_leader(state))

  def handle(%{key: :char, char: "c", alt: true} = k, state) when not is_map_key(k, :ctrl),
    do: command(%{key: :char, char: "c"}, clear_leader(state))

  # Alt+\ toggles the right SESSION PANE (2026-08-31): show/hide the selected thread's live lead PTY
  # beside the stack. Workspace-only (there's no thread stack elsewhere); global across TERM/NAV.
  def handle(%{key: :char, char: "\\", alt: true} = k, %{active_key: key} = state)
      when Space.workspace?(key) and not is_map_key(k, :ctrl),
      do: {clear_leader(state), :toggle_session_pane}

  # --- Tlön: the lazygit focus model (design 2026-08-20). The center is a live tmux client, so
  # `Ctrl+Space` is a STICKY toggle in/out of it — NOT the arm-next-key leader other spaces use.
  # In the terminal every key forwards to tmux; out of it console owns the keys and drives the pure
  # `Console.Tlon.Focus` SM over `tlon_layout` (h/l pane · H/L column · s section · Esc→terminal).
  # `focus` (persistent) and `tlon_layout` (derived per keypress, like center_live?) are supplied by
  # the cockpit only for this space; the guard keeps every other space on the leader path below. ---
  def handle(key, %{active_key: k, focus: %Focus{}} = state) when Space.workspace?(k), do: handle_tlon(key, state)

  # --- leader pending: Ctrl+Space was pressed; the next key is an console command. ---
  # Ctrl+Space again → send a LITERAL Ctrl+Space through (the prefix-twice convention), so an
  # app that binds it (emacs set-mark!) still gets it. Only with a live terminal to receive it.
  def handle(%{key: :space, ctrl: true}, %{leader_pending?: true, center_live?: true} = state),
    do: {%{state | leader_pending?: false}, {:forward, %{key: :space, ctrl: true}}}

  def handle(%{key: :space, ctrl: true}, %{leader_pending?: true} = state), do: {%{state | leader_pending?: false}, :none}

  # Esc cancels a pending prefix without acting — the escape hatch from a half-armed leader.
  def handle(%{key: :escape}, %{leader_pending?: true} = state), do: {%{state | leader_pending?: false}, :repaint}

  # Any other key while the prefix is armed → run the command, then clear the prefix. The command
  # table (`command/2`) is the single source of console's bindings, shared with the bare-key path.
  def handle(key, %{leader_pending?: true} = state) do
    {next, effect} = command(key, state)
    {%{next | leader_pending?: false}, effect}
  end

  # --- the leader: Ctrl+Space arms the next key as an console command. ---
  def handle(%{key: :space, ctrl: true}, state), do: {%{state | leader_pending?: true}, :repaint}

  # --- default: the center surface owns the keys. ---
  # A live terminal in the center → every key forwards to its PTY. The terminal is "normal mode";
  # you type into it immediately. (Ctrl+C lands here too → forwards as an interrupt, never a quit.)
  def handle(key, %{center_live?: true} = state), do: {state, {:forward, key}}

  # No live terminal (Orbis, or a placeholder before a session spawns) → console's nav bindings are
  # bare — the same command table the leader reaches, just without the prefix.
  def handle(key, state), do: command(key, state)

  # --- console's command table — one source of bindings, reached two ways: bare in a nav-default
  # space, or via the Ctrl+Space leader from inside a running terminal. ---

  # --- Orbis' delete confirm (author face, D2.5): a `d` on the cursor row arms; the SECOND `d`
  # (still armed on that SAME id — nothing else could have changed it, see the next clause)
  # confirms; literally any other key cancels. Both must precede EVERY other clause (even `q`) so
  # an armed delete can never be confirmed by a stale keypress. ---
  defp command(%{key: :char, char: "d"}, %{active_key: :orbis, pending_delete: id} = state) when not is_nil(id) do
    {Map.put(state, :pending_delete, nil), {:remove_workspace, id}}
  end

  defp command(_key, %{active_key: :orbis, pending_delete: id} = state) when not is_nil(id) do
    {Map.put(state, :pending_delete, nil), :repaint}
  end

  # --- the field editor (D2.4 Chunk 2a): `author_edit != nil` gates its own key table, ahead of
  # the list's `n`/`d`/`a`/Esc/h/l/j/k so editing and list-management never leak into each other. ---

  # `e` on the list's cursor workspace opens the editor at field 0. A no-op off the author face, on an
  # empty list, or while ALREADY editing (never re-arms onto a different cursor workspace mid-edit).
  defp command(%{key: :char, char: "e"}, %{active_key: :orbis} = state) do
    case {orbis_face(state), author_edit(state), Enum.at(author_workspaces(state), author_cursor(state))} do
      {:author, nil, %{id: id}} ->
        {Map.put(state, :author_edit, %{id: id, field: 0, sub: 0, mode: :field, knob: :model}), :repaint}

      _ ->
        {state, :none}
    end
  end

  # Field-list mode: j/k move the field cursor 0..3, clamped (no wrap).
  defp command(%{key: :char, char: "j"}, %{active_key: :orbis, author_edit: %{mode: :field} = edit} = state),
    do: {put_author_edit(state, %{edit | field: min(edit.field + 1, 3)}), :repaint}

  defp command(%{key: :down}, %{active_key: :orbis, author_edit: %{mode: :field} = edit} = state),
    do: {put_author_edit(state, %{edit | field: min(edit.field + 1, 3)}), :repaint}

  defp command(%{key: :char, char: "k"}, %{active_key: :orbis, author_edit: %{mode: :field} = edit} = state),
    do: {put_author_edit(state, %{edit | field: max(edit.field - 1, 0)}), :repaint}

  defp command(%{key: :up}, %{active_key: :orbis, author_edit: %{mode: :field} = edit} = state),
    do: {put_author_edit(state, %{edit | field: max(edit.field - 1, 0)}), :repaint}

  # Field-list mode: h/l cycle the type (field 0) / scope (field 1) ring against the LIVE workspace
  # (author_workspaces, threaded per keypress) and emit the edit immediately — no draft/commit step.
  # Fields 2/3 (paths/roster) have no ring — a no-op, matching the plan's "otherwise no-op".
  defp command(%{key: :char, char: "h"}, %{active_key: :orbis, author_edit: %{mode: :field} = edit} = state),
    do: {state, field_ring_edit(state, edit, -1)}

  defp command(%{key: :char, char: "l"}, %{active_key: :orbis, author_edit: %{mode: :field} = edit} = state),
    do: {state, field_ring_edit(state, edit, 1)}

  # Esc in field-list mode clears author_edit — back to the list.
  defp command(%{key: :escape}, %{active_key: :orbis, author_edit: %{mode: :field}} = state),
    do: {put_author_edit(state, nil), :repaint}

  # Field-list mode: Enter on fields 2/3 (paths/roster) drops into the sub-list. Fields 0/1's
  # rings already apply via h/l — nothing for Enter to open, a no-op.
  defp command(%{key: :enter}, %{active_key: :orbis, author_edit: %{mode: :field, field: f} = edit} = state)
       when f in [2, 3], do: {put_author_edit(state, %{edit | mode: :sub, sub: 0}), :repaint}

  defp command(%{key: :enter}, %{active_key: :orbis, author_edit: %{mode: :field}} = state), do: {state, :none}

  # Sub-list mode (D2.4 Chunk 2b/2c): j/k move `sub`, clamped to the field's LIVE list length
  # (paths/roster off author_workspaces, threaded per keypress — never stale).
  defp command(%{key: :char, char: "j"}, %{active_key: :orbis, author_edit: %{mode: :sub} = edit} = state),
    do: {put_author_edit(state, %{edit | sub: move_sub(state, edit, 1)}), :repaint}

  defp command(%{key: :down}, %{active_key: :orbis, author_edit: %{mode: :sub} = edit} = state),
    do: {put_author_edit(state, %{edit | sub: move_sub(state, edit, 1)}), :repaint}

  defp command(%{key: :char, char: "k"}, %{active_key: :orbis, author_edit: %{mode: :sub} = edit} = state),
    do: {put_author_edit(state, %{edit | sub: move_sub(state, edit, -1)}), :repaint}

  defp command(%{key: :up}, %{active_key: :orbis, author_edit: %{mode: :sub} = edit} = state),
    do: {put_author_edit(state, %{edit | sub: move_sub(state, edit, -1)}), :repaint}

  # Sub-list mode, field 2 (paths): `a` opens a `:new_path` add buffer (state.input, kind-agnostic
  # reuse of the printable-insert/Enter/Esc machinery, mirrors `:new_workspace`).
  defp command(%{key: :char, char: "a"}, %{active_key: :orbis, author_edit: %{mode: :sub, field: 2, id: id}} = state),
    do: {%{state | input: %{kind: :new_path, buffer: "", cursor: 0, workspace_id: id}}, :repaint}

  # Sub-list mode, field 2 (paths): x/d removes the sub-selected path immediately — no confirm
  # (unlike the list's whole-workspace delete, an add re-creates it; the two-key arm is reserved for
  # destroying a WORKSPACE).
  defp command(
         %{key: :char, char: c},
         %{active_key: :orbis, author_edit: %{mode: :sub, field: 2, id: id, sub: sub}} = state
       )
       when c in ["x", "d"],
       do: {state, {:edit_workspace, id, %{paths: List.delete_at(workspace_field(state, id, :paths), sub)}}}

  # Sub-list mode, field 3 (roster): `a` opens a `:new_roster` add flow — the same `state.input`
  # kit as `:new_path`, plus an `archetype` ring (Profiles.archetypes/0's keys, cycled by h/l
  # below) armed at the FIRST archetype, mirroring `:new_workspace`'s `template`.
  defp command(%{key: :char, char: "a"}, %{active_key: :orbis, author_edit: %{mode: :sub, field: 3, id: id}} = state) do
    input = %{
      kind: :new_roster,
      buffer: "",
      cursor: 0,
      workspace_id: id,
      archetype: List.first(Map.keys(Profiles.archetypes()))
    }

    {%{state | input: input}, :repaint}
  end

  # Sub-list mode, field 3 (roster): x/d removes the sub-selected entry immediately — same no-confirm
  # reasoning as field 2's paths removal.
  defp command(
         %{key: :char, char: c},
         %{active_key: :orbis, author_edit: %{mode: :sub, field: 3, id: id, sub: sub}} = state
       )
       when c in ["x", "d"],
       do: {state, {:edit_workspace, id, %{roster: List.delete_at(workspace_field(state, id, :roster), sub)}}}

  # Sub-list mode, field 3 (roster) only: `Tab` flips the knob (:model <-> :yolo) Enter/Space
  # applies (D2.4 Chunk 2b, absorbs Settings' field-flip). Guarded to field 3 (paths has no knob)
  # and must precede the generic Tab-switches-space clauses below.
  defp command(%{key: :tab}, %{active_key: :orbis, author_edit: %{mode: :sub, field: 3} = edit} = state),
    do: {put_author_edit(state, Map.put(edit, :knob, flip_knob(edit_knob(edit)))), :repaint}

  # Sub-list mode, field 3 (roster) only: Enter/Space applies the active knob to the sub-selected
  # coworker (the Settings modal's apply, now here) — `name` off the LIVE roster (workspace_field/2,
  # same source `a`/`x`/`d` read). A vanished entry (sub past the shrunk list) is a no-op.
  defp command(%{key: :enter}, %{active_key: :orbis, author_edit: %{mode: :sub, field: 3}} = state),
    do: roster_knob_apply(state)

  defp command(%{key: :char, char: " "}, %{active_key: :orbis, author_edit: %{mode: :sub, field: 3}} = state),
    do: roster_knob_apply(state)

  defp command(%{key: :space}, %{active_key: :orbis, author_edit: %{mode: :sub, field: 3}} = state),
    do: roster_knob_apply(state)

  # Sub-list mode: Esc steps back to the field list (mode: :field), field unchanged.
  defp command(%{key: :escape}, %{active_key: :orbis, author_edit: %{mode: :sub} = edit} = state),
    do: {put_author_edit(state, %{edit | mode: :field}), :repaint}

  # The list's n/d/a verbs are blocked while author_edit is set — editing is its own mode; falling
  # through here (rather than to the list clauses below) keeps Chunk 1's create/delete/toggle
  # list-only, untouched when author_edit is nil.
  defp command(%{key: :char, char: c}, %{active_key: :orbis, author_edit: %{}} = state) when c in ["n", "d", "a"],
    do: {state, :none}

  defp command(%{key: :char, char: "q"}, state), do: {state, :quit}

  # `n` in Orbis' author face opens the create-workspace flow (a template ring + a name buffer, D2.3)
  # instead of the thread composer; every other space (and Orbis' survey face) keeps `n` == new
  # thread. `orbis_face/1` isn't guard-safe (a plain function, not a `defguard`), so the branch is
  # in the body, not the clause head.
  defp command(%{key: :char, char: "n"}, %{active_key: :orbis} = state) do
    if orbis_face(state) == :author do
      input = %{kind: :new_workspace, buffer: "", cursor: 0, template: List.first(WorkspaceTemplates.names())}
      {%{state | input: input}, :repaint}
    else
      {%{state | input: %{kind: :new_thread, buffer: "", cursor: 0}}, :repaint}
    end
  end

  # `n` focuses the persistent new-thread input band (2026-09-01) — a shortcut to the same input you
  # can click. Type a title, Enter creates (the :new_thread Enter clause → {:create_thread, …}).
  defp command(%{key: :char, char: "n"}, state),
    do: {%{state | input: %{kind: :new_thread, buffer: "", cursor: 0}}, :repaint}

  # `:` opens the tertius command line from any panel (Slice 1) — a vim-style command prompt for
  # meta-intent ("tell @x …", "file a ticket …", "remember …"). The generic input machinery below
  # handles the typing/cursor; Enter (above) dispatches to the orchestrator.
  defp command(%{key: :char, char: ":"}, state),
    do: {%{state | input: %{kind: :orchestrate, buffer: "", cursor: 0}}, :repaint}

  # Space toggles the fold on the focused card (the standard fold-nav paradigm: z/Enter/Space).
  # Tertius is focused by click or `:`.
  defp command(%{key: :space}, state), do: {state, {:toggle_fold}}

  # `z` folds/unfolds the active thread card in the stack; `Z` zooms one thread full-screen (a real
  # zoom over the stack), `Z` again to go back (Slice 3).
  defp command(%{key: :char, char: "z"}, state), do: {state, {:toggle_fold}}
  defp command(%{key: :char, char: "Z"}, state), do: {state, {:zoom_thread}}
  defp command(%{key: :char, char: "+"}, state), do: {state, {:zoom_thread}}

  # `g`/`G` jump the stack cursor to the top/bottom thread (vim/less convention).
  defp command(%{key: :char, char: "g"}, %{active_key: key} = state) when key != :orbis, do: jump(state, :first)
  defp command(%{key: :char, char: "G"}, %{active_key: key} = state) when key != :orbis, do: jump(state, :last)

  # `a` (bare) toggles Orbis' author face on; Esc (below, no input open) toggles it back off.
  # Modifier-guarded like `c`/`m` — Ctrl/Shift/Alt+A never fires this.
  defp command(%{key: :char, char: "a"} = k, %{active_key: :orbis} = state)
       when not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt),
       do: {state, {:toggle_orbis_face}}

  # Esc steps the author face back to the survey. Only reached with `input` nil (the input-mode
  # Esc clause up top intercepts first while typing) — a bare Esc on the survey face is a no-op,
  # nothing to close.
  defp command(%{key: :escape}, %{active_key: :orbis} = state) do
    if orbis_face(state) == :author, do: {state, {:toggle_orbis_face}}, else: {state, :none}
  end

  # `d` on the author face's cursor workspace arms the delete confirm (D2.5) — the FIRST press; the
  # armed-state clauses above own the second press and every cancel. A no-op off the author face
  # (nothing to delete from the survey) or on an empty list.
  defp command(%{key: :char, char: "d"}, %{active_key: :orbis} = state) do
    case {orbis_face(state), Enum.at(author_workspaces(state), author_cursor(state))} do
      {:author, %{id: id, name: name}} -> {state, {:arm_delete, id, name}}
      _ -> {state, :none}
    end
  end

  # `c` — the composer: post to the thread `composer_thread_id` (the focused thread in Orbis, the
  # machine thread in Tlön — resolved per keypress by the cockpit, like center_live?).
  # nil (empty board / no machine thread) → nothing to post on. Bare `c` only (modifiers nil):
  # Ctrl+C is unbound (never a quit) and must not open a composer. Bare in a nav space or via the
  # leader from a terminal.
  defp command(%{key: :char, char: "c"} = k, %{composer_thread_id: id} = state)
       when not is_nil(id) and not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt),
       do: {%{state | input: %{kind: :compose, thread_id: id, buffer: "", cursor: 0}}, :repaint}

  # `m` — cycle the active space's coworker driver model (the SETTINGS panel's one verb). Only
  # in a space WITH a coworker (elsewhere there's nothing to point the ring at), and bare `m`
  # only, same modifier discipline as `c`.
  defp command(%{key: :char, char: "m"} = k, %{active_key: key} = state)
       when not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt) do
    case Space.fetch(key).coworker do
      nil -> {state, :none}
      profile -> {state, {:cycle_coworker_model, profile}}
    end
  end

  # Enter in the Orbis survey (focus == :survey) zooms into the CURSOR row's own workspace id — the
  # god-view → workspace zoom, resolved from `survey_cursor` against the live workspaces list (D0.3 gives
  # every row an `id`). With focus on :threads, Enter has no verb here (falls to the plain no-op
  # below, same as "elsewhere") — the thread list has nothing for Enter to do (Slice 1). The
  # author face has no Enter verb yet either (opening the field editor is Chunk 2) — a no-op, not
  # an accidental zoom into the cursor workspace's space.
  defp command(%{key: :enter}, %{active_key: :orbis} = state) do
    cond do
      orbis_face(state) == :author ->
        {state, :none}

      orbis_focus(state) == :survey ->
        case Enum.at(survey_workspaces(state), survey_cursor(state)) do
          %{id: id} -> {state, {:switch_space, id}}
          _ -> {state, :none}
        end

      true ->
        {state, :none}
    end
  end

  # Enter has no top-level verb elsewhere since the Slice 0 collapse: the Sessions space (its only
  # home — the one center that could show a spawned per-thread PTY) is gone, so Enter is a plain
  # no-op. In Tlön, Enter is routed by handle_tlon (commit-the-preview), never reaching this clause.
  defp command(%{key: :enter}, state), do: {state, :none}

  defp command(%{key: :tab, shift: true}, state), do: switch(state, :prev)
  defp command(%{key: :tab}, state), do: switch(state, :next)

  # `h`/`l` toggle Orbis' focus between the survey (per-row cursor) and the thread list (the
  # existing `focused_id` nav) — Orbis-only; in a Workspace, h/l belong to Focus pane-nav
  # (`handle_tlon`), never reaching this table. Bare keys only (same modifier discipline as
  # `a`/`c`/`m`) — a workspace-guarded Alt chord that fell past the Global Alt block must not leak
  # into Orbis nav.
  defp command(%{key: :char, char: "h"} = k, %{active_key: :orbis} = state)
       when not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt),
       do: {toggle_orbis_focus(state), :repaint}

  defp command(%{key: :char, char: "l"} = k, %{active_key: :orbis} = state)
       when not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt),
       do: {toggle_orbis_focus(state), :repaint}

  # j/k/↑/↓ route by `orbis_focus`: :survey moves the survey's per-row cursor (clamped, no wrap);
  # :threads keeps the pre-existing thread-focus move. Orbis-only (Workspace j/k is `handle_tlon`'s).
  defp command(%{key: :up}, %{active_key: :orbis} = state), do: move_orbis(state, -1)

  defp command(%{key: :char, char: "k"} = k, %{active_key: :orbis} = state)
       when not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt), do: move_orbis(state, -1)

  defp command(%{key: :down}, %{active_key: :orbis} = state), do: move_orbis(state, 1)

  defp command(%{key: :char, char: "j"} = k, %{active_key: :orbis} = state)
       when not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt), do: move_orbis(state, 1)

  defp command(%{key: :up}, state), do: move(state, -1)

  defp command(%{key: :char, char: "k"} = k, state)
       when not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt), do: move(state, -1)

  defp command(%{key: :down}, state), do: move(state, 1)

  defp command(%{key: :char, char: "j"} = k, state)
       when not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt), do: move(state, 1)

  # Anything else (Ctrl+C, F-keys, page-up…) is unbound — a no-op, never a quit.
  defp command(_key, state), do: {state, :none}

  # --- Tlön's delete confirm (mirrors Orbis'): `d` arms on the focused pane's selection (the
  # cockpit resolves the target + flashes), the SECOND `d` — still armed — confirms with the
  # ARM-TIME target; literally any other key cancels. Both precede every other clause so a stale
  # keypress can never confirm. ---
  defp handle_tlon(%{key: :char, char: "d"}, %{tlon_delete: target} = state) when not is_nil(target),
    do: {%{state | tlon_delete: nil}, {:tlon_delete, target}}

  defp handle_tlon(_key, %{tlon_delete: target} = state) when not is_nil(target),
    do: {%{state | tlon_delete: nil}, :repaint}

  # --- Tlön focus routing. Ctrl+Space toggles the terminal; in the terminal every key forwards;
  # out of it the nav keys drive the focus SM and the bare commands (quit, space-switch, composer,
  # driver ring) stay reachable. Anything else no-ops — nav mode never leaks a key to tmux. ---
  defp handle_tlon(%{key: :space, ctrl: true}, state), do: {focus_intent(state, :toggle_terminal), :repaint}

  # The thread stack is the shown center (center_view :chat, Slice 3) and it's the focused surface
  # (in_terminal? — the center owns the keys): drive the STACK directly instead of forwarding to a
  # tmux client that isn't there. j/k/↑↓ move the cursor, z/Space fold, Z/+ zoom, g/G ends. `:`
  # focuses the tertius line from here too. This precedes the generic forward clause below, so the
  # terminal path (center_view :terminal) is untouched.
  defp handle_tlon(%{key: :char, char: ":"}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state),
    do: {%{state | input: %{kind: :orchestrate, buffer: "", cursor: 0}}, :repaint}

  defp handle_tlon(%{key: :char, char: "j"}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: stack_move(state, 1)
  defp handle_tlon(%{key: :char, char: "k"}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: stack_move(state, -1)
  defp handle_tlon(%{key: :down}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: stack_move(state, 1)
  defp handle_tlon(%{key: :up}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: stack_move(state, -1)
  defp handle_tlon(%{key: :char, char: "g"}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: stack_jump(state, :first)
  defp handle_tlon(%{key: :char, char: "G"}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: stack_jump(state, :last)
  defp handle_tlon(%{key: :char, char: "z"}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: {state, {:toggle_fold}}
  defp handle_tlon(%{key: :space}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: {state, {:toggle_fold}}
  defp handle_tlon(%{key: :char, char: "Z"}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: {state, {:zoom_thread}}
  defp handle_tlon(%{key: :char, char: "+"}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: {state, {:zoom_thread}}

  # `n` (focus the new-thread band) and `c` (reply to the focused card) are the create/write verbs —
  # they drive the chat directly here (like j/k/z), so they work while you're looking at the stack,
  # not only via the Alt chords. Precede the forward clause below.
  defp handle_tlon(%{key: :char, char: "n"} = k, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: command(k, state)
  defp handle_tlon(%{key: :char, char: "c"} = k, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: command(k, state)
  # `d` arms the two-key delete for the FOCUSED thread card (the second `d` is caught by the armed
  # clause at the top of handle_tlon). This restores thread-delete, lost when the MachineChat TUI and
  # the LEAVES rail panel — the old delete surfaces — were retired.
  defp handle_tlon(%{key: :char, char: "d"}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state), do: {state, :stack_delete_arm}
  defp handle_tlon(key, %{focus: %Focus{in_terminal?: true}} = state), do: {state, {:forward, key}}

  # Esc steps back one level: close an open detail first, else drop out of nav into the terminal.
  defp handle_tlon(%{key: :escape}, %{focus: %Focus{detail?: true}} = state),
    do: {focus_intent(state, :close_detail), :repaint}

  defp handle_tlon(%{key: :escape}, state), do: {put_in(state.focus.in_terminal?, true), :repaint}
  # Nav v2: pane digits are gone — the rail is walked with h/l. (Bare digits are no longer a jump.)
  defp handle_tlon(%{key: :char, char: "l"}, state), do: {focus_intent(state, :pane_next), :repaint}
  defp handle_tlon(%{key: :char, char: "h"}, state), do: {focus_intent(state, :pane_prev), :repaint}
  defp handle_tlon(%{key: :char, char: "L"}, state), do: {focus_intent(state, :col_right), :repaint}
  defp handle_tlon(%{key: :char, char: "H"}, state), do: {focus_intent(state, :col_left), :repaint}
  # j/k move the item cursor within the focused pane; Enter opens its selection's detail in MAIN.
  # (Leaves' Enter is a space-jump, not a detail — Phase 4 special-cases it ahead of this clause.)
  # Over a WINDOW-BEARING pane (Leaves — each leaf maps to a live Workspace tmux window) the move emits
  # `:tlon_preview` so the cockpit re-points the center to the hovered window (a hover, not a commit
  # — focus stays in nav); anywhere else it's a plain `:repaint`.
  defp handle_tlon(%{key: :char, char: "j"}, state), do: nav_move(state, :item_next)
  defp handle_tlon(%{key: :char, char: "k"}, state), do: nav_move(state, :item_prev)
  defp handle_tlon(%{key: :down}, state), do: nav_move(state, :item_next)
  defp handle_tlon(%{key: :up}, state), do: nav_move(state, :item_prev)
  # Enter is contextual: the cockpit resolves the focused pane and either opens a MAIN detail
  # (Commits/Memory) or jumps to a thread (Leaves) — the keymap can't, it lacks the reads.
  defp handle_tlon(%{key: :enter}, state), do: {state, :tlon_enter}
  # a/r act on the selected pending habit (Memory's habits section) — the cockpit resolves which
  # --- input-buffer cursor math (graphemes, not bytes) — what makes the composer/new-thread box
  # habit from the focus + reads and no-ops if the focus isn't on a habit. Approving writes it into
  # behave like a normal text field instead of an append-only log. `input.cursor` defaults to the
  # the recall floor; rejecting drops it.
  # buffer's end when absent (a state built before this field existed, or by an older test),
  # matching the old append-always behaviour exactly until something actually moves the cursor.

  defp handle_tlon(%{key: :char, char: "a"}, state), do: {state, {:habit_action, :approve}}
  defp handle_tlon(%{key: :char, char: "r"}, state), do: {state, {:habit_action, :reject}}
  # `y` — semantic yank: the cockpit resolves the focused pane's real text (sha/fact/title) and
  # writes it to the clipboard via OSC 52. Detail-open yanks the detail body.
  defp handle_tlon(%{key: :char, char: "y"}, state), do: {state, :yank}
  # `d` — the operator's delete verb: the cockpit resolves the focused pane's selection (MEMORY
  # fact → forget, LEAVES leaf → window + thread) and arms the two-key confirm above.
  defp handle_tlon(%{key: :char, char: "d"}, state), do: {state, :tlon_delete_arm}
  # C3.4 reshuffle: Tab/Shift+Tab switch spaces (matching the command level) instead of cycling
  # sections — Shift+Tab must precede the bare :tab clause below, which also matches it.
  defp handle_tlon(%{key: :tab, shift: true}, state), do: switch(state, :prev)
  defp handle_tlon(%{key: :tab}, state), do: switch(state, :next)
  # `s` took over section-cycle (freed by Tab) — habits approve/reject needs focus.section == 1,
  # so the section must stay reachable.
  defp handle_tlon(%{key: :char, char: "s"}, state), do: {focus_intent(state, :section_next), :repaint}
  defp handle_tlon(%{key: :char, char: "q"}, state), do: {state, :quit}
  # The center [chat]|[terminal] toggle (reshape slice D): flip which face the Workspace center shows.
  defp handle_tlon(%{key: :char, char: "v"}, state), do: {state, :toggle_center_view}
  defp handle_tlon(%{key: :char, char: "n"} = k, state), do: command(k, state)
  defp handle_tlon(%{key: :char, char: "c"} = k, state), do: command(k, state)
  defp handle_tlon(%{key: :char, char: "m"} = k, state), do: command(k, state)
  defp handle_tlon(_key, state), do: {state, :none}

  defp focus_intent(state, intent), do: %{state | focus: Focus.handle(state.focus, state.tlon_layout, intent)}

  # A digit key to a 1-based position: "1".."9" → 1..9, "0" → 10 (the super+1..0 idiom).
  defp digit_pos("0"), do: 10
  defp digit_pos(d), do: String.to_integer(d)

  # A global Alt chord consumes any armed leader — without this, Ctrl+Space then an Alt chord
  # leaves the prefix stuck (the next Ctrl+Space would silently disarm instead of arming).
  defp clear_leader(state), do: Map.put(state, :leader_pending?, false)

  # Alt+h/j/k/l: directional pane movement, implicit nav (Focus intents no-op in-terminal, so
  # drop out of the terminal first).
  @alt_moves %{"h" => :col_left, "l" => :col_right, "j" => :pane_next, "k" => :pane_prev}

  defp alt_move(state, c) do
    focus = %{state.focus | in_terminal?: false}
    %{state | focus: Focus.handle(focus, state.tlon_layout, @alt_moves[c])}
  end

  # Move the item cursor, then decide the effect: over a window-bearing pane the cockpit should
  # preview (re-point the center) — `:tlon_preview`; elsewhere a plain `:repaint`. The cockpit
  # re-checks and no-ops the re-point if the hovered leaf has no live window.
  defp nav_move(state, intent) do
    next = focus_intent(state, intent)
    if window_bearing?(next), do: {next, :tlon_preview}, else: {next, :repaint}
  end

  # A pane whose selection maps to a live Workspace tmux window — Leaves today (each leaf → its lead's
  # window). Only these drive the center preview.
  defp window_bearing?(state), do: Focus.focused_pane(state.focus, state.tlon_layout) == Panel.Leaves

  defp switch(state, dir) do
    space =
      if dir == :next,
        do: Space.next(state.active_key),
        else: Space.prev(state.active_key)

    {%{state | active_key: space.key}, :repaint}
  end

  defp move(%{threads: []} = state, _dir), do: {state, :none}

  defp move(state, dir) do
    ids = Enum.map(state.threads, & &1.id)
    i = Enum.find_index(ids, &(&1 == state.focused_id)) || 0
    new_id = Enum.at(ids, min(max(i + dir, 0), length(ids) - 1))
    {%{state | focused_id: new_id}, :repaint}
  end

  # `g`/`G`: jump the cursor to the first/last thread (top/bottom of the stack).
  defp jump(%{threads: []} = state, _), do: {state, :none}
  defp jump(state, :first), do: {%{state | focused_id: hd(state.threads).id}, :repaint}
  defp jump(state, :last), do: {%{state | focused_id: List.last(state.threads).id}, :repaint}

  # The thread-stack cursor move/jump in the Tlön (workspace) context — same as move/2 + jump/2 but
  # returning from handle_tlon (the workspace routes keys here, not through command/2).
  defp stack_move(%{threads: []} = state, _dir), do: {state, :none}

  defp stack_move(state, dir) do
    ids = Enum.map(state.threads, & &1.id)
    i = Enum.find_index(ids, &(&1 == state.focused_id)) || 0
    {%{state | focused_id: Enum.at(ids, min(max(i + dir, 0), length(ids) - 1))}, :repaint}
  end

  defp stack_jump(%{threads: []} = state, _), do: {state, :none}
  defp stack_jump(state, :first), do: {%{state | focused_id: hd(state.threads).id}, :repaint}
  defp stack_jump(state, :last), do: {%{state | focused_id: List.last(state.threads).id}, :repaint}

  # Dispatch Orbis' j/k/↑/↓: the author face's own cursor takes priority over `orbis_focus`
  # (survey/threads is meaningless while the author face is showing — Panel.Author, not Overview);
  # else the survey's per-row cursor, or the pre-existing thread move (`move/2`, unchanged — keeps
  # the composer's `c` target working).
  defp move_orbis(state, dir) do
    cond do
      orbis_face(state) == :author -> move_author_cursor(state, dir)
      orbis_focus(state) == :survey -> move_survey(state, dir)
      true -> move(state, dir)
    end
  end

  # Clamp `survey_cursor` into `0..length(workspaces) - 1` — no wrap, same edge-clamp discipline as
  # `move/2`. Zero workspaces clamps to 0 (harmless; Enter no-ops on an empty survey).
  # `Map.put/3`, not `%{state | ...}` — that raises KeyError when `:survey_cursor` is absent (an
  # older test's literal state map, built before this field existed), same tolerance as the
  # composer's `insert_at/2`.
  defp move_survey(state, dir) do
    max_idx = max(length(survey_workspaces(state)) - 1, 0)
    cursor = (survey_cursor(state) + dir) |> max(0) |> min(max_idx)
    {Map.put(state, :survey_cursor, cursor), :repaint}
  end

  defp toggle_orbis_focus(state) do
    next = if orbis_focus(state) == :survey, do: :threads, else: :survey
    Map.put(state, :orbis_focus, next)
  end

  # Clamp `author_cursor` into `0..length(author_workspaces) - 1` — same edge-clamp discipline as
  # `move_survey/2`.
  defp move_author_cursor(state, dir) do
    max_idx = max(length(author_workspaces(state)) - 1, 0)
    cursor = (author_cursor(state) + dir) |> max(0) |> min(max_idx)
    {Map.put(state, :author_cursor, cursor), :repaint}
  end

  # h/l cycle `input.template` through `WorkspaceTemplates.names/0`, wrapping (a ring, not a clamp) —
  # the create flow always has a template armed, so there's no "past the end" to guard.
  defp cycle_template(%{template: template} = input, dir) do
    names = WorkspaceTemplates.names()
    i = Enum.find_index(names, &(&1 == template)) || 0
    Map.put(input, :template, Enum.at(names, rem(i + dir + length(names), length(names))))
  end

  # h/l cycle `input.archetype` through `Profiles.archetypes/0`'s keys, wrapping — same ring
  # idiom as `cycle_template/2`, for the roster add flow's archetype picker.
  defp cycle_archetype(%{archetype: archetype} = input, dir) do
    keys = Map.keys(Profiles.archetypes())
    i = Enum.find_index(keys, &(&1 == archetype)) || 0
    Map.put(input, :archetype, Enum.at(keys, rem(i + dir + length(keys), length(keys))))
  end

  # Defaults tolerate a state map built before these fields existed (an older test's literal
  # state) — `:survey`/`0`, matching the cockpit's init-state defaults.
  defp orbis_focus(state), do: Map.get(state, :orbis_focus, :survey)
  defp survey_cursor(state), do: Map.get(state, :survey_cursor, 0)
  defp orbis_face(state), do: Map.get(state, :orbis_face, :survey)
  defp author_cursor(state), do: Map.get(state, :author_cursor, 0)
  defp author_edit(state), do: Map.get(state, :author_edit)
  defp put_author_edit(state, edit), do: Map.put(state, :author_edit, edit)

  # h/l on field 0 (type) / field 1 (scope): find the CURRENT workspace (author_workspaces, threaded per
  # keypress — never stale), step its ring value by `dir` (wrapping — a ring, not a clamp, same
  # idiom as `cycle_template/2`), and emit the edit. A workspace that's vanished (deleted mid-edit,
  # the Bus race is real but rare) or a field with no ring (2/3) is a no-op.
  defp field_ring_edit(state, %{id: id, field: field}, dir) when field in [0, 1] do
    case Enum.find(author_workspaces(state), &(&1.id == id)) do
      %{} = workspace ->
        {key, ring} = if field == 0, do: {:type, @type_ring}, else: {:scope, @scope_ring}
        current = Map.get(workspace, key)
        i = Enum.find_index(ring, &(&1 == current)) || 0
        next = Enum.at(ring, rem(i + dir + length(ring), length(ring)))
        {:edit_workspace, id, %{key => next}}

      _ ->
        :none
    end
  end

  defp field_ring_edit(_state, _edit, _dir), do: :none

  # Sub-list mode's j/k: clamp `sub` into `0..length(field's live list) - 1`, no wrap — same
  # edge-clamp discipline as `move_author_cursor/2`/`move_survey/2`.
  defp move_sub(state, %{id: id, field: field, sub: sub}, dir) do
    max_idx = state |> workspace_field(id, sub_key(field)) |> length() |> Kernel.-(1) |> max(0)
    (sub + dir) |> max(0) |> min(max_idx)
  end

  defp sub_key(2), do: :paths
  defp sub_key(3), do: :roster

  # The roster sub-editor's knob (D2.4 Chunk 2b) — tolerant read (default :model) so a state built
  # before this field existed (an older test's literal author_edit) still works.
  defp edit_knob(edit), do: Map.get(edit, :knob, :model)
  defp flip_knob(:model), do: :yolo
  defp flip_knob(:yolo), do: :model

  # Resolve the sub-selected roster entry's `name` off the LIVE workspace and emit the apply effect —
  # a vanished entry (deleted mid-edit, or `sub` past the shrunk list) is a no-op, not a crash.
  defp roster_knob_apply(%{author_edit: %{id: id, sub: sub} = edit} = state) do
    case state |> workspace_field(id, :roster) |> Enum.at(sub) do
      %{"name" => name} -> {state, {:coworker_knob, name, edit_knob(edit)}}
      _ -> {state, :none}
    end
  end

  # The CURRENT value of one list-shaped field (`:paths`/`:roster`) off the LIVE workspace
  # (author_workspaces, threaded per keypress — never stale). A vanished workspace (deleted mid-edit)
  # degrades to `[]` rather than crashing the reducer.
  defp workspace_field(state, id, key) do
    case Enum.find(author_workspaces(state), &(&1.id == id)) do
      nil -> []
      workspace -> Map.get(workspace, key) || []
    end
  end

  # The live workspaces list Orbis' survey cursor/Enter resolve against — the same cached
  # `Console.Orbis.rollup/0` the cockpit's `orbis_workspaces/1` reads (`state.leaves.workspaces`). Kept local
  # (not a call into `Console.Cockpit`) so the keymap stays a pure reducer over its passed-in state.
  defp survey_workspaces(state) do
    case Map.get(state, :leaves) do
      %{workspaces: workspaces} -> workspaces
      _ -> []
    end
  end

  # The author face's own workspace list — `Console.Workspaces.all/0`, threaded in per keypress by the
  # cockpit (like `composer_thread_id`) so this stays a pure reducer with no server call of its
  # own. Distinct from `survey_workspaces/1` (the Orbis rollup, which is `nil` whenever there are no
  # MACHINE THREADS yet — a freshly-created, thread-less workspace would vanish from that list even
  # though it's a real row here).
  defp author_workspaces(state), do: Map.get(state, :author_workspaces, [])

  defp cursor_of(%{cursor: c}), do: c
  defp cursor_of(%{buffer: buffer}), do: String.length(buffer)

  # `Map.merge/2`, NOT the `%{input | ...}` update syntax — that raises KeyError when :cursor is
  # absent (an older test's literal input map, built before this field existed), and this must
  # tolerate that same as `cursor_of/1` does.
  defp insert_at(%{buffer: buffer} = input, text) do
    cursor = cursor_of(input)
    {before, aft} = split_at(buffer, cursor)
    Map.merge(input, %{buffer: before <> text <> aft, cursor: cursor + String.length(text)})
  end

  defp delete_before_cursor(%{buffer: buffer} = input) do
    cursor = cursor_of(input)

    if cursor <= 0 do
      Map.put(input, :cursor, 0)
    else
      {before, aft} = split_at(buffer, cursor)
      Map.merge(input, %{buffer: String.slice(before, 0..-2//1) <> aft, cursor: cursor - 1})
    end
  end

  defp move_cursor(%{buffer: buffer} = input, delta) do
    cursor = (cursor_of(input) + delta) |> max(0) |> min(String.length(buffer))
    Map.put(input, :cursor, cursor)
  end

  # Home/End act on the CURRENT line of a multiline buffer, not the whole thing — the line is
  # whatever's between the nearest "\n" before/after the cursor (buffer edges stand in when there
  # isn't one).
  defp cursor_home(%{buffer: buffer} = input), do: Map.put(input, :cursor, line_start_offset(buffer, cursor_of(input)))

  # The offset where the CURRENT line begins — shared by Home/Ctrl+A and Ctrl+U (kill-to-line-start
  # needs the same boundary Home jumps the cursor to).
  defp line_start_offset(buffer, cursor) do
    {before, _} = split_at(buffer, cursor)
    line = before |> String.split("\n") |> List.last()
    cursor - String.length(line)
  end

  # Ctrl+U: delete everything on the current line from its start up to the cursor. `before` is
  # buffer[0, cursor) already (from split_at), so slicing it to `start` (also measured from 0)
  # keeps everything before the line, drops everything the line had typed so far.
  defp kill_to_line_start(%{buffer: buffer} = input) do
    cursor = cursor_of(input)
    start = line_start_offset(buffer, cursor)
    {before, aft} = split_at(buffer, cursor)
    Map.merge(input, %{buffer: String.slice(before, 0, start) <> aft, cursor: start})
  end

  # Ctrl+W: delete the word behind the cursor — readline's unix-word-rubout. Walk `before`
  # backwards past trailing whitespace, then past the run of non-whitespace (the word), and keep
  # whatever's left.
  defp kill_word_backward(%{buffer: buffer} = input) do
    cursor = cursor_of(input)
    {before, aft} = split_at(buffer, cursor)

    {_ws, rest} =
      before |> String.graphemes() |> Enum.reverse() |> Enum.split_while(&(&1 in [" ", "\t", "\n"]))

    {_word, kept_reversed} = Enum.split_while(rest, &(&1 not in [" ", "\t", "\n"]))
    kept = kept_reversed |> Enum.reverse() |> Enum.join()
    Map.merge(input, %{buffer: kept <> aft, cursor: String.length(kept)})
  end

  defp cursor_end(%{buffer: buffer} = input), do: Map.put(input, :cursor, line_end_offset(buffer, cursor_of(input)))

  # The offset where the CURRENT line ends — shared by End/Ctrl+E and Ctrl+K (kill-to-line-end
  # needs the same boundary End jumps the cursor to).
  defp line_end_offset(buffer, cursor) do
    {_, aft} = split_at(buffer, cursor)

    line =
      case String.split(aft, "\n", parts: 2) do
        [first, _] -> first
        [first] -> first
      end

    cursor + String.length(line)
  end

  # Ctrl+K: delete everything on the current line from the cursor to its end (readline's
  # kill-line), leaving the cursor where it was.
  defp kill_to_line_end(%{buffer: buffer} = input) do
    cursor = cursor_of(input)
    end_offset = line_end_offset(buffer, cursor)
    {before, aft} = split_at(buffer, end_offset)
    kept_before = String.slice(before, 0, cursor)
    Map.put(input, :buffer, kept_before <> aft)
  end

  # Up/Down: move to the same COLUMN one line up/down (clamped to that line's length), the usual
  # text-editor contract. No line in that direction (top/bottom already) → no-op.
  defp move_line(%{buffer: buffer} = input, dir) do
    lines = String.split(buffer, "\n")
    {line_idx, col} = line_position(lines, cursor_of(input))
    target_idx = line_idx + dir

    if target_idx < 0 or target_idx >= length(lines) do
      input
    else
      target_line = Enum.at(lines, target_idx)
      new_col = min(col, String.length(target_line))
      Map.put(input, :cursor, line_start(lines, target_idx) + new_col)
    end
  end

  # Which line the cursor is on and its column within that line, walking lines left-to-right.
  defp line_position(lines, cursor) do
    Enum.reduce_while(lines, {0, cursor}, fn line, {idx, remaining} ->
      len = String.length(line)

      if remaining <= len,
        do: {:halt, {idx, remaining}},
        else: {:cont, {idx + 1, remaining - len - 1}}
    end)
  end

  # The cursor offset where `lines[target_idx]` begins — the sum of every earlier line's length
  # plus its trailing "\n".
  defp line_start(lines, target_idx) do
    lines |> Enum.take(target_idx) |> Enum.reduce(0, fn line, acc -> acc + String.length(line) + 1 end)
  end

  defp split_at(buffer, cursor) do
    graphemes = String.graphemes(buffer)
    {before, aft} = Enum.split(graphemes, cursor)
    {Enum.join(before), Enum.join(aft)}
  end
end
