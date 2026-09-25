defmodule Console.Keymap do
  @moduledoc """
  The cockpit's keyhandling as a **pure reducer** (design §8): `(key_event, state) → {new_state,
  effect}`, with no TTY, no tmux, and no paint. Extracting the decision from the side effect is
  what makes every binding testable headlessly (`Console.KeymapTest`) — the `Console.Cockpit`
  GenServer stays a thin interpreter of the returned effect.

  **Input model — tmux-style** (see `docs/plans/2026-08-16-aleph-tmux-style-input.md`): the center
  surface owns the keys by default. A **live terminal** in the center forwards every key to its PTY
  (the terminal is "normal mode"); `Ctrl+Space` is the STICKY toggle in and out of it, handled by
  `handle_tlon/2`. NOT Ctrl+B: that's tmux's prefix, and the Tlön center is literal tmux — Ctrl+B
  forwards like any other key so `C-b 2` reaches the real thing. (Ctrl+Space arrives as Kitty CSI-u
  `\\e[32;5u` → `%{key: :space, ctrl: true}` under the disambiguate mode the cockpit arms on the host.)

  **The arm-the-next-key leader is GONE** (UX slice 2). It was unreachable: the routing clause
  `handle(key, %{active_key: k, focus: %Focus{}}) when Space.workspace?(k)` sends every live
  keypress to `handle_tlon/2`, `Space.workspace?/1` is `is_integer/1` (satisfied even by the
  server-down sentinel `0`), and the cockpit always carries a `Focus` — so the prefix clauses below
  it were reached only by tests. Its verbs live in `Console.Verbs`, listed with a sentence each in
  the `^⇧P` command palette, which is the discoverable door a hidden prefix never was.

  **Two global chords** open the overlays of slice 2: `^⇧K` the switcher (go to any workspace,
  channel or thread) and `^⇧P` the palette. Ctrl+Shift+letter because nothing in a terminal binds
  it — a legacy terminal cannot encode it at all, only the Kitty CSI-u this cockpit already arms —
  so they cost the coworker's shell nothing. They precede the input modal, the drawer and the
  picker itself, so they open from anywhere and each closes what it opened.

  **`Alt+d` and `Alt+\\` are global for the same reason** — the drawer and the session pane are
  layout, not text, so neither has any business waiting for you to leave the reply box. That box is
  the only PERSISTENT input (it is focused the whole time a thread is open), so ordering it above
  the drawer clause made `Alt+d` dead inside a thread; the drawer clause now precedes `:reply` and
  still follows the transient modals its own verbs open. `Alt+g` (LOCK), `Alt+n`/`Alt+c` and the
  Alt+digits stay BELOW the modal on purpose — each would freeze, replace or orphan a live draft.

  `state` is the slice of cockpit state keys touch: `active_key`, `focused_id`, `threads`,
  `center_live?` (derived per keypress by the cockpit — true when a live terminal is in the
  center), `composer_thread_id` (also derived per keypress — the thread the `c` verb composes
  onto: the focused thread, or the machine thread in Tlön), `input` (the typing modal), `drawer`
  (the open drawer pane, nil when shut), `picker` (the open switcher/palette, nil when shut) with
  `picker_items` (its live rows, threaded in per keypress so the cursor clamps against the list on
  screen), and `live_workspaces` (the live workspace list, threaded in per keypress — the space
  ring and CONFIG read it). A `key_event` is the
  `Raxol.Core.Events.Event` `data` map, e.g. `%{key: :up}` or `%{key: :char, char: "j"}`.

  Effects (every one the reducer emits — the cockpit's `apply_effect/2` must cover each):

    * `:repaint` — state changed; reload server reads and paint.
    * `:quit` — tear down and stop.
    * `:none` — nothing to do.
    * `{:forward, key}` — send this key to the live center terminal.
    * `{:create_thread, text, project_id}` — the new-thread band's Enter: open a thread with `text`
      as its opening message (the `n` verb), on the project Tab picked (nil: the workspace default).
    * `{:file_ticket, text}` / `{:write_note, text}` — the New menu's ticket/note inputs.
    * `{:post_message, thread_id, body}` — post the composer's/reply box's body to that thread as
      the operator; `{:show_status, thread_id}` is the composer's `/status` slash command.
    * `{:orchestrate, text}` — the tertius `:` line's Enter; `{:confirm_orchestrate, armed}` — `y`
      on a routed consequential verb that is waiting for confirmation (`pending_confirm`).
    * `:open_focused_thread` / `:close_thread_view` / `{:scroll_conversation, rows}` — the
      two-step chat center: Enter opens the cursor thread's conversation, Esc steps back to the
      list, j/k (PgUp/PgDn with the reply box focused) scroll the open backlog.
    * `:stack_delete_arm` — `d` on a thread card arms the two-key delete; `:tlon_delete_arm` /
      `{:tlon_delete, target}` — the rail's `d` arm and its confirmed arm-time target.
    * `:toggle_center_view` (`v`, chat⇄terminal) and `:toggle_session_pane` (Alt+\\).
    * `:zoom_git` (Alt+z) — the open thread's lazygit, full-frame; Ctrl+Space hands it back to its pane.
    * `:tlon_enter` — Enter on a rail pane (space switch / lazygit zoom / detail, cockpit-resolved).
    * `:yank` — `y` in nav: the focused pane's semantic text to the clipboard.
    * `{:ticket_move, dir}` / `:ticket_advance` / `{:ticket_reorder, :up | :down}` — the drawer's
      TICKETS pane: move the kanban cursor over the live columns, advance the selected ticket's
      status, reorder it within its column (all need the server read the cockpit holds, so the
      reducer only names them).
    * `{:habit_action, :approve | :reject}` — `a`/`r` on the Memory pane's pending habit.
    * `{:cycle_coworker_model, profile}` — advance the active space's coworker driver model one
      step round `Server.Profiles.model_ring/0` and persist it (the `m` verb; only in a space with
      a coworker).
    * `{:switch_workspace_pos, n}` / `{:select_tab, n}` — Alt+Shift+digit / Alt+digit.
    * `{:register_workspace, template_key, name}` — Enter on the `:new_workspace` input (CONFIG's
      `n` verb) — register a workspace from a template + the typed name (D2.3).
    * `{:arm_delete, id, name}` — `d` on the author face's cursor row arms a delete confirm (D2.5).
    * `{:remove_workspace, id}` — the second `d` while armed on the SAME id confirms the delete.
    * `{:add_repo, id, buffer}` / `{:remove_repo, id, repo_id}` — CONFIG's repos sub-list (UX
      slice 5); the scope is rows now, so adding one is not a whole-list workspace edit.
    * `{:seat, id, attrs}` / `{:unseat, id, seat_id}` — CONFIG's bench sub-list, for the same
      reason. Seating registers the coworker's agent; unseating leaves it standing.
    * `{:edit_workspace, id, attrs}` — the field editor's `h`/`l` rings (type/scope) and the
      roster sub-list's `a`/`x`/`d` (D2.4 Chunk 2a) — apply one attrs map to a workspace immediately.
    * `{:coworker_knob, name, knob}` — the roster sub-list's `Tab`-selected knob (`:model` |
      `:yolo`), applied by `Enter`/`Space` to the sub-selected coworker (D2.4 Chunk 2b).

  `state.input` is `nil` normally, or a typing modal `%{kind, buffer, cursor, …}`. Kinds:
  `:new_thread` (the `n` verb / new-thread band), `:compose` (`c`, carries `thread_id`), `:reply`
  (the persistent per-thread reply box, `thread_id`; Enter posts and keeps the box, Esc closes the
  thread view), `:new_ticket` / `:new_note` (the New menu), `:orchestrate` (the tertius `:` line),
  `:new_workspace` (the author face's `n` — `template` is a `WorkspaceTemplates.names/0` atom,
  `h`/`l` cycle it), and the field editor's `:new_path` / `:new_roster` (`workspace_id`; the latter
  also an `archetype` ring). A modal captures EVERY key (so `q` types a
  "q", it does not quit) until Enter submits or Esc cancels. `cursor` is a grapheme offset into
  `buffer` (not always the end — Left/Right/Up/Down/Home/End move it, Ctrl+P/Ctrl+N alias Up/Down
  for hosts that don't deliver arrow keys, and Ctrl+A/Ctrl+E/Ctrl+U/Ctrl+K/Ctrl+W are readline's
  line-editing reflexes), and every edit (typing, Backspace, Shift+Enter's newline) acts AT the
  cursor, like a normal text box. In the composer, Shift+Enter inserts a newline (multiline
  bodies) instead of submitting.

  CONFIG (the Author, in the drawer since UX slice 1 task 5; `Alt+d` then its tab, or the settings
  verb): `handle_drawer/2` routes every key to `config/2` while `drawer == :config`. `author_cursor`
  is the workspace list's own per-row cursor, clamped against
  `live_workspaces` — the live `Console.Workspaces.all/0` list, threaded in per keypress (like
  `composer_thread_id`) so this module stays a pure reducer with no server call of its own.
  `pending_delete` (id | nil) is the two-key delete confirm's arm.

  The field editor (D2.4 Chunk 2a): `author_edit :: nil | %{id, field, sub, mode}` — `e` on the
  list's cursor workspace opens it at `field: 0` (type), `mode: :field`. `mode` (`:field | :sub`) is
  an addition beyond the plan's 3-key shape — the field list and a field's sub-list (repos/bench
  entries) both drive `j`/`k` over a DIFFERENT cursor (`field` vs `sub`) and need a bit to tell
  which is live; everything else matches the plan verbatim. `field` cycles the 4 rows (0 type · 1
  scope · 2 repos · 3 bench) with `j`/`k`, clamped no-wrap. On fields 0/1, `h`/`l` cycle a ring
  (`@type_ring`/`@scope_ring`) and emit `{:edit_workspace, id, attrs}` immediately — no draft/commit
  step. On fields 2/3, `Enter` drops into the sub-list (`mode: :sub`, `sub` resets to 0); there
  `j`/`k` move `sub` (clamped to the live repos/bench length), `a` opens an add buffer
  (`state.input` kind `:new_path` or `:new_roster` — the latter also carries an `archetype` ring
  cycled by `h`/`l`, mirroring `:new_workspace`'s `template`), `x`/`d` removes the `sub`-selected entry
  immediately, and `Esc` steps back to `mode: :field`. `Esc` on `mode: :field` clears `author_edit`
  entirely (back to the list). While `author_edit` is set, the list's own `n`/`d`/`a` verbs are
  blocked (`:none`) — editing and list-management stay separate modes, same as `input`/`modal`.

  The roster sub-list ALSO carries `knob :: :model | :yolo` (D2.4 Chunk 2b, default `:model`,
  read tolerantly via `Map.get/3` so older literal states don't need it) — meaningless outside
  `mode: :sub, field: 3` (the bench) — meaningless-but-harmless elsewhere. There `Tab` flips it;
  `Enter`/`Space` emit
  `{:coworker_knob, name, knob}` for the sub-selected entry (`name` resolved off the LIVE roster,
  `workspace_field/2`, same as the `a`/`x`/`d` clauses) — the Settings modal's model-ring-cycle /
  yolo-flip, now reached from here. This absorbs Settings; Chunk 2b deletes the `,` modal.
  """
  alias Console.Cockpit.Drawer
  alias Console.Picker
  alias Console.Space
  alias Console.Tlon.Focus
  alias Console.WorkspaceTemplates
  alias Server.Profiles

  # `Space.workspace?/1` is a `defguard` (usable in clause-head `when`s), which requires the module,
  # not just an alias.
  require Space

  # The field editor's rings (D2.4 Chunk 2a) — `h`/`l` cycle these on fields 0/1. Match
  # `Server.Workspace`'s DB CHECK closed sets exactly (funes/lib/funes/workspace.ex).
  @type_ring ["code", "life", "blank"]
  @scope_ring ["project", "machine"]

  # j/k/↓/↑ are ONE gesture wherever a list is walked: `vertical/1` reads it as +1 (down) / -1 (up)
  # and each site dispatches on that instead of spelling the four keys out.
  defguardp is_vertical(k) when k.key in [:up, :down] or (k.key == :char and k.char in ["j", "k"])

  # Enter, Space, or a typed space — the "apply" gesture of the roster sub-editor's knob.
  defguardp is_apply_key(k) when k.key in [:enter, :space] or (k.key == :char and k.char == " ")

  # Bare = no modifier at all; the Orbis nav keys demand it so a fallen-through chord can't leak in.
  defguardp is_bare(k) when not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt)

  @type effect ::
          :repaint
          | :quit
          | {:forward, map()}
          | {:create_thread, String.t(), integer() | nil}
          | {:file_ticket, String.t()}
          | {:write_note, String.t()}
          | {:orchestrate, String.t()}
          | {:confirm_orchestrate, map()}
          | :toggle_session_pane
          | :zoom_git
          | :toggle_center_view
          | {:post_message, term(), String.t()}
          | {:show_status, term()}
          | :open_focused_thread
          | :close_thread_view
          | {:scroll_conversation, integer()}
          | {:cycle_coworker_model, String.t()}
          | {:habit_action, :approve | :reject}
          | {:switch_workspace_pos, pos_integer()}
          | {:select_tab, pos_integer()}
          | {:register_workspace, atom(), String.t()}
          | {:arm_delete, term(), String.t()}
          | {:remove_workspace, term()}
          | {:edit_workspace, term(), map()}
          | {:coworker_knob, String.t(), :model | :yolo}
          | :tlon_enter
          | {:picker_pick, map()}
          | {:ticket_move, String.t()}
          | {:add_repo, integer(), String.t()}
          | {:seat, integer(), map()}
          | {:unseat, integer(), integer()}
          | {:remove_repo, integer(), integer()}
          | {:ticket_reorder, :up | :down}
          | :ticket_blocker_menu
          | :ticket_advance
          | :stack_delete_arm
          | :tlon_delete_arm
          | {:tlon_delete, term()}
          | :yank
          | :none

  @doc "Map a key event against the current state to the next state and the effect to run."
  @spec handle(map(), map()) :: {map(), effect()}

  # LOCK mode (design 2026-08-23): total passthrough. Alt+g alone is console's; every other
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

  # Ctrl+Space arrives in TWO encodings and the cockpit only understood one. Under the Kitty
  # disambiguate mode it is `\e[32;5u` → %{key: :space, ctrl: true}; without it — which is every
  # tmux-hosted cockpit, since tmux sends the legacy byte whatever `extended-keys` says — it is a
  # bare NUL, which raxol decodes as a ctrl-modified SPACE CHAR. Normalize to the canonical form up
  # front, the same way Shift+Space is normalized above, so one key means one thing downstream.
  def handle(%{key: :char, char: " ", ctrl: true}, state), do: handle(%{key: :space, ctrl: true}, state)

  # tertius y/n confirm gate (Slice 3.5): a consequential verb (open work / approve a gate) was
  # routed and is armed, waiting on the operator — the whole point is that a command line you talk into
  # NEVER fires a consequential action without a yes. While `pending_confirm` is set every key belongs
  # to the gate: `y` fires it (`:confirm_orchestrate`, apply_effect reads the arm), anything else backs
  # out. Precedes even the input modal — no modal can be open while armed (the submit cleared it).
  def handle(%{key: :char, char: "y"}, %{pending_confirm: pc} = state) when not is_nil(pc),
    do: {%{state | pending_confirm: nil}, {:confirm_orchestrate, pc}}

  def handle(_key, %{pending_confirm: pc} = state) when not is_nil(pc), do: {%{state | pending_confirm: nil}, :repaint}

  # input mode: a MODAL — every key belongs to the buffer until Enter/Esc, so a binding
  # letter (q, s, tab) types its character instead of firing. Must come first.
  # The persistent reply box (2026-09-01): Esc doesn't just drop the input, it steps the whole
  # center back to the thread LIST (`:close_thread_view` clears `opened_thread`) AND drops the draft,
  # so no half-typed reply leaks into the next thread. Precedes the generic Esc below.
  # `^⇧K` (go to) / `^⇧P` (commands) / `^⇧H` (history) — the global picker chords. Ctrl+Shift+<letter>
  # because NOTHING in a terminal binds it: a legacy terminal cannot even encode the combination,
  # only the Kitty CSI-u this cockpit already arms (`\e[107;6u` / `\e[112;6u`), so taking these
  # costs the coworker's shell nothing — unlike Slack's own Ctrl+K, which is readline's kill-line.
  # They sit above the input modal, the drawer AND the picker itself, so they open from anywhere
  # and each closes what it opened. Some hosts report the SHIFTED letter, hence both cases.
  def handle(%{key: :char, char: c, ctrl: true, shift: true}, state) when c in ["k", "K"],
    do: {toggle_picker(state, :switcher), :repaint}

  def handle(%{key: :char, char: c, ctrl: true, shift: true}, state) when c in ["p", "P"],
    do: {toggle_picker(state, :palette), :repaint}

  def handle(%{key: :char, char: c, ctrl: true, shift: true}, state) when c in ["h", "H"],
    do: {toggle_picker(state, :history), :repaint}

  # An open PICKER owns every key — it has a query box of its own, so it must precede the input
  # modal: `^⇧K` from inside the reply box opens the switcher and typing then goes to the switcher,
  # not the reply. Esc hands the keys back to whatever was underneath, draft intact.
  def handle(key, %{picker: picker} = state) when not is_nil(picker), do: handle_picker(key, state)

  # The DRAWER owns every key while it is open (UX slice 1 task 4) — like the picker above it,
  # nothing leaks to the frame underneath, and Esc / `Alt+d` hand the keys back with the draft
  # intact. It precedes the PERSISTENT reply box (`:reply`, focused the whole time a thread is
  # open): that box sitting ABOVE the drawer clause is why `Alt+d` did nothing inside a thread,
  # and why opening the drawer there would have left it undriveable. It still FOLLOWS the
  # TRANSIENT modals the drawer's own verbs open (`:new_ticket`, `:new_path`, …), so typing a new
  # ticket's title takes the keys back.
  def handle(key, %{drawer: d, input: nil} = state) when not is_nil(d), do: handle_drawer(key, state)

  def handle(key, %{drawer: d, input: %{kind: :reply}} = state) when not is_nil(d), do: handle_drawer(key, state)

  # `Alt+d` (open the drawer on its last pane) and `Alt+\` (toggle the session pane) are global for
  # the same reason the two chords above are: neither touches the draft, so there is nothing to gain
  # by making you leave the reply box first. The other Alt chords deliberately stay BELOW the input
  # modal — `Alt+g` because arming LOCK mid-compose would silently freeze the box, `Alt+n`/`Alt+c`
  # because they open a DIFFERENT modal over the draft, and the digits because switching workspace
  # would leave the draft pointing at another workspace's thread.
  def handle(%{key: :char, char: "d", alt: true} = k, %{drawer: nil} = state) when not is_map_key(k, :ctrl),
    do: {Drawer.open(state, state.last_drawer), :repaint}

  def handle(%{key: :char, char: "\\", alt: true} = k, %{active_key: key} = state)
      when Space.workspace?(key) and not is_map_key(k, :ctrl), do: {state, :toggle_session_pane}

  # Alt+z zooms the open thread's lazygit — global like Alt+\, since it moves the view, never the draft.
  def handle(%{key: :char, char: "z", alt: true} = k, %{active_key: key} = state)
      when Space.workspace?(key) and not is_map_key(k, :ctrl), do: {state, :zoom_git}

  # Ctrl+Space — the sticky term↔nav toggle — is global for the same reason: it moves FOCUS, never
  # text, so the draft is untouched. It sat below the input modal, and the reply box is focused the
  # whole time a thread is open, so the one key that gets you out of the terminal was dead there.
  def handle(%{key: :space, ctrl: true}, %{active_key: k, focus: %Focus{}} = state) when Space.workspace?(k),
    do: {focus_intent(state, :toggle_terminal), :repaint}

  def handle(%{key: :escape}, %{input: %{kind: :reply}} = state), do: {%{state | input: nil}, :close_thread_view}

  def handle(%{key: :escape}, %{input: %{}} = state), do: {%{state | input: nil}, :repaint}

  # Shift+Enter in the composer inserts a newline (a multiline body) instead of submitting, AT
  # the cursor (not always the end — Up/Down can have moved it off the last line). Must precede
  # the plain-Enter clauses — %{key: :enter, shift: true} also matches %{key: :enter}.
  def handle(%{key: :enter, shift: true}, %{input: %{kind: kind} = input} = state)
      when kind in [:compose, :new_thread, :reply], do: {%{state | input: insert_at(input, "\n")}, :repaint}

  # The reply box is PERSISTENT (born with the open thread), so Enter on an empty buffer is a plain
  # no-op — it must NOT clear the input like the transient composers below (that would blank the box
  # mid-conversation). Precedes the generic empty-buffer clause.
  def handle(%{key: :enter}, %{input: %{kind: :reply, buffer: ""}} = state), do: {state, :repaint}

  # Enter submits — but an empty buffer creates/posts nothing (cancel), never a blank thread/message.
  def handle(%{key: :enter}, %{input: %{buffer: ""}} = state), do: {%{state | input: nil}, :repaint}

  def handle(%{key: :enter}, %{input: %{kind: :new_thread, buffer: buffer} = input} = state),
    do: {%{state | input: nil}, {:create_thread, buffer, Map.get(input, :project_id)}}

  # Tab in the new-thread box picks the project the thread opens on (the project decides where its
  # coworker works), starting from the default the cockpit threads in as `project_choice`.
  def handle(%{key: :tab}, %{input: %{kind: :new_thread} = input} = state) do
    case state[:project_choice] do
      %{projects: [_ | _] = projects, default: default} ->
        ids = Enum.map(projects, & &1.id)
        at = Enum.find_index(ids, &(&1 == (Map.get(input, :project_id) || default))) || -1
        {%{state | input: Map.put(input, :project_id, Enum.at(ids, rem(at + 1, length(ids))))}, :repaint}

      _ ->
        {state, :none}
    end
  end

  # The `new` menu's ticket/note branches (Slice C): file a workspace ticket / jot a workspace note —
  # first-class create for the two nouns that were previously only reachable via a tertius prefix.
  def handle(%{key: :enter}, %{input: %{kind: :new_ticket, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:file_ticket, buffer}}

  def handle(%{key: :enter}, %{input: %{kind: :new_note, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:write_note, buffer}}

  # A topic channel in the active workspace (channels slice 1b; the `#` verb / a rail menu).
  def handle(%{key: :enter}, %{input: %{kind: :new_channel, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:create_channel, buffer}}

  # The tertius command line (Slice 1): Enter dispatches the typed meta-intent to the orchestrator,
  # which routes + executes it and hands back a receipt (the cockpit flashes it).
  def handle(%{key: :enter}, %{input: %{kind: :orchestrate, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:orchestrate, buffer}}

  # A non-blank name registers a workspace from the armed template. Blank already fell into the
  # empty-buffer clause above, same cancel-not-create precedent as :new_thread.
  def handle(%{key: :enter}, %{input: %{kind: :new_workspace, template: template, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:register_workspace, template, buffer}}

  # A non-blank buffer adds a REPO ROW to the edited workspace (UX slice 5). The buffer is
  # `path [remote [branch]]` — whitespace-split by the cockpit — so the two columns a bare glob
  # never had a place for are reachable without inventing a second prompt.
  # keypress) and applies immediately. Blank already fell into the empty-buffer clause above.
  def handle(%{key: :enter}, %{input: %{kind: :new_path, workspace_id: id, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:add_repo, id, buffer}}

  # A non-blank name appends a wire-shaped roster entry (`%{"archetype" => .., "name" => ..}`,
  # matching `WorkspaceTemplates.new_workspace_attrs/2`'s shape) to the edited workspace's LIVE roster and
  # applies immediately. Blank already fell into the empty-buffer clause above.
  def handle(%{key: :enter}, %{input: %{kind: :new_roster, workspace_id: id, archetype: arch, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:seat, id, %{name: buffer, archetype: Atom.to_string(arch)}}}

  # Slash commands are the composer's other door (reshape slice D): /status is the full HEALTH
  # readout (the panel demoted to a footer line), never posted as a chat message.
  def handle(%{key: :enter}, %{input: %{kind: :compose, thread_id: id, buffer: buffer}} = state) do
    case String.trim(buffer) do
      "/status" -> {%{state | input: nil}, {:show_status, id}}
      _body -> {%{state | input: nil}, {:post_message, id, buffer}}
    end
  end

  # The reply box posts to its thread and STAYS focused with a cleared buffer (unlike the composer,
  # which closes) — send, keep talking. The empty-buffer case already returned above, so `buffer`
  # here is non-blank.
  def handle(%{key: :enter}, %{input: %{kind: :reply, thread_id: id, buffer: buffer} = input} = state),
    do: {%{state | input: %{input | buffer: "", cursor: 0}}, {:post_message, id, buffer}}

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

  # With the reply box focused the buffer owns j/k (they type), so backlog scrolling rides PgUp/PgDn
  # (and the mouse wheel, handled in the cockpit) — routed to the same `:scroll_conversation` effect
  # the list-nav path used. Precede the ignore catch-all so these don't vanish while typing.
  def handle(%{key: :page_up}, %{input: %{kind: :reply}} = state), do: {state, {:scroll_conversation, -3}}
  def handle(%{key: :page_down}, %{input: %{kind: :reply}} = state), do: {state, {:scroll_conversation, 3}}

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

  # Global Alt chords (design 2026-08-23): work from ANY mode — TERM included — and switch
  # mode implicitly. Workspace-only for movement (there's no pane grid elsewhere); n/c everywhere.
  # Must precede the Tlön routing clause (which would forward them to tmux from TERM).
  # Nav v2 (Andrew 2026-08-31): Alt+Shift+digit → switch to the Nth WORKSPACE; Alt+digit (no shift) →
  # select tmux TAB N in the active workspace. `0` is the 10th. The shift clause is first (more
  # specific). (These replace the old Alt+digit focus-pane jump — pane digits are gone.)
  def handle(%{key: :char, char: d, alt: true, shift: true} = k, %{active_key: key} = state)
      when Space.workspace?(key) and d in ~w(0 1 2 3 4 5 6 7 8 9) and not is_map_key(k, :ctrl),
      do: {state, {:switch_workspace_pos, digit_pos(d)}}

  def handle(%{key: :char, char: d, alt: true} = k, %{active_key: key} = state)
      when Space.workspace?(key) and d in ~w(0 1 2 3 4 5 6 7 8 9) and not is_map_key(k, :ctrl),
      do: {state, {:select_tab, digit_pos(d)}}

  def handle(%{key: :char, char: c, alt: true} = k, %{active_key: key, focus: %Focus{}} = state)
      when Space.workspace?(key) and c in ~w(h j k l) and not is_map_key(k, :ctrl), do: {alt_move(state, c), :repaint}

  # Alt+n / Alt+c reach the shared command table with the modifier stripped (its clauses are
  # modifier-guarded on purpose — a bare-shaped key is the door).
  def handle(%{key: :char, char: "n", alt: true} = k, state) when not is_map_key(k, :ctrl),
    do: command(%{key: :char, char: "n"}, state)

  def handle(%{key: :char, char: "c", alt: true} = k, state) when not is_map_key(k, :ctrl),
    do: command(%{key: :char, char: "c"}, state)

  # Tlön: the lazygit focus model (design 2026-08-20). The center is a live tmux client, so
  # `Ctrl+Space` is a STICKY toggle in/out of it — NOT the arm-next-key leader other spaces use.
  # In the terminal every key forwards to tmux; out of it console owns the keys and drives the pure
  # `Console.Tlon.Focus` SM over `tlon_layout` (h/l pane · H/L column · s section · Esc→terminal).
  # `focus` (persistent) and `tlon_layout` (derived per keypress, like center_live?) are supplied by
  # the cockpit only for this space; the guard keeps every other space on the leader path below.
  def handle(key, %{active_key: k, focus: %Focus{}} = state) when Space.workspace?(k), do: handle_tlon(key, state)

  # default: the center surface owns the keys.
  # A live terminal in the center → every key forwards to its PTY. The terminal is "normal mode";
  # you type into it immediately. (Ctrl+C lands here too → forwards as an interrupt, never a quit.)
  def handle(key, %{center_live?: true} = state), do: {state, {:forward, key}}

  # No live terminal (Orbis, or a placeholder before a session spawns) → console's nav bindings are
  # bare — the same command table the leader reaches, just without the prefix.
  def handle(key, state), do: command(key, state)

  # console's command table — one source of bindings, reached two ways: bare in a nav-default
  # space, or via the Ctrl+Space leader from inside a running terminal.

  # The PICKER's key table (UX slice 2). Letters TYPE — it is a query box — so the cursor moves on
  # ↑↓, ^p/^n and Tab only, which is Slack's quick switcher exactly. `picker_items` is the live row
  # list, threaded in per keypress by the cockpit (the `live_workspaces` pattern), so the cursor is
  # clamped against the list actually on screen without this module reading anything.
  defp handle_picker(%{key: :escape}, state), do: {%{state | picker: nil}, :repaint}

  defp handle_picker(%{key: :enter}, %{picker: picker} = state) do
    case Picker.selected(picker_items(state), picker) do
      nil -> {%{state | picker: nil}, :repaint}
      item -> {%{state | picker: nil}, {:picker_pick, item}}
    end
  end

  defp handle_picker(%{key: :backspace}, %{picker: picker} = state),
    do: {%{state | picker: Picker.backspace(picker)}, :repaint}

  # ^u clears the query without closing — readline's reflex, and the fast way to re-aim a search.
  defp handle_picker(%{key: :char, char: "u", ctrl: true}, %{picker: picker} = state),
    do: {%{state | picker: Picker.clear_query(picker)}, :repaint}

  defp handle_picker(%{key: :up}, state), do: move_picker(state, -1)
  defp handle_picker(%{key: :down}, state), do: move_picker(state, 1)

  # ^p/^n are the readline aliases, for hosts that do not deliver arrows (a nested tmux/SSH hop);
  # both must precede the printable-insert clause below, which would otherwise type the letter.
  defp handle_picker(%{key: :char, char: "p", ctrl: true}, state), do: move_picker(state, -1)
  defp handle_picker(%{key: :char, char: "n", ctrl: true}, state), do: move_picker(state, 1)
  defp handle_picker(%{key: :tab, shift: true}, state), do: move_picker(state, -1)
  defp handle_picker(%{key: :tab}, state), do: move_picker(state, 1)

  defp handle_picker(%{key: :char, char: c} = key, %{picker: picker} = state)
       when is_binary(c) and not is_map_key(key, :alt) and not is_map_key(key, :ctrl),
       do: {%{state | picker: Picker.type(picker, c)}, :repaint}

  # A space can arrive as %{key: :space} with no char under CSI-u disambiguation — same reason the
  # input modal carries this clause.
  defp handle_picker(%{key: :space}, %{picker: picker} = state),
    do: {%{state | picker: Picker.type(picker, " ")}, :repaint}

  # Anything else is swallowed: the picker covers the frame, so no key may fall through to it.
  defp handle_picker(_key, state), do: {state, :none}

  defp move_picker(%{picker: picker} = state, delta),
    do: {%{state | picker: Picker.move(picker, delta, length(picker_items(state)))}, :repaint}

  # Absent in a state built by a test that does not exercise the list; an empty corpus is the right
  # reading of "no rows", not a crash.
  defp picker_items(state), do: Map.get(state, :picker_items) || []

  # The chord that opened a picker closes it; the OTHER chord swaps corpus without a trip through
  # Esc, so ^⇧K and ^⇧P behave like two tabs of one overlay.
  defp toggle_picker(%{picker: %{kind: kind}} = state, kind), do: %{state | picker: nil}
  defp toggle_picker(state, kind), do: %{state | picker: Picker.open(kind)}

  defp command(%{key: :char, char: "q"}, state), do: {state, :quit}

  # `n` focuses the persistent new-thread input band (2026-09-01) — a shortcut to the same input you
  # can click. Type a title, Enter creates (the :new_thread Enter clause → {:create_thread, …}).
  defp command(%{key: :char, char: "n"}, state),
    do: {%{state | input: %{kind: :new_thread, buffer: "", cursor: 0}}, :repaint}

  # `:` opens the tertius command line from any panel (Slice 1) — a vim-style command prompt for
  # meta-intent ("tell @x …", "file a ticket …", "remember …"). The generic input machinery below
  # handles the typing/cursor; Enter (above) dispatches to the orchestrator.
  defp command(%{key: :char, char: ":"}, state),
    do: {%{state | input: %{kind: :orchestrate, buffer: "", cursor: 0}}, :repaint}

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
    # a missing space (the server-down sentinel 0) has no coworker either
    case Space.fetch(key) do
      %{coworker: profile} when not is_nil(profile) -> {state, {:cycle_coworker_model, profile}}
      _ -> {state, :none}
    end
  end

  # Enter has no top-level verb elsewhere since the Slice 0 collapse: the Sessions space (its only
  # home — the one center that could show a spawned per-thread PTY) is gone, so Enter is a plain
  # no-op. In Tlön, Enter is routed by handle_tlon (commit-the-preview), never reaching this clause.
  defp command(%{key: :enter}, state), do: {state, :none}

  defp command(%{key: :tab, shift: true}, state), do: switch(state, :prev)
  defp command(%{key: :tab}, state), do: switch(state, :next)

  # j/k/↑/↓ move the thread focus. Since task 5 every live keypress enters through handle_tlon
  # (every active_key is a workspace key and the cockpit always carries a Focus), so this table —
  # and the Ctrl+Space leader above it — is reached only by handle_tlon's delegations and by tests
  # that build a state without :focus. Slice 2 (the key layers) decides the leader's fate.
  defp command(key, state) when is_vertical(key) and (key.key != :char or is_bare(key)),
    do: move_thread(state, vertical(key))

  # Anything else (Ctrl+C, F-keys, page-up…) is unbound — a no-op, never a quit.
  defp command(_key, state), do: {state, :none}

  # Tlön's delete confirm (mirrors Orbis'): `d` arms on the focused pane's selection (the
  # cockpit resolves the target + flashes), the SECOND `d` — still armed — confirms with the
  # ARM-TIME target; literally any other key cancels. Both precede every other clause so a stale
  # keypress can never confirm.
  defp handle_tlon(%{key: :char, char: "d"}, %{tlon_delete: target} = state) when not is_nil(target),
    do: {%{state | tlon_delete: nil}, {:tlon_delete, target}}

  defp handle_tlon(_key, %{tlon_delete: target} = state) when not is_nil(target),
    do: {%{state | tlon_delete: nil}, :repaint}

  # The thread stack is the shown center (center_view :chat, Slice 3) and it's the focused surface
  # (in_terminal? — the center owns the keys): drive the STACK directly instead of forwarding to a
  # tmux client that isn't there. j/k/↑↓ move the cursor, z/Space fold, Z/+ zoom, g/G ends. `:`
  # focuses the tertius line from here too. This precedes the generic forward clause below, so the
  # terminal path (center_view :terminal) is untouched.
  defp handle_tlon(%{key: :char, char: ":"}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state),
    do: {%{state | input: %{kind: :orchestrate, buffer: "", cursor: 0}}, :repaint}

  # LIST mode (no thread opened): j/k move the cursor, g/G jump, Enter opens the focused thread's
  # conversation. (Two-step center — the fold/zoom stack is retired.)
  defp handle_tlon(key, %{focus: %Focus{in_terminal?: true}, center_view: :chat, opened_thread: nil} = state)
       when is_vertical(key), do: move_thread(state, vertical(key))

  defp handle_tlon(
         %{key: :char, char: "g"},
         %{focus: %Focus{in_terminal?: true}, center_view: :chat, opened_thread: nil} = state
       ), do: stack_jump(state, :first)

  defp handle_tlon(
         %{key: :char, char: "G"},
         %{focus: %Focus{in_terminal?: true}, center_view: :chat, opened_thread: nil} = state
       ), do: stack_jump(state, :last)

  defp handle_tlon(
         %{key: :enter},
         %{focus: %Focus{in_terminal?: true}, center_view: :chat, opened_thread: nil} = state
       ), do: {state, :open_focused_thread}

  # CONVERSATION mode (a thread opened): j/k scroll it; Esc goes back to the list.
  defp handle_tlon(key, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state) when is_vertical(key),
    do: {state, {:scroll_conversation, 3 * vertical(key)}}

  defp handle_tlon(%{key: :escape}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state),
    do: {state, :close_thread_view}

  # `n` focuses the new-thread band while looking at the LIST (like j/k), not only via the Alt chords.
  # `c` is retired from the chat flow: opening a thread now focuses its persistent reply box directly
  # (the `:reply` input), so there's no compose verb to reach here. (`c` still opens a composer in
  # Orbis / terminal view via the `command` clause, which routes through `composer_thread_id`.)
  defp handle_tlon(%{key: :char, char: "n"} = k, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state),
    do: command(k, state)

  # `d` arms the two-key delete for the FOCUSED thread card (the second `d` is caught by the armed
  # clause at the top of handle_tlon). This restores thread-delete, lost when the MachineChat TUI and
  # the LEAVES rail panel — the old delete surfaces — were retired.
  defp handle_tlon(%{key: :char, char: "d"}, %{focus: %Focus{in_terminal?: true}, center_view: :chat} = state),
    do: {state, :stack_delete_arm}

  # The center owns the keys only while a live PTY is actually SHOWN there (`center_live?`, derived per
  # keypress by the cockpit): the chat view has none, so an unlisted key is a no-op — never a forward
  # into the hidden machine PTY underneath.
  defp handle_tlon(key, %{focus: %Focus{in_terminal?: true}, center_live?: true} = state), do: {state, {:forward, key}}
  defp handle_tlon(_key, %{focus: %Focus{in_terminal?: true}} = state), do: {state, :none}

  # Esc steps back one level: close an open detail first, else drop out of nav into the terminal.
  defp handle_tlon(%{key: :escape}, %{focus: %Focus{detail?: true}} = state),
    do: {focus_intent(state, :close_detail), :repaint}

  defp handle_tlon(%{key: :escape}, state), do: {put_in(state.focus.in_terminal?, true), :repaint}
  # Nav v2: pane digits are gone — the rail is walked with h/l. (Bare digits are no longer a jump.)
  defp handle_tlon(%{key: :char, char: "l"}, state), do: {focus_intent(state, :pane_next), :repaint}
  defp handle_tlon(%{key: :char, char: "h"}, state), do: {focus_intent(state, :pane_prev), :repaint}
  defp handle_tlon(%{key: :char, char: "L"}, state), do: {focus_intent(state, :col_right), :repaint}
  defp handle_tlon(%{key: :char, char: "H"}, state), do: {focus_intent(state, :col_left), :repaint}
  # j/k move the item cursor within the focused pane.
  defp handle_tlon(key, state) when is_vertical(key), do: {focus_intent(state, item_intent(vertical(key))), :repaint}
  # Enter is contextual: the cockpit resolves the focused pane (space switch / lazygit zoom / a MAIN
  # detail) — the keymap can't, it lacks the reads.
  defp handle_tlon(%{key: :enter}, state), do: {state, :tlon_enter}
  # a/r act on the selected pending habit (Memory's habits section) — the cockpit resolves which
  # habit from the focus + reads and no-ops if the focus isn't on a habit. Approving writes it into
  # the recall floor; rejecting drops it.
  defp handle_tlon(%{key: :char, char: "a"}, state), do: {state, {:habit_action, :approve}}
  defp handle_tlon(%{key: :char, char: "r"}, state), do: {state, {:habit_action, :reject}}
  # `y` — semantic yank: the cockpit resolves the focused pane's real text (sha/fact/title) and
  # writes it to the clipboard via OSC 52. Detail-open yanks the detail body.
  defp handle_tlon(%{key: :char, char: "y"}, state), do: {state, :yank}
  # `d` — the operator's delete verb: the cockpit resolves the focused pane's selection (MEMORY
  # fact → forget) and arms the two-key confirm above.
  defp handle_tlon(%{key: :char, char: "d"}, state), do: {state, :tlon_delete_arm}
  # C3.4 reshuffle: Tab/Shift+Tab switch spaces (matching the command level) instead of cycling
  # sections — Shift+Tab must precede the bare :tab clause below, which also matches it.
  defp handle_tlon(%{key: :tab, shift: true}, state), do: switch(state, :prev)
  defp handle_tlon(%{key: :tab}, state), do: switch(state, :next)
  # `[`/`]` are the rail's own advertised space keys — the same ring Tab walks.
  defp handle_tlon(%{key: :char, char: "["}, state), do: switch(state, :prev)
  defp handle_tlon(%{key: :char, char: "]"}, state), do: switch(state, :next)
  # `s` took over section-cycle (freed by Tab) — habits approve/reject needs focus.section == 1,
  # so the section must stay reachable.
  defp handle_tlon(%{key: :char, char: "s"}, state), do: {focus_intent(state, :section_next), :repaint}
  defp handle_tlon(%{key: :char, char: "q"}, state), do: {state, :quit}
  # The center [chat]|[terminal] toggle (reshape slice D): flip which face the Workspace center shows.
  defp handle_tlon(%{key: :char, char: "v"}, state), do: {state, :toggle_center_view}
  defp handle_tlon(%{key: :char, char: "n"} = k, state), do: command(k, state)
  defp handle_tlon(%{key: :char, char: "c"} = k, state), do: command(k, state)
  # `m` — move the rail's thread to another channel (a menu); off the rail it cycles the coworker's
  # model as before. `#` — a new channel. Both cockpit-resolved (the rail's rows are a read).
  defp handle_tlon(%{key: :char, char: "m"}, state), do: {state, :rail_move}
  defp handle_tlon(%{key: :char, char: "#"}, state), do: {state, :new_channel_prompt}
  defp handle_tlon(_key, state), do: {state, :none}

  @doc """
  The drawer's key table (UX slice 1, task 4). `Esc` / `Alt+d` close it (an open detail closes
  first); `1`-`9` and `h`/`l` walk the tab strip; `j`/`k` move the open pane's own cursor and
  `Enter` runs its verb through the cockpit (`:tlon_enter`). The pane-specific verbs are the ones
  its `Console.Panel.hints/1` advertise — MEMORY's `s`/`y`/`d`/`a`/`r`, TICKETS' `n`/`p`/`H`/`L`,
  NOTES' `n`. Everything else is swallowed: the drawer covers the centre, so no key may fall through
  to it.
  """
  @spec handle_drawer(map(), map()) :: {map(), effect()}

  # The armed two-key delete (a MEMORY fact) — must precede every other clause, exactly as it does
  # in `handle_tlon/2`, so a stale keypress can never confirm one.
  def handle_drawer(%{key: :char, char: "d"}, %{tlon_delete: target} = state) when not is_nil(target),
    do: {%{state | tlon_delete: nil}, {:tlon_delete, target}}

  def handle_drawer(_key, %{tlon_delete: target} = state) when not is_nil(target),
    do: {%{state | tlon_delete: nil}, :repaint}

  # CONFIG (the Author, UX slice 1 task 5): its own key table — the workspace list's n/e/d, the
  # field editor, the sub-lists — then the drawer's common keys.
  def handle_drawer(key, %{drawer: :config} = state), do: config(key, state)

  def handle_drawer(key, state), do: drawer_common(key, state)

  # The drawer's common keys, every pane.
  # Esc steps back one level: an open detail first, then the drawer itself.
  defp drawer_common(%{key: :escape}, %{focus: %Focus{detail?: true}} = state),
    do: {focus_intent(state, :close_detail), :repaint}

  defp drawer_common(%{key: :escape}, state), do: {Drawer.close(state), :repaint}

  defp drawer_common(%{key: :char, char: "d", alt: true} = k, state) when not is_map_key(k, :ctrl),
    do: {Drawer.close(state), :repaint}

  # 1-9 jump straight to a pane; a digit past the strip is a no-op, never a blank drawer.
  defp drawer_common(%{key: :char, char: d} = k, state) when is_bare(k) and d in ~w(1 2 3 4 5 6 7 8 9) do
    case Drawer.at(String.to_integer(d) - 1) do
      nil -> {state, :none}
      key -> {Drawer.open(state, key), :repaint}
    end
  end

  defp drawer_common(%{key: :char, char: "l"}, state), do: {Drawer.open(state, Drawer.step(state.drawer, +1)), :repaint}
  defp drawer_common(%{key: :char, char: "h"}, state), do: {Drawer.open(state, Drawer.step(state.drawer, -1)), :repaint}

  # TICKETS is a grid, so its cursor needs a horizontal move too — `H`/`L`, since `h`/`l` walk the
  # strip. The cockpit owns the move (the live columns are a server read); the keymap stays pure.
  # `J`/`K` reorder the selected ticket within its column and persist it (UX slice 4). Above the
  # `H`/`L` column clause so the shifted pair is read as a pair, and above the generic `is_vertical`
  # move below, which would otherwise take them as plain j/k.
  # `b` on a card opens the "blocked by…" menu (UX slice 4) — cockpit-resolved, because the other
  # tickets it offers and which of them already block are server reads the keymap does not hold.
  defp drawer_common(%{key: :char, char: "b"}, %{drawer: :tickets} = state), do: {state, :ticket_blocker_menu}

  defp drawer_common(%{key: :char, char: "J"}, %{drawer: :tickets} = state), do: {state, {:ticket_reorder, :down}}
  defp drawer_common(%{key: :char, char: "K"}, %{drawer: :tickets} = state), do: {state, {:ticket_reorder, :up}}

  defp drawer_common(%{key: :char, char: c}, %{drawer: :tickets} = state) when c in ~w(H L),
    do: {state, {:ticket_move, if(c == "H", do: "h", else: "l")}}

  defp drawer_common(key, %{drawer: :tickets} = state) when is_vertical(key),
    do: {state, {:ticket_move, if(vertical(key) == 1, do: "j", else: "k")}}

  defp drawer_common(%{key: :char, char: "p"}, %{drawer: :tickets} = state), do: {state, :ticket_advance}

  # `n` on a board files/jots one — the same create inputs the New menu opens.
  defp drawer_common(%{key: :char, char: "n"}, %{drawer: :tickets} = state),
    do: {%{state | input: %{kind: :new_ticket, buffer: "", cursor: 0}}, :repaint}

  defp drawer_common(%{key: :char, char: "n"}, %{drawer: :notes} = state),
    do: {%{state | input: %{kind: :new_note, buffer: "", cursor: 0}}, :repaint}

  # j/k move the open pane's own item cursor (stored per pane, so each keeps its place).
  defp drawer_common(key, state) when is_vertical(key), do: {focus_intent(state, item_intent(vertical(key))), :repaint}

  # Enter is contextual — the cockpit resolves the open pane (lazygit zoom / a detail / a promote).
  defp drawer_common(%{key: :enter}, state), do: {state, :tlon_enter}
  defp drawer_common(%{key: :char, char: "s"}, state), do: {focus_intent(state, :section_next), :repaint}
  defp drawer_common(%{key: :char, char: "y"}, state), do: {state, :yank}
  defp drawer_common(%{key: :char, char: "d"}, state), do: {state, :tlon_delete_arm}
  defp drawer_common(%{key: :char, char: "a"}, state), do: {state, {:habit_action, :approve}}
  defp drawer_common(%{key: :char, char: "r"}, state), do: {state, {:habit_action, :reject}}
  defp drawer_common(_key, state), do: {state, :none}

  # CONFIG's delete confirm (D2.5): a `d` on the cursor row arms; the SECOND `d`
  # (still armed on that SAME id — nothing else could have changed it, see the next clause)
  # confirms; literally any other key cancels. Both must precede EVERY other clause (even `q`) so
  # an armed delete can never be confirmed by a stale keypress.
  defp config(%{key: :char, char: "d"}, %{pending_delete: id} = state) when not is_nil(id) do
    {Map.put(state, :pending_delete, nil), {:remove_workspace, id}}
  end

  defp config(_key, %{pending_delete: id} = state) when not is_nil(id) do
    {Map.put(state, :pending_delete, nil), :repaint}
  end

  # the field editor (D2.4 Chunk 2a): `author_edit != nil` gates its own key table, ahead of
  # the list's `n`/`d`/`a`/Esc/h/l/j/k so editing and list-management never leak into each other.

  # `e` on the list's cursor workspace opens the editor at field 0. A no-op on an
  # empty list, or while ALREADY editing (never re-arms onto a different cursor workspace mid-edit).
  defp config(%{key: :char, char: "e"}, state) do
    case {author_edit(state), Enum.at(live_workspaces(state), author_cursor(state))} do
      {nil, %{id: id}} ->
        {Map.put(state, :author_edit, %{id: id, field: 0, sub: 0, mode: :field, knob: :model}), :repaint}

      _ ->
        {state, :none}
    end
  end

  # Field-list mode: j/k move the field cursor 0..3, clamped (no wrap).
  defp config(key, %{author_edit: %{mode: :field} = edit} = state) when is_vertical(key),
    do: {put_author_edit(state, %{edit | field: (edit.field + vertical(key)) |> max(0) |> min(3)}), :repaint}

  # Field-list mode: h/l cycle the type (field 0) / scope (field 1) ring against the LIVE workspace
  # (live_workspaces, threaded per keypress) and emit the edit immediately — no draft/commit step.
  # Fields 2/3 (repos/bench) have no ring — a no-op, matching the plan's "otherwise no-op".
  defp config(%{key: :char, char: "h"}, %{author_edit: %{mode: :field} = edit} = state),
    do: {state, field_ring_edit(state, edit, -1)}

  defp config(%{key: :char, char: "l"}, %{author_edit: %{mode: :field} = edit} = state),
    do: {state, field_ring_edit(state, edit, 1)}

  # Esc in field-list mode clears author_edit — back to the list.
  defp config(%{key: :escape}, %{author_edit: %{mode: :field}} = state), do: {put_author_edit(state, nil), :repaint}

  # Field-list mode: Enter on fields 2/3 (repos/bench) drops into the sub-list. Fields 0/1's
  # rings already apply via h/l — nothing for Enter to open, a no-op.
  defp config(%{key: :enter}, %{author_edit: %{mode: :field, field: f} = edit} = state) when f in [2, 3],
    do: {put_author_edit(state, %{edit | mode: :sub, sub: 0}), :repaint}

  defp config(%{key: :enter}, %{author_edit: %{mode: :field}} = state), do: {state, :none}

  # Sub-list mode (D2.4 Chunk 2b/2c): j/k move `sub`, clamped to the field's LIVE list length
  # (repos/bench off live_workspaces, threaded per keypress — never stale).
  defp config(key, %{author_edit: %{mode: :sub} = edit} = state) when is_vertical(key),
    do: {put_author_edit(state, %{edit | sub: move_sub(state, edit, vertical(key))}), :repaint}

  # Sub-list mode, field 2 (repos): `a` opens a `:new_path` add buffer (state.input, kind-agnostic
  # reuse of the printable-insert/Enter/Esc machinery, mirrors `:new_workspace`).
  defp config(%{key: :char, char: "a"}, %{author_edit: %{mode: :sub, field: 2, id: id}} = state),
    do: {%{state | input: %{kind: :new_path, buffer: "", cursor: 0, workspace_id: id}}, :repaint}

  # Sub-list mode, field 2 (repos): x/d removes the sub-selected ROW by id immediately — no confirm
  # (unlike the list's whole-workspace delete, an add re-creates it; the two-key arm is reserved for
  # destroying a WORKSPACE). By id, not index: the row is what the server deletes, and an index
  # racing a concurrent edit would delete the wrong one.
  defp config(%{key: :char, char: c}, %{author_edit: %{mode: :sub, field: 2, id: id, sub: sub}} = state)
       when c in ["x", "d"] do
    state
    |> workspace_field(id, :repos)
    |> Enum.at(sub)
    |> case do
      %{id: repo_id} -> {state, {:remove_repo, id, repo_id}}
      _ -> {state, :none}
    end
  end

  # Sub-list mode, field 3 (roster): `a` opens a `:new_roster` add flow — the same `state.input`
  # kit as `:new_path`, plus an `archetype` ring (Profiles.archetypes/0's keys, cycled by h/l
  # below) armed at the FIRST archetype, mirroring `:new_workspace`'s `template`.
  defp config(%{key: :char, char: "a"}, %{author_edit: %{mode: :sub, field: 3, id: id}} = state) do
    input = %{
      kind: :new_roster,
      buffer: "",
      cursor: 0,
      workspace_id: id,
      archetype: List.first(Map.keys(Profiles.archetypes()))
    }

    {%{state | input: input}, :repaint}
  end

  # Sub-list mode, field 3 (bench): x/d UNSEATS the sub-selected coworker by its ROW id — same
  # no-confirm reasoning as field 2's repo removal, same by-id discipline. Unseating does not
  # delete the AGENT: that is durable identity other threads point at.
  defp config(%{key: :char, char: c}, %{author_edit: %{mode: :sub, field: 3, id: id, sub: sub}} = state)
       when c in ["x", "d"] do
    state
    |> workspace_field(id, :bench)
    |> Enum.at(sub)
    |> case do
      %Server.Coworker{id: seat_id} -> {state, {:unseat, id, seat_id}}
      _ -> {state, :none}
    end
  end

  # Sub-list mode, field 3 (roster) only: `Tab` flips the knob (:model <-> :yolo) Enter/Space
  # applies (D2.4 Chunk 2b, absorbs Settings' field-flip). Guarded to field 3 (repos have no knob)
  # and must precede the generic Tab-switches-space clauses below.
  defp config(%{key: :tab}, %{author_edit: %{mode: :sub, field: 3} = edit} = state),
    do: {put_author_edit(state, Map.put(edit, :knob, flip_knob(edit_knob(edit)))), :repaint}

  # Sub-list mode, field 3 (roster) only: Enter/Space applies the active knob to the sub-selected
  # coworker (the Settings modal's apply, now here) — `name` off the LIVE bench (workspace_field/2,
  # same source `a`/`x`/`d` read). A vanished entry (sub past the shrunk list) is a no-op.
  defp config(key, %{author_edit: %{mode: :sub, field: 3}} = state) when is_apply_key(key), do: roster_knob_apply(state)

  # Sub-list mode: Esc steps back to the field list (mode: :field), field unchanged.
  defp config(%{key: :escape}, %{author_edit: %{mode: :sub} = edit} = state),
    do: {put_author_edit(state, %{edit | mode: :field}), :repaint}

  # The list's n/d/a verbs are blocked while author_edit is set — editing is its own mode; falling
  # through here (rather than to the list clauses below) keeps Chunk 1's create/delete/toggle
  # list-only, untouched when author_edit is nil.
  defp config(%{key: :char, char: c}, %{author_edit: %{}} = state) when c in ["n", "d", "a"], do: {state, :none}

  # `n` opens the create-workspace flow (a template ring + a name buffer, D2.3).
  defp config(%{key: :char, char: "n"}, state) do
    input = %{kind: :new_workspace, buffer: "", cursor: 0, template: List.first(WorkspaceTemplates.names())}
    {%{state | input: input}, :repaint}
  end

  # `d` on the cursor workspace arms the delete confirm (D2.5) — the FIRST press; the armed-state
  # clauses above own the second press and every cancel. A no-op on an empty list.
  defp config(%{key: :char, char: "d"}, state) do
    case Enum.at(live_workspaces(state), author_cursor(state)) do
      %{id: id, name: name} -> {state, {:arm_delete, id, name}}
      _ -> {state, :none}
    end
  end

  # j/k walk the workspace list; Enter has no verb on the list (e opens the editor) — and never
  # the drawer's :tlon_enter, which would arm a detail this pane cannot show.
  defp config(key, state) when is_vertical(key) and (key.key != :char or is_bare(key)),
    do: move_author_cursor(state, vertical(key))

  defp config(%{key: :enter}, state), do: {state, :none}
  defp config(%{key: :char, char: "a"}, state), do: {state, :none}
  defp config(key, state), do: drawer_common(key, state)

  defp focus_intent(state, intent), do: %{state | focus: Focus.handle(state.focus, state.tlon_layout, intent)}

  @doc false
  @spec vertical(map()) :: 1 | -1 | nil
  def vertical(%{key: :down}), do: 1
  def vertical(%{key: :up}), do: -1
  def vertical(%{char: "j"}), do: 1
  def vertical(%{char: "k"}), do: -1
  def vertical(_key), do: nil

  defp item_intent(1), do: :item_next
  defp item_intent(-1), do: :item_prev

  # A digit key to a 1-based position: "1".."9" → 1..9, "0" → 10 (the super+1..0 idiom).
  defp digit_pos("0"), do: 10
  defp digit_pos(d), do: String.to_integer(d)

  # Alt+h/j/k/l: directional pane movement, implicit nav (Focus intents no-op in-terminal, so
  # drop out of the terminal first).
  @alt_moves %{"h" => :col_left, "l" => :col_right, "j" => :pane_next, "k" => :pane_prev}

  defp alt_move(state, c) do
    focus = %{state.focus | in_terminal?: false}
    %{state | focus: Focus.handle(focus, state.tlon_layout, @alt_moves[c])}
  end

  # Tab/Shift+Tab/[ ] walk the workspace ring; with no workspaces (server down) there is nowhere
  # to go — a no-op, not a crash.
  defp switch(state, dir) do
    # the ring is the keypress's own workspace list (the cockpit threads the cache in), so the
    # keymap stays pure and a test can hand it two workspaces
    spaces = Space.all(live_workspaces(state))

    case if(dir == :next, do: Space.next(state.active_key, spaces), else: Space.prev(state.active_key, spaces)) do
      nil -> {state, :none}
      space -> {%{state | active_key: space.key}, :repaint}
    end
  end

  # The thread cursor: one step through `state.threads`, clamped (no wrap) — the Workspace stack's
  # j/k and Orbis' thread-focus move alike.
  defp move_thread(%{threads: []} = state, _dir), do: {state, :none}

  defp move_thread(state, dir) do
    ids = Enum.map(state.threads, & &1.id)
    i = Enum.find_index(ids, &(&1 == state.focused_id)) || 0
    {%{state | focused_id: Enum.at(ids, min(max(i + dir, 0), length(ids) - 1))}, :repaint}
  end

  defp stack_jump(%{threads: []} = state, _), do: {state, :none}
  defp stack_jump(state, :first), do: {%{state | focused_id: hd(state.threads).id}, :repaint}
  defp stack_jump(state, :last), do: {%{state | focused_id: List.last(state.threads).id}, :repaint}

  # Clamp `author_cursor` into `0..length(live_workspaces) - 1` — edge-clamp, no wrap.
  defp move_author_cursor(state, dir) do
    max_idx = max(length(live_workspaces(state)) - 1, 0)
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
  defp author_cursor(state), do: Map.get(state, :author_cursor, 0)
  defp author_edit(state), do: Map.get(state, :author_edit)
  defp put_author_edit(state, edit), do: Map.put(state, :author_edit, edit)

  # h/l on field 0 (type) / field 1 (scope): find the CURRENT workspace (live_workspaces, threaded per
  # keypress — never stale), step its ring value by `dir` (wrapping — a ring, not a clamp, same
  # idiom as `cycle_template/2`), and emit the edit. A workspace that's vanished (deleted mid-edit,
  # the Bus race is real but rare) or a field with no ring (2/3) is a no-op.
  defp field_ring_edit(state, %{id: id, field: field}, dir) when field in [0, 1] do
    case Enum.find(live_workspaces(state), &(&1.id == id)) do
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
  # edge-clamp discipline as `move_author_cursor/2`.
  defp move_sub(state, %{id: id, field: field, sub: sub}, dir) do
    max_idx = state |> workspace_field(id, sub_key(field)) |> length() |> Kernel.-(1) |> max(0)
    (sub + dir) |> max(0) |> min(max_idx)
  end

  defp sub_key(2), do: :repos
  defp sub_key(3), do: :bench

  # The roster sub-editor's knob (D2.4 Chunk 2b) — tolerant read (default :model) so a state built
  # before this field existed (an older test's literal author_edit) still works.
  defp edit_knob(edit), do: Map.get(edit, :knob, :model)
  defp flip_knob(:model), do: :yolo
  defp flip_knob(:yolo), do: :model

  # Resolve the sub-selected roster entry's `name` off the LIVE workspace and emit the apply effect —
  # a vanished entry (deleted mid-edit, or `sub` past the shrunk list) is a no-op, not a crash.
  defp roster_knob_apply(%{author_edit: %{id: id, sub: sub} = edit} = state) do
    state
    |> workspace_field(id, :bench)
    |> Enum.at(sub)
    |> case do
      %Server.Coworker{name: name} -> {state, {:coworker_knob, name, edit_knob(edit)}}
      _ -> {state, :none}
    end
  end

  # The CURRENT value of one list-shaped field (`:repos`/`:bench`) off the LIVE workspace
  # (live_workspaces, threaded per keypress — never stale). A vanished workspace (deleted mid-edit)
  # degrades to `[]` rather than crashing the reducer.
  defp workspace_field(state, id, key) do
    case Enum.find(live_workspaces(state), &(&1.id == id)) do
      nil -> []
      workspace -> Map.get(workspace, key) || []
    end
  end

  defp live_workspaces(state), do: Map.get(state, :live_workspaces, [])

  # Input-buffer cursor math (graphemes, not bytes). `input.cursor` defaults to the buffer's end when
  # absent (a state built before this field existed, or by an older test).
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
