defmodule Server.PartCheck do
  @moduledoc """
  The one gate a model-drawn sprite part passes before it is kept (`Server.GeneratedParts`): a slot the
  office can dress (head, neck, hand), all three views, each a map of row index (0..17) to a row of exactly
  12 characters, and only the gear colours. The colour list must stay in step with `office/test/wcag.test.ts`
  (LEGAL), which proves each reads at 3:1 on the room's backgrounds; the body colours (k f s p b h) are refused.
  """

  @slots ~w(head neck hand)
  @views [{"front", :front}, {"side", :side}, {"back", :back}]
  @width 12
  @rows 0..17
  @legal ~c"._ycgewro"

  @spec validate(term()) :: {:ok, %{slot: String.t(), front: map(), side: map(), back: map()}} | {:error, term()}
  def validate(%{"slot" => slot} = part) when slot in @slots do
    Enum.reduce_while(@views, {:ok, %{slot: slot}}, fn {key, atom}, {:ok, acc} ->
      case view(part[key]) do
        :ok -> {:cont, {:ok, Map.put(acc, atom, part[key])}}
        {:error, why} -> {:halt, {:error, {atom, why}}}
      end
    end)
  end

  def validate(%{"slot" => _}), do: {:error, :slot}
  def validate(_), do: {:error, :shape}

  defp view(rows) when is_map(rows) and map_size(rows) > 0 do
    Enum.find_value(rows, :ok, fn {k, row} -> if !row_ok?(k, row), do: {:error, {:row, k}} end)
  end

  defp view(_), do: {:error, :missing}

  defp row_ok?(k, row) when is_binary(k) and is_binary(row) do
    case Integer.parse(k) do
      {i, ""} when i in @rows -> byte_size(row) == @width and row |> String.to_charlist() |> Enum.all?(&(&1 in @legal))
      _ -> false
    end
  end

  defp row_ok?(_, _), do: false
end
