defmodule Console.Verbs do
  @moduledoc """
  **Every verb the cockpit has, with its key and what it does** — the command palette's corpus
  (UX slice 2, `^⇧P`). Andrew's ask was discoverability: "what is term what is model". A keycap in
  the footer answers *which key*; only a sentence answers *what it does*, so every row here carries
  one.

  A row is `%{group, keys, label, doc, event}`:

    * `group` — where the verb applies (`:global`, `:centre`, `:rail`, `:drawer`, `:typing`),
      shown dim and matched by the fuzzy filter, so typing "drawer" lists the drawer's keys.
    * `keys` — the keycap, in the footer's notation (`^⇧K`, `Alt+d`, `⇧⏎`).
    * `event` — the key event the palette REPLAYS through `Console.Keymap.handle/2` when you pick
      the row. Picking a verb is literally pressing its key, so the palette can never drift from
      what the key does; `Console.VerbsTest` asserts every event still reaches a live binding.

  `event: nil` means the row is a doc line, not a button. Two kinds of verb are deliberately
  doc-only:

    * **verbs with no single key** — `j`/`k`, `Alt+1…0`, the two-key `d d`. There is no one event
      to replay.
    * **consequential verbs** — `q` (quit) and the deletes. A fuzzy list where a mistyped query
      plus Enter tears down your cockpit is a trap; the same instinct as the tertius `y`/`n`
      confirm gate. The palette tells you the key and you press it.
  """

  @type verb :: %{group: atom(), keys: String.t(), label: String.t(), doc: String.t(), event: map() | nil}

  @verbs [
    # ── global: these work from anywhere, the coworker's terminal included ──────────────────
    %{
      group: :global,
      keys: "^⇧K",
      label: "go to",
      doc: "jump to any workspace, channel or thread by name — type to filter, ⏎ jumps",
      event: %{key: :char, char: "k", ctrl: true, shift: true}
    },
    %{
      group: :global,
      keys: "^⇧P",
      label: "commands",
      doc: "this list: every verb the cockpit has, its key, and what it does",
      event: %{key: :char, char: "p", ctrl: true, shift: true}
    },
    %{
      group: :global,
      keys: "Alt+d",
      label: "drawer",
      doc:
        "open the drawer over the centre — now · crew · memory · stack · roster · triage · tickets · notes · health · config",
      event: %{key: :char, char: "d", alt: true}
    },
    %{
      group: :global,
      keys: "^␣",
      label: "term / nav",
      doc: "give the keys to the coworker's terminal, or take them back for the cockpit",
      event: %{key: :space, ctrl: true}
    },
    %{
      group: :global,
      keys: "Alt+\\",
      label: "session pane",
      doc: "the right-hand live terminal beside the conversation: auto → off → on",
      event: %{key: :char, char: "\\", alt: true}
    },
    %{
      group: :global,
      keys: "Alt+g",
      label: "lock",
      doc: "total passthrough — every key goes to the terminal (even the chords) until Alt+g again",
      event: %{key: :char, char: "g", alt: true}
    },
    %{
      group: :global,
      keys: "]  [",
      label: "workspace",
      doc: "the next / previous workspace (Tab and ⇧Tab do the same)",
      event: %{key: :char, char: "]"}
    },
    %{
      group: :global,
      keys: "Alt+⇧1…0",
      label: "workspace N",
      doc: "switch straight to the Nth workspace",
      event: nil
    },
    %{
      group: :global,
      keys: "Alt+1…0",
      label: "tab N",
      doc: "select the Nth tmux tab inside this workspace",
      event: nil
    },
    %{
      group: :global,
      keys: "Alt+h/j/k/l",
      label: "tmux pane",
      doc: "move the focus between the tmux panes of the active workspace",
      event: nil
    },

    # ── the centre: the thread list and the open conversation ──────────────────────────────
    %{
      group: :centre,
      keys: "⏎",
      label: "open",
      doc: "open the cursor thread's conversation (its reply box comes up focused)",
      event: %{key: :enter}
    },
    %{
      group: :centre,
      keys: "esc",
      label: "back",
      doc: "step back from the open conversation to the thread list",
      event: %{key: :escape}
    },
    %{
      group: :centre,
      keys: "j  k",
      label: "move",
      doc: "move the thread cursor, or scroll the open conversation (↑↓ too)",
      event: nil
    },
    %{
      group: :centre,
      keys: "g  G",
      label: "ends",
      doc: "jump to the first / last thread in the list",
      event: nil
    },
    %{
      group: :centre,
      keys: "n",
      label: "new thread",
      doc: "start a thread in the open channel — type a title, ⏎ creates it",
      event: %{key: :char, char: "n"}
    },
    %{
      group: :centre,
      keys: "c",
      label: "compose",
      doc: "post a message to the focused thread (an open conversation already has its reply box)",
      event: %{key: :char, char: "c"}
    },
    %{
      group: :centre,
      keys: "v",
      label: "term",
      doc: "flip the centre between the conversation and the coworker's live terminal",
      event: %{key: :char, char: "v"}
    },
    %{
      group: :centre,
      keys: "m",
      label: "model",
      doc: "cycle this workspace's coworker driver model one step round the ring (glm · deepseek · kimi · …)",
      event: %{key: :char, char: "m"}
    },
    %{
      group: :centre,
      keys: ":",
      label: "command line",
      doc: ~s{the tertius line — talk an intent at the orchestrator ("tell @x …", "file a ticket …")},
      event: %{key: :char, char: ":"}
    },
    %{
      group: :centre,
      keys: "y",
      label: "yank",
      doc: "copy the focused row's real text (sha · fact · title) to the clipboard",
      event: %{key: :char, char: "y"}
    },
    %{
      group: :centre,
      keys: "d  d",
      label: "delete thread",
      doc: "delete the focused thread — press d twice, the second confirms the armed target",
      event: nil
    },
    %{
      group: :centre,
      keys: "q",
      label: "quit",
      doc: "leave the cockpit (press it in the frame — the palette won't fire it for you)",
      event: nil
    },

    # ── the rail: workspaces → channels → threads ──────────────────────────────────────────
    %{
      group: :rail,
      keys: "h  l",
      label: "pane",
      doc: "move the focus between panes — the rail and the centre",
      event: nil
    },
    %{
      group: :rail,
      keys: "H  L",
      label: "column",
      doc: "move the focus between the frame's columns",
      event: nil
    },
    %{
      group: :rail,
      keys: "s",
      label: "section",
      doc: "the next section within the focused pane",
      event: %{key: :char, char: "s"}
    },
    %{
      group: :rail,
      keys: "m",
      label: "move to channel",
      doc: "move the rail's thread into another channel (a menu of this workspace's channels)",
      event: nil
    },
    %{
      group: :rail,
      keys: "#",
      label: "new channel",
      doc: "a new topic channel in the active workspace",
      event: %{key: :char, char: "#"}
    },
    %{
      group: :rail,
      keys: "d  d",
      label: "delete",
      doc: "delete the rail's thread, or a topic channel — twice to confirm (#general can't go)",
      event: nil
    },

    # ── the drawer ─────────────────────────────────────────────────────────────────────────
    %{group: :drawer, keys: "1…9", label: "pane", doc: "jump straight to the Nth pane of the tab strip", event: nil},
    %{group: :drawer, keys: "h  l", label: "pane", doc: "walk the tab strip one pane at a time", event: nil},
    %{group: :drawer, keys: "esc", label: "close", doc: "close the drawer (an open detail closes first)", event: nil},
    %{
      group: :drawer,
      keys: "n",
      label: "new",
      doc: "file a ticket (on TICKETS) or jot a note (on NOTES)",
      event: nil
    },
    %{group: :drawer, keys: "p", label: "advance", doc: "advance the selected ticket's status", event: nil},
    %{group: :drawer, keys: "H  L", label: "column", doc: "move the kanban cursor across the columns", event: nil},
    %{
      group: :drawer,
      keys: "a  r",
      label: "habit",
      doc: "approve / reject the pending habit on MEMORY",
      event: nil
    },
    %{
      group: :drawer,
      keys: "e",
      label: "edit workspace",
      doc: "on CONFIG: open the cursor workspace's field editor (type · scope · repos · roster)",
      event: nil
    },

    # ── typing: any input — the reply box, a title, the tertius line ───────────────────────
    %{group: :typing, keys: "⏎", label: "send", doc: "post the reply, or create the thing you named", event: nil},
    %{group: :typing, keys: "⇧⏎", label: "newline", doc: "a newline inside the message instead of sending", event: nil},
    %{group: :typing, keys: "esc", label: "cancel", doc: "drop the draft and step out of the input", event: nil},
    %{
      group: :typing,
      keys: "^a ^e ^u ^k ^w",
      label: "line edit",
      doc: "readline's reflexes: home · end · kill to start · kill to end · kill the word behind",
      event: nil
    },
    %{
      group: :typing,
      keys: "^p ^n",
      label: "line",
      doc: "up / down a line, for hosts that don't deliver the arrow keys",
      event: nil
    }
  ]

  @doc "Every verb, in reading order (global → centre → rail → drawer → typing)."
  @spec all() :: [verb()]
  def all, do: @verbs

  @doc """
  The text the fuzzy filter matches a verb on: its group, keycap, label and doc together, so
  "drawer", "^⇧K", "model" and "clipboard" all find their row.
  """
  @spec subject(verb()) :: String.t()
  def subject(%{group: group, keys: keys, label: label, doc: doc}), do: "#{group} #{keys} #{label} #{doc}"
end
