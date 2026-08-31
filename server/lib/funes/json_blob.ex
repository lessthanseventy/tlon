defmodule Server.JsonBlob do
  @moduledoc """
  Pull the ONE valid JSON object out of decorated CLI/model output. Models are told
  "ONLY JSON" and decorate anyway — try the whole trimmed output, then every
  first-brace..closing-brace candidate from the END inward, so trailing brace-bearing
  prose can't corrupt the real object. Shared by the eval judge and the memory extractor.
  """

  @doc """
  The first candidate blob that decodes AND satisfies `shape` (decoded map → result | nil).
  Returns the shape's result, or nil when nothing valid is found.
  """
  def first_valid(out, shape) do
    out
    |> candidates()
    |> Enum.find_value(fn blob ->
      case JSON.decode(blob) do
        {:ok, decoded} -> shape.(decoded)
        _ -> nil
      end
    end)
  end

  defp candidates(out) do
    trimmed = String.trim(out)

    case :binary.match(trimmed, "{") do
      :nomatch ->
        []

      {start, _} ->
        tail = binary_part(trimmed, start, byte_size(trimmed) - start)
        closers = for {i, _} <- :binary.matches(tail, "}"), do: binary_part(tail, 0, i + 1)
        [trimmed | Enum.reverse(closers)]
    end
  end
end
