defmodule Console.Panel.Rule do
  @moduledoc "A vertical column separator — the `│` gutter between the cockpit's regions."
  @behaviour Console.Panel

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(_data, %{h: h} = rect) do
    "│" |> Console.Panel.line(:separator) |> List.duplicate(h) |> Console.Panel.clip(rect)
  end
end
