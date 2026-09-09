defmodule Console.Panel.Menu do
  @moduledoc """
  A small overlay menu (Slice 3.5): the right-click workspace context menu and the Set-icon picker.
  A list of labeled `items` (each `%{label, action, danger?, icon?}`), one cursor-highlighted. The
  Cockpit places it ON TOP of the frame (a Border around this content) at the click position, and
  routes a click/Enter on a row to its `action` via `{:menu_pick, action}`.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [pad: 3]

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{items: items} = data, rect) do
    cursor = data[:cursor]

    items
    |> Enum.with_index()
    |> Enum.drop(offset(data, rect))
    |> Enum.map(fn {item, i} -> row(item, i == cursor, rect.w) end)
    |> Console.Panel.clip(rect)
  end

  def render(_data, rect), do: Console.Panel.clip([], rect)

  defp row(item, selected?, w) do
    style =
      cond do
        selected? -> :selected
        Map.get(item, :danger) -> :label
        true -> :normal
      end

    lead = if selected?, do: "▸ ", else: "  "
    pad([{lead, style}, {item.label, style}], w, if(selected?, do: :selected, else: :normal))
  end

  @impl Console.Panel
  def pick(%{items: items} = data, rect, local_y) do
    case Enum.at(items, offset(data, rect) + local_y) do
      %{action: action} -> {:menu_pick, action}
      _ -> nil
    end
  end

  def pick(_data, _rect, _local_y), do: nil

  # More items than rows: the list scrolls so the cursor row is always on screen (a long channel
  # list, a short frame); nothing is ever drawn past the box.
  defp offset(data, rect), do: max((data[:cursor] || 0) - rect.h + 1, 0)

  @doc "The widest row (the 2-cell lead + the label) — the Cockpit sizes the overlay box to this."
  def width(%{items: items}), do: items |> Enum.map(&(String.length(&1.label) + 2)) |> Enum.max(fn -> 0 end)
end
