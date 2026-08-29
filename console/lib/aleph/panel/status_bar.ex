defmodule Console.Panel.StatusBar do
  @moduledoc """
  The bottom status footer — two rows, always present:

    * an **info** line, justified into sections: a space *tab* and the focused thread on the left,
      the global counts (open threads, live sessions) as chips on the right;
    * a **hints** line: the key bindings, keycaps lit against dim labels.

  The gap between left and right is neutral (never a chip background), so the footer frames the
  screen instead of flooding it. Data is `%{space, thread, thread_count, live_count}`.
  """
  @behaviour Console.Panel

  alias Console.Panel

  # {keycap, label} pairs — keycaps lit in amber, labels dim. The tmux-style model: the center
  # owns the keys by default, so aleph's commands are reached through the ^B leader. (In a
  # nav-default space — no live terminal — these are also bare; the hints name the universal path.)
  @hints [
    {"^␣", "aleph"},
    {"^␣n", "new"},
    {"^␣c", "post"},
    {"^␣⏎", "spawn"},
    {"^␣Tab", "space"},
    {"^␣↑↓", "thread"},
    {"^␣q", "quit"}
  ]
  @leader_hints [{"^␣ …", :header}, {"  prefix armed — Esc cancels", :dim}]

  @impl Panel
  def topics(_assigns), do: []

  # Composer mode: the buffer itself renders in the growable compose box above this footer
  # (`Console.Panel.Composer` — full buffer, wrap + grow); the footer keeps the mode chip and the
  # composer hints.
  @impl Panel
  def render(%{input: %{kind: :compose}}, rect) do
    prompt = [{" COMPOSE ", :tab}]

    hints = [
      {"⏎", :header},
      {" post", :dim},
      {"   ", :dim},
      {"⇧⏎", :header},
      {" newline", :dim},
      {"  ", :dim},
      {"←→↑↓", :header},
      {" move", :dim},
      {"  ", :dim},
      {"Esc", :header},
      {" cancel", :dim}
    ]

    Panel.clip([prompt, hints], rect)
  end

  # Title input mode: the info line becomes the prompt, split at the cursor (a caret marks it),
  # and the hints line names only the keys that do anything while typing.
  @impl Panel
  def render(%{input: %{kind: :new_thread} = input}, rect) do
    {before, after_} = cursor_split(input)

    prompt = [
      {" NEW THREAD ", :tab},
      {"  ", :normal},
      {"▸ ", :accent},
      {before, :normal},
      {"▎", :accent},
      {after_, :normal}
    ]

    hints = [
      {"⏎", :header},
      {" create", :dim},
      {"   ", :dim},
      {"←→", :header},
      {" move", :dim},
      {"  ", :dim},
      {"Esc", :header},
      {" cancel", :dim}
    ]

    Panel.clip([prompt, hints], rect)
  end

  # The author face's create-workspace prompt (D2.3): the info line becomes the prompt over the typed
  # name, prefixed by the armed template — h/l cycles it, named in the hints.
  @impl Panel
  def render(%{input: %{kind: :new_workspace, template: template} = input}, rect) do
    {before, after_} = cursor_split(input)

    prompt = [
      {" NEW WORKSPACE ", :tab},
      {"  ", :normal},
      {"◂ #{template} ▸ ", :accent},
      {before, :normal},
      {"▎", :accent},
      {after_, :normal}
    ]

    hints = [
      {"⏎", :header},
      {" create", :dim},
      {"   ", :dim},
      {"←→", :header},
      {" move", :dim},
      {"  ", :dim},
      {"h/l", :header},
      {" template", :dim},
      {"  ", :dim},
      {"Esc", :header},
      {" cancel", :dim}
    ]

    Panel.clip([prompt, hints], rect)
  end

  # The field editor's paths sub-list `a` add (D2.4 Chunk 2b): the info line becomes the prompt
  # over the typed path.
  @impl Panel
  def render(%{input: %{kind: :new_path} = input}, rect) do
    {before, after_} = cursor_split(input)

    prompt = [
      {" NEW PATH ", :tab},
      {"  ", :normal},
      {"▸ ", :accent},
      {before, :normal},
      {"▎", :accent},
      {after_, :normal}
    ]

    hints = [
      {"⏎", :header},
      {" add", :dim},
      {"   ", :dim},
      {"←→", :header},
      {" move", :dim},
      {"  ", :dim},
      {"Esc", :header},
      {" cancel", :dim}
    ]

    Panel.clip([prompt, hints], rect)
  end

  # The field editor's roster sub-list `a` add (D2.4 Chunk 2c): the info line becomes the prompt
  # over the typed name, prefixed by the armed archetype — h/l cycles it, named in the hints.
  @impl Panel
  def render(%{input: %{kind: :new_roster, archetype: archetype} = input}, rect) do
    {before, after_} = cursor_split(input)

    prompt = [
      {" NEW ROSTER ENTRY ", :tab},
      {"  ", :normal},
      {"◂ #{archetype} ▸ ", :accent},
      {before, :normal},
      {"▎", :accent},
      {after_, :normal}
    ]

    hints = [
      {"⏎", :header},
      {" add", :dim},
      {"   ", :dim},
      {"←→", :header},
      {" move", :dim},
      {"  ", :dim},
      {"h/l", :header},
      {" archetype", :dim},
      {"  ", :dim},
      {"Esc", :header},
      {" cancel", :dim}
    ]

    Panel.clip([prompt, hints], rect)
  end

  # A transient result line (a spawn's pane id, or its failure reason) — the operator's feedback
  # that `n`/`s` did something. Shown until the next keypress clears it.
  @impl Panel
  def render(%{flash: flash}, rect) when is_binary(flash) do
    info = [{" ", :normal}, {"▸ ", :accent}, {flash, :normal}]
    Panel.clip([justify(info, [], rect.w), hints_row()], rect)
  end

  # The prefix is armed (Ctrl+Space was pressed, awaiting the next key) — show the prefix state
  # instead of the command hints, so the operator knows the next key is aleph's, not the terminal's.
  @impl Panel
  def render(%{leader_pending?: true}, rect) do
    info = [{" ", :normal}, {"▸ ^␣ ", :accent}, {"prefix armed", :normal}]
    Panel.clip([justify(info, [], rect.w), hints_row(@leader_hints)], rect)
  end

  @impl Panel
  def render(%{space: space} = data, rect) do
    thread = data[:thread] || "—"
    threads = data[:thread_count] || 0
    live = data[:live_count] || 0

    left =
      mode_chip(data) ++
        [
          {" #{space} ", :tab},
          {"  ", :normal},
          {"▸ ", :accent},
          {thread, :normal}
        ]

    right =
      health_seg(data[:health]) ++
        [
          {" ◷ #{threads} threads ", :stat},
          {" ", :normal},
          {" ● #{live} live ", :stat_live}
        ]

    Panel.clip([justify(left, right, rect.w), hints_row(assemble_hints(data))], rect)
  end

  # HEALTH demoted to a one-line footer segment (reshape slice D): service dots + disk/mem/load,
  # dim so it frames rather than shouts. The full readout is `/status` in the composer. nil
  # (probe not run — Orbis, boot frame) renders nothing.
  defp health_seg(%{funes_up: funes, tlon_up: tlon} = h) do
    [
      {"#{service_dot(funes)} ", service_style(funes)},
      {"funes ", :dim},
      {"#{service_dot(tlon)} ", service_style(tlon)},
      {"tlon ", :dim},
      {"· d#{h[:disk_pct]}% m#{h[:mem_pct]}% l#{short_load(h[:load_avg])} ", :dim},
      {" ", :normal}
    ]
  end

  defp health_seg(_health), do: []

  defp service_dot(true), do: "●"
  defp service_dot(_up), do: "○"
  defp service_style(true), do: :stat_live
  defp service_style(_up), do: :stat_warn

  defp short_load(load) when is_number(load), do: :erlang.float_to_binary(load / 1, decimals: 1)
  defp short_load(_load), do: "?"

  # LOCK outranks TERM/NAV — total keyboard passthrough deserves the loudest chip. Absent for
  # spaces without a focus model (mode nil, focus nil).
  defp mode_chip(%{mode: :lock}), do: [{" LOCK ", :stat_warn}, {" ", :normal}]
  defp mode_chip(%{focus: %{in_terminal?: true}}), do: [{" TERM ", :stat_live}, {" ", :normal}]
  defp mode_chip(%{focus: %{in_terminal?: false}}), do: [{" NAV ", :stat}, {" ", :normal}]
  defp mode_chip(_data), do: []

  # The CURRENT line of a (possibly multiline) input buffer, split into the text before/after the
  # cursor — what the composer's single visible line renders around the `▎` marker. `cursor`
  # defaults to the buffer's end when absent (a state from before this field existed), matching
  # the old always-at-the-end rendering.
  defp cursor_split(%{buffer: buffer} = input) do
    cursor = Map.get(input, :cursor, String.length(buffer))
    {before, aft} = buffer |> String.graphemes() |> Enum.split(cursor)
    before_line = before |> Enum.join() |> String.split("\n") |> List.last()

    after_line =
      aft
      |> Enum.join()
      |> String.split("\n", parts: 2)
      |> List.first()

    {before_line, after_line}
  end

  defp hints_row, do: hints_row(@hints)

  # The contextual footer (design 2026-08-23): mode → space → pane, mode-first because clip/2
  # trims from the right — pane verbs drop first on a narrow frame, the mode chip survives.
  # Keyed on workspace-ness (mode/workspace? from View.status_data), NEVER the space label — a renamed
  # or additional Workspace still gets these, unlike the old "Tlön"-keyed table.
  defp assemble_hints(%{mode: nil}), do: @hints
  defp assemble_hints(data), do: mode_seg(data.mode) ++ space_seg(data) ++ (data[:pane_hints] || [])

  defp mode_seg(:term), do: [{"Alt+#", "panes"}, {"^␣", "nav"}]
  defp mode_seg(:nav), do: [{"Alt+0", "term"}, {"q", "quit"}]
  defp mode_seg(:lock), do: [{"Alt+g", "unlock"}]

  defp space_seg(%{mode: :nav, workspace?: true}), do: [{"c", "post"}, {"n", "task"}, {"v", "chat"}, {"m", "driver"}]
  defp space_seg(_data), do: []

  defp hints_row(hints) do
    Enum.flat_map(hints, fn
      {key, label} when is_binary(label) -> [{key, :header}, {" #{label}", :dim}, {"   ", :dim}]
      {text, style} -> [{text, style}]
    end)
  end

  # Left-align `left`, right-align `right`, fill the middle with neutral spaces to exactly `w`.
  # When too narrow for both, keep the left (clip/1 trims it) — the thread matters more than counts.
  defp justify(left, right, w) do
    gap = w - Panel.row_width(left) - Panel.row_width(right)

    if gap >= 1,
      do: left ++ [{String.duplicate(" ", gap), :normal}] ++ right,
      else: left
  end
end
