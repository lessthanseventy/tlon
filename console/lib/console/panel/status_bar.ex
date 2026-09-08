defmodule Console.Panel.StatusBar do
  @moduledoc """
  The bottom status footer — **one row** since UX slice 1: the contextual hints (mode verbs →
  space verbs → the focused pane's own), keycaps lit against dim labels. Where you are and who is
  on it belongs to `Console.Panel.TopBar` now.

  While an input is open (compose, new ticket/note/workspace/path/roster) or a flash/leader prefix
  is live, that state takes the row instead: the prompt on the left, its verbs right-aligned on the
  SAME row, the least important verb dropped first when the frame is too narrow for all of them.
  """
  @behaviour Console.Panel

  alias Console.Panel

  # {keycap, label} pairs — keycaps lit in amber, labels dim. The tmux-style model: the center
  # owns the keys by default, so console's commands are reached through the ^B leader. (In a
  # nav-default space — no live terminal — these are also bare; the hints name the universal path.)
  @hints [
    {"^␣", "console"},
    {"^␣n", "new"},
    {"^␣c", "reply"},
    {"^␣⏎", "spawn"},
    {"^␣Tab", "space"},
    {"^␣↑↓", "thread"},
    {"^␣q", "quit"}
  ]
  # What the armed prefix accepts next — @hints without the ^␣ prefix, since the prefix is already
  # down. Esc leads: the escape hatch is the one verb that must survive a narrow frame.
  @leader_hints [
    {"Esc", "cancel"},
    {"n", "new"},
    {"c", "reply"},
    {"⏎", "spawn"},
    {"Tab", "space"},
    {"↑↓", "thread"},
    {"q", "quit"}
  ]

  @impl Panel
  def topics(_assigns), do: []

  # Composer mode: the buffer itself renders in the growable compose box above this footer
  # (`Console.Panel.Composer` — full buffer, wrap + grow); the footer keeps the mode chip and the
  # composer verbs.
  @impl Panel
  def render(%{input: %{kind: :compose}}, rect) do
    prompt = [{" COMPOSE ", :tab}]
    verbs = [{"⏎", "reply"}, {"Esc", "cancel"}, {"⇧⏎", "newline"}, {"←→↑↓", "move"}]
    Panel.clip([prompt_row(prompt, verbs, rect.w)], rect)
  end

  # Title input mode: the row becomes the prompt, split at the cursor (a caret marks it), with only
  # the keys that do anything while typing right-aligned beside it.
  @impl Panel
  # :new_thread renders in the permanent Panel.NewThread band (like :orchestrate in Tertius), so it is
  # NOT matched here — it falls through to the normal footer. Ticket/note stay modal in the footer.
  def render(%{input: %{kind: kind} = input}, rect) when kind in [:new_ticket, :new_note] do
    {before, after_} = cursor_split(input)
    label = %{new_ticket: " NEW TICKET ", new_note: " NEW NOTE "}[kind]

    prompt = [
      {label, :tab},
      {"  ", :normal},
      {"▸ ", :accent},
      {before, :buf},
      {"▎", :accent},
      {after_, :buf}
    ]

    Panel.clip([prompt_row(prompt, [{"Esc", "cancel"}, {"⏎", "create"}, {"←→", "move"}], rect.w)], rect)
  end

  # NOTE: the tertius orchestrate input renders in the permanent `Console.Panel.Tertius` band (the
  # bottom of the center), NOT here — an :orchestrate input falls through to the normal footer below,
  # so the input never shows twice.

  # The author face's create-workspace prompt (D2.3): the row becomes the prompt over the typed
  # name, prefixed by the armed template — h/l cycles it, named in the verbs.
  @impl Panel
  def render(%{input: %{kind: :new_workspace, template: template} = input}, rect) do
    {before, after_} = cursor_split(input)

    prompt = [
      {" NEW WORKSPACE ", :tab},
      {"  ", :normal},
      {"◂ #{template} ▸ ", :accent},
      {before, :buf},
      {"▎", :accent},
      {after_, :buf}
    ]

    verbs = [{"Esc", "cancel"}, {"⏎", "create"}, {"h/l", "template"}, {"←→", "move"}]
    Panel.clip([prompt_row(prompt, verbs, rect.w)], rect)
  end

  # The field editor's paths sub-list `a` add (D2.4 Chunk 2b): the row becomes the prompt over the
  # typed path.
  @impl Panel
  def render(%{input: %{kind: :new_path} = input}, rect) do
    {before, after_} = cursor_split(input)

    prompt = [
      {" NEW PATH ", :tab},
      {"  ", :normal},
      {"▸ ", :accent},
      {before, :buf},
      {"▎", :accent},
      {after_, :buf}
    ]

    Panel.clip([prompt_row(prompt, [{"Esc", "cancel"}, {"⏎", "add"}, {"←→", "move"}], rect.w)], rect)
  end

  # The field editor's roster sub-list `a` add (D2.4 Chunk 2c): the row becomes the prompt over the
  # typed name, prefixed by the armed archetype — h/l cycles it, named in the verbs.
  @impl Panel
  def render(%{input: %{kind: :new_roster, archetype: archetype} = input}, rect) do
    {before, after_} = cursor_split(input)

    prompt = [
      {" NEW ROSTER ENTRY ", :tab},
      {"  ", :normal},
      {"◂ #{archetype} ▸ ", :accent},
      {before, :buf},
      {"▎", :accent},
      {after_, :buf}
    ]

    verbs = [{"Esc", "cancel"}, {"⏎", "add"}, {"h/l", "archetype"}, {"←→", "move"}]
    Panel.clip([prompt_row(prompt, verbs, rect.w)], rect)
  end

  # A transient result line (a spawn's pane id, or its failure reason) — the operator's feedback
  # that `n`/`s` did something. Shown until the next keypress clears it.
  @impl Panel
  def render(%{flash: flash} = data, rect) when is_binary(flash) do
    info = [{" ", :normal}, {"▸ ", :accent}, {flash, :normal}]
    Panel.clip([prompt_row(info, assemble_hints(data), rect.w)], rect)
  end

  # The prefix is armed (Ctrl+Space was pressed, awaiting the next key) — the state plus what the
  # next key can be, so the operator knows the key is console's, not the terminal's.
  @impl Panel
  def render(%{leader_pending?: true}, rect) do
    info = [{" ", :normal}, {"▸ ^␣ ", :accent}, {"prefix armed", :normal}]
    Panel.clip([prompt_row(info, @leader_hints, rect.w)], rect)
  end

  # The default face: hints only. The old info row (mode chip, space, thread, counts) moved to
  # Panel.TopBar with UX slice 1; HEALTH goes to the drawer.
  @impl Panel
  def render(data, rect) do
    Panel.clip([hints_row(assemble_hints(data))], rect)
  end

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

  # The contextual footer (design 2026-08-23): mode → space → pane, mode-first because clip/2
  # trims from the right — pane verbs drop first on a narrow frame, the mode chip survives.
  # Keyed on workspace-ness (mode/workspace? from View.status_data), NEVER the space label — a renamed
  # or additional Workspace still gets these, unlike the old "Tlön"-keyed table.
  defp assemble_hints(data) do
    case data[:mode] do
      nil -> @hints
      mode -> mode_seg(mode) ++ space_seg(data) ++ (data[:pane_hints] || [])
    end
  end

  defp mode_seg(:term), do: [{"Alt+#", "panes"}, {"^␣", "nav"}]
  defp mode_seg(:nav), do: [{"Alt+0", "term"}, {"q", "quit"}]
  defp mode_seg(:lock), do: [{"Alt+g", "unlock"}]
  # The open drawer owns every key (Console.Cockpit.Drawer): only its own verbs, plus the open
  # pane's, are live — the NAV face's would be dead hints under it.
  defp mode_seg(:drawer), do: [{"esc", "close"}, {"h/l", "pane"}]

  defp space_seg(%{mode: :nav, workspace?: true} = data) do
    [
      {"Alt+d", "drawer"},
      {"c", "reply"},
      {"n", "new"},
      {"v", "term"},
      {"m", "model"},
      {"Alt+\\", pane_mode(data[:session_pane_mode])}
    ]
  end

  defp space_seg(_data), do: []

  # The right session pane's mode, named rather than implied — Alt+\ cycles :auto → off → on.
  defp pane_mode(true), do: "pane on"
  defp pane_mode(false), do: "pane off"
  defp pane_mode(_auto), do: "pane auto"

  # A face's own row: prompt left, verbs right-aligned, as many as fit. The row is one line high,
  # so a verb that doesn't fit is GONE — hence the drop-from-the-tail order (verbs are listed
  # most-load-bearing first, Esc/the head verb always survives). When even the head verb has no
  # room, the prompt yields instead of the verb — see fit_prompt/3.
  defp prompt_row(prompt, verbs, w) do
    fit = fit_verbs(prompt, verbs, w)
    Panel.justify(fit_prompt(prompt, fit, w), fit, w)
  end

  defp fit_verbs(_prompt, [], _w), do: []
  # The head verb is load-bearing (Esc, or a face's lone primary action) — never dropped.
  defp fit_verbs(_prompt, [_only] = verbs, _w), do: verbs_row(verbs)

  defp fit_verbs(prompt, verbs, w) do
    runs = verbs_row(verbs)

    if w - Panel.row_width(prompt) - Panel.row_width(runs) >= 1,
      do: runs,
      else: fit_verbs(prompt, Enum.drop(verbs, -1), w)
  end

  # Room for the head verb comes from the prompt's typed buffer (style :buf) — the least
  # load-bearing text, clipped from the tail of each :buf run in turn before anything else gives.
  defp fit_prompt(prompt, verbs, w) do
    over = Panel.row_width(prompt) - (w - Panel.row_width(verbs) - 1)

    if over > 0 do
      {clipped, _left} = Enum.map_reduce(prompt, over, &clip_buf/2)
      clipped
    else
      prompt
    end
  end

  defp clip_buf({text, :buf}, left) when left > 0 do
    keep = max(String.length(text) - left, 0)
    {{String.slice(text, 0, keep), :buf}, left - (String.length(text) - keep)}
  end

  defp clip_buf(run, left), do: {run, left}

  # Right-aligned verbs: no trailing separator (it would push the last verb off the edge), one
  # trailing space so the row does not butt against the frame.
  defp verbs_row(verbs) do
    verbs
    |> Enum.map_intersperse([{"  ", :dim}], fn {key, label} -> [{key, :header}, {" #{label}", :dim}] end)
    |> List.flatten()
    |> Kernel.++([{" ", :normal}])
  end

  defp hints_row(hints) do
    Enum.flat_map(hints, fn
      {key, label} when is_binary(label) -> [{key, :header}, {" #{label}", :dim}, {"   ", :dim}]
      {text, style} -> [{text, style}]
    end)
  end
end
