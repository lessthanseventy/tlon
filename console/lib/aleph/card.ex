defmodule Console.Card do
  @moduledoc """
  The cockpit visual system's shared primitives (Slice D, 2026-09-01). One module so the card idiom
  and the colour language can't drift between surfaces (Home, Tickets, Notes, CREW).

  **Colour tiers** (all resolve to `Console.Style` atoms):
  - `status_color/1` — the SIGNAL tier (card gutter + `status_dot/1`): working·blocked·awaiting·
    open·done·idle.
  - `archetype_color/1` — the IDENTITY tier: a coworker archetype's stable hue, reused as the
    `workspace_hue/1` cycle.

  **Card shapes:**
  - `gutter_card/3` — a status-coloured `▌` gutter + header runs + indented body rows. For LISTS.
  - `boxed_card/4` — a bordered box, status-coloured frame + title, framed body rows. For the FEW
    big items (Home workspace cards).

  Rows are `Console.Panel` rows (`[{text, style}]`); a card returns a list of rows.
  """
  alias Console.Panel

  @gutter "▌"

  @doc "A status → signal-colour style atom (unknown → :dim)."
  def status_color(:working), do: :st_working
  def status_color(:blocked), do: :st_blocked
  def status_color(:failing), do: :st_blocked
  def status_color(:awaiting), do: :st_await
  def status_color(:open), do: :st_open
  def status_color(:stalled), do: :st_await
  def status_color(:done), do: :st_done
  def status_color(:merged), do: :st_done
  def status_color(:idle), do: :st_idle
  def status_color(:off), do: :st_idle
  def status_color(_), do: :dim

  @doc "A filled status dot `●` in the status colour — the at-a-glance signal on a card."
  def status_dot(status), do: {"●", status_color(status)}

  @doc "A coworker archetype → identity hue style atom (unknown → :normal)."
  def archetype_color(:surveyor), do: :arch_surveyor
  def archetype_color(:builder), do: :arch_builder
  def archetype_color(:reviewer), do: :arch_reviewer
  def archetype_color(:planner), do: :arch_planner
  def archetype_color(:assistant), do: :arch_assistant
  def archetype_color(a) when is_binary(a), do: archetype_color(safe_atom(a))
  def archetype_color(_), do: :normal

  @hues [:arch_surveyor, :arch_builder, :arch_reviewer, :arch_planner, :arch_assistant]

  @doc """
  A workspace's identity hue — an explicit `knobs["hue"]` when set, else cycled from the id so each
  workspace draws a stable colour (its spine tile + Home card border). Unknown → :accent.
  """
  def workspace_hue(%{knobs: %{"hue" => hue}}) when is_binary(hue), do: safe_atom(hue)
  def workspace_hue(%{id: id}) when is_integer(id), do: Enum.at(@hues, rem(id, length(@hues)))
  def workspace_hue(_), do: :accent

  @doc """
  A gutter card: a status-coloured `▌ ` gutter opening the header row, then each body row indented
  two spaces (so a folded card is one line, an open one nests its body). `header_runs` is a list of
  `{text, style}`; `body_rows` a list of rows.
  """
  def gutter_card(header_runs, body_rows \\ [], status \\ :open) do
    gutter = {@gutter <> " ", status_color(status)}
    [[gutter | header_runs] | Enum.map(body_rows, fn row -> [{"  ", :normal} | row] end)]
  end

  @doc """
  A boxed card `w` wide: a status-coloured frame (`╭─ title ─╮` / `│ … │` / `╰──╯`) around
  `body_rows` (each padded + framed). Title truncates if it can't fit. For the few big items.
  """
  def boxed_card(title, body_rows, w, status \\ :open) when is_binary(title) do
    frame = status_color(status)
    inner = max(w - 4, 1)
    title = String.slice(title, 0, max(w - 6, 1))
    fill = max(w - 5 - String.length(title), 0)

    top = [{"╭─ ", frame}, {title, :label}, {" " <> String.duplicate("─", fill), frame}, {"╮", frame}]
    bottom = [{"╰" <> String.duplicate("─", max(w - 2, 0)) <> "╯", frame}]

    body =
      Enum.map(body_rows, fn row ->
        [{"│ ", frame}] ++ Panel.pad(row, inner, :normal) ++ [{" │", frame}]
      end)

    [top] ++ body ++ [bottom]
  end

  # A best-effort atom for a known style/archetype name — an unknown string never crashes a paint,
  # it falls through to the caller's default via the existing atoms table.
  defp safe_atom(s) do
    String.to_existing_atom(s)
  rescue
    ArgumentError -> :normal
  end
end
