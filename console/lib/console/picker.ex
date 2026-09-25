defmodule Console.Picker do
  @moduledoc """
  The overlays of UX slice 2, which are one thing wearing three corpora: a **query**, a
  **cursor**, and a filtered list you pick from.

    * `:switcher` (`^⇧K`) — every workspace, channel and thread in the cockpit, matched on its
      whole path (`ficciones · #general · cockpit slice`), so typing a workspace narrows to its
      threads. Picking one JUMPS: it switches workspace if it has to.
    * `:palette` (`^⇧P`) — `Console.Verbs`, every verb with its key and a sentence saying what it
      does. Picking one REPLAYS its key event through the keymap.
    * `:history` (`^⇧H`) — every CLOSED thread (`Server.Channel.closed_threads/0`, the imported
      conversations among them), matched on title and project. Picking one opens it.

  Each reads a corpus that already exists — the switcher off the rail's own `sidebar` read, so it
  costs no server call and can never disagree with what the rail is showing; the palette off a
  static table; history off the `history` read the cockpit stashes while that picker is up. `entries/2` filters and ranks with `Console.Fuzzy`.

  Pure: the picker never reads the world, it is handed the cockpit state. `query`/`cursor` live in
  `state.picker`; the rows are derived per keypress (`Console.Cockpit` threads them in as
  `picker_items`, the way `live_workspaces` is threaded in) so the cursor can be clamped against a
  list neither this module nor `Console.Keymap` had to fetch.
  """

  alias Console.Fuzzy
  alias Console.Verbs

  @type kind :: :switcher | :palette | :history
  @type t :: %{kind: kind(), query: String.t(), cursor: non_neg_integer()}

  @doc "A freshly opened picker: empty query, cursor on the first row."
  @spec open(kind()) :: t()
  def open(kind) when kind in [:switcher, :palette, :history], do: %{kind: kind, query: "", cursor: 0}

  @doc "The overlay's title — what you are picking FROM."
  @spec title(t() | kind()) :: String.t()
  def title(%{kind: kind}), do: title(kind)
  def title(:switcher), do: "GO TO"
  def title(:palette), do: "COMMANDS"
  def title(:history), do: "HISTORY"

  @doc "The overlay's footer hint — how to drive it."
  @spec hint(t() | kind()) :: String.t()
  def hint(%{kind: kind}), do: hint(kind)
  def hint(:switcher), do: "type to filter · ↑↓ move · ⏎ jump · esc close"
  def hint(:palette), do: "type to filter · ↑↓ move · ⏎ run · esc close"
  def hint(:history), do: "type to filter · ↑↓ move · ⏎ open · esc close"

  @doc """
  The picker's rows, filtered and ranked against its query. `state` is the cockpit's — the switcher
  reads `:sidebar` (the rail's last painted groups), the palette reads nothing.

  A row carries what the panel paints (`tag`, `keys`, `label`, `context`), what the filter matches
  (`text`), and what picking it acts on (`kind` plus the ids, or the verb's `event`).
  """
  @spec entries(t(), map()) :: [map()]
  def entries(%{kind: :switcher, query: query}, state) do
    state
    |> Map.get(:sidebar)
    |> List.wrap()
    |> switcher_rows()
    |> Fuzzy.filter(query, & &1.text)
  end

  def entries(%{kind: :palette, query: query}, _state) do
    Verbs.all()
    |> Enum.map(&verb_row/1)
    |> Fuzzy.filter(query, & &1.text)
  end

  def entries(%{kind: :history, query: query}, state) do
    state
    |> Map.get(:history)
    |> List.wrap()
    |> Enum.map(&history_row/1)
    |> Fuzzy.filter(query, & &1.text)
  end

  @doc "Type a character into the query. Any edit puts the cursor back on the best match."
  @spec type(t(), String.t()) :: t()
  def type(picker, char), do: %{picker | query: picker.query <> char, cursor: 0}

  @doc "Delete the last character of the query (a no-op on an empty one)."
  @spec backspace(t()) :: t()
  def backspace(%{query: ""} = picker), do: picker
  def backspace(picker), do: %{picker | query: String.slice(picker.query, 0..-2//1), cursor: 0}

  @doc "Clear the query, keeping the picker open (readline's ^U)."
  @spec clear_query(t()) :: t()
  def clear_query(picker), do: %{picker | query: "", cursor: 0}

  @doc """
  Move the cursor `delta` rows, wrapping — a short list is a ring, the way every quick-switcher
  behaves. `count` is the live row count, threaded in per keypress, so this clamps against the
  list actually on screen.
  """
  @spec move(t(), integer(), non_neg_integer()) :: t()
  def move(picker, _delta, count) when count <= 0, do: %{picker | cursor: 0}
  def move(picker, delta, count), do: %{picker | cursor: Integer.mod(picker.cursor + delta, count)}

  @doc "The row the cursor is on, or nil (an empty list, or a query that matches nothing)."
  @spec selected([map()], t()) :: map() | nil
  def selected(items, %{cursor: cursor}), do: Enum.at(items, cursor)

  # -- the switcher's corpus: the rail's own read, every workspace expanded ------------------

  # The rail shows only the ACTIVE workspace's channels; the switcher shows them all, which is the
  # point of it — the read already carries every group's channels, so this costs nothing extra.
  defp switcher_rows(groups) do
    Enum.flat_map(groups, fn group ->
      workspace = group[:workspace] || %{}
      [workspace_row(workspace) | Enum.flat_map(group[:channels] || [], &channel_rows(&1, workspace))]
    end)
  end

  defp workspace_row(workspace) do
    name = workspace[:name] || "?"

    %{
      kind: :workspace,
      tag: "workspace",
      keys: nil,
      label: name,
      context: "",
      text: name,
      workspace_id: workspace[:id]
    }
  end

  defp channel_rows(channel, workspace) do
    ws = workspace[:name] || "?"
    name = "##{channel[:name] || "?"}"

    row = %{
      kind: :channel,
      tag: "channel",
      keys: nil,
      label: name,
      context: ws,
      text: "#{ws} · #{name}",
      workspace_id: workspace[:id],
      channel_id: channel[:id]
    }

    [row | Enum.map(channel[:threads] || [], &thread_row(&1, channel, workspace, name, ws))]
  end

  defp thread_row(thread, channel, workspace, channel_name, ws) do
    title = thread[:title] || "(untitled)"

    %{
      kind: :thread,
      tag: "thread",
      keys: nil,
      label: title,
      context: "#{ws} · #{channel_name}",
      text: "#{ws} · #{channel_name} · #{title}",
      workspace_id: workspace[:id],
      channel_id: channel[:id],
      thread_id: thread[:id]
    }
  end

  defp verb_row(verb) do
    %{
      kind: :verb,
      tag: Atom.to_string(verb.group),
      keys: verb.keys,
      label: verb.label,
      context: verb.doc,
      text: Verbs.subject(verb),
      event: verb.event
    }
  end

  # A closed thread: its title, then where it lived and when it last spoke. Picking it opens the
  # conversation (read-only until you reply), switching workspace if it has to.
  defp history_row(thread) do
    title = thread[:title] || "(untitled)"
    project = thread[:project] || "no project"

    %{
      kind: :thread,
      tag: "closed",
      keys: nil,
      label: title,
      context: "#{project} · #{thread[:at] && Calendar.strftime(thread[:at], "%Y-%m-%d")}",
      text: "#{title} · #{project}",
      workspace_id: thread[:workspace_id],
      thread_id: thread[:id]
    }
  end
end
