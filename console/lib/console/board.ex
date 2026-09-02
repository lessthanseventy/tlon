defmodule Console.Board do
  @moduledoc """
  The render half of the cockpit: flatten placed panels into a list of styled cells, then paint
  them. `compose/3` is a pure, testable value (no TTY) — each panel's styled rows are walked into
  `%{x, y, ch, fg, bg}` cells at the panel's rect offset, semantic styles resolved to truecolor
  by `Console.Style`. `paint/1` blits that list through the termbox2 NIF (output-only; input +
  resize come from `Raxol.Terminal.Driver`, see `Console.Cockpit`).
  """
  alias Console.Panel
  alias Console.Style

  @type placement :: {module(), term(), Panel.rect()}
  @type cell :: %{
          x: non_neg_integer(),
          y: non_neg_integer(),
          ch: char(),
          fg: integer(),
          bg: integer()
        }

  @spec compose([placement()], pos_integer(), pos_integer()) :: [cell()]
  def compose(placements, _width, _height) do
    Enum.flat_map(placements, fn {panel, data, rect} ->
      panel
      |> safe_rows(data, rect)
      |> Enum.with_index()
      |> Enum.flat_map(fn {row, i} -> row_cells(row, rect.x, rect.y + i) end)
    end)
  end

  # A panel render must NEVER crash the cockpit — it's a long-running TTY app where one raise (a bad
  # row shape, a NotLoaded assoc) would take the whole screen down, silently under the alt-screen. So
  # a raise degrades THAT panel to an error row and is logged (the bug still surfaces via the crash
  # log), while every other panel paints. This is why per-renderer catch-alls aren't needed: a
  # missing clause stays a loud failure — just a survivable, recorded one, not a dead cockpit.
  defp safe_rows(panel, data, rect) do
    Panel.render_scroll(panel, data, rect)
  rescue
    e ->
      Console.CrashLog.append(
        "panel render error: #{inspect(panel)}",
        Exception.format(:error, e, __STACKTRACE__)
      )

      [[{"⚠ #{panel_name(panel)} render error — see #{Console.CrashLog.path()}", :error}]]
  end

  defp panel_name(panel) when is_atom(panel), do: panel |> Atom.to_string() |> String.split(".") |> List.last()
  defp panel_name(panel), do: inspect(panel)

  @doc """
  `safe_rows/3`'s twin, one layer up: guard a cockpit READ (the per-frame server/tmux assembly —
  crew, presence, logbook…) so a raise OR an exit (a down server GenServer) degrades that one read
  to `fallback` and a crash-log entry instead of taking the whole cockpit down. Panels already
  tolerate their read's empty shape, so a degraded read renders as that panel's quiet state.
  """
  @spec safe_read(atom(), term(), (-> term())) :: term()
  def safe_read(label, fallback, fun) do
    fun.()
  rescue
    e ->
      Console.CrashLog.append("read error: #{label}", Exception.format(:error, e, __STACKTRACE__))
      fallback
  catch
    kind, reason ->
      Console.CrashLog.append("read error: #{label}", Exception.format(kind, reason, __STACKTRACE__))
      fallback
  end

  @doc """
  Turn already-rendered rows into cells at the rect's offset — the guts of `compose/3` for a single
  panel's rows, exposed so a caller that renders + windows rows itself (e.g. a scrolling loop) can
  paint them without a second `render/2` pass.
  """
  @spec rows_to_cells([Panel.row()], Panel.rect()) :: [cell()]
  def rows_to_cells(rows, %{x: x, y: y}) do
    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, i} -> row_cells(row, x, y + i) end)
  end

  # Walk a row's runs left-to-right, emitting one cell per grapheme with the run's colours.
  defp row_cells(row, x0, y) do
    {cells, _x} =
      Enum.reduce(row, {[], x0}, fn {text, style}, {acc, x} ->
        {fg, bg} = Style.fg_bg(style)

        {chars, next_x} =
          text
          |> String.graphemes()
          |> Enum.map_reduce(x, fn g, cx ->
            {%{x: cx, y: y, ch: codepoint(g), fg: fg, bg: bg}, cx + 1}
          end)

        {[chars | acc], next_x}
      end)

    cells |> Enum.reverse() |> List.flatten()
  end

  # A raw C0/C1 control byte or DEL painted straight to the terminal would be read as the start
  # of an escape sequence — a stray ESC shifts the whole screen's colours. Neutralise here, the
  # one boundary every cell passes through, so no panel can leak one.
  defp codepoint(grapheme) do
    cp = grapheme |> String.to_charlist() |> hd()
    if cp < 0x20 or (cp >= 0x7F and cp <= 0x9F), do: 0x20, else: cp
  end

  @doc "Blit composed cells to the real screen via termbox2. Assumes `tb_init` already ran."
  @spec paint([cell()]) :: :ok
  def paint(cells) do
    :termbox2_nif.tb_clear()

    Enum.each(cells, fn %{x: x, y: y, ch: ch, fg: fg, bg: bg} ->
      :termbox2_nif.tb_set_cell(x, y, ch, fg, bg)
    end)

    :termbox2_nif.tb_present()
    :ok
  end
end
