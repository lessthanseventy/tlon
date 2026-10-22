defmodule Server.GeneratedParts do
  @moduledoc """
  One invented accessory a day per workspace, drawn by `Server.Generator` in the sprite row format and kept
  in `generated_part` (the library; nothing prunes it). `refresh_due/2` makes at most one model call a day:
  the output is parsed, checked by `Server.PartCheck`, and stored, or rejected and logged. A reject still
  counted against the generator's cap and is not retried. Off, capped or rejected means no row that day; the
  office wears nothing and shows no error. `library/1` is what `Server.ToyPool.day/1` serves.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Server.{Generator, JsonBlob, PartCheck, Repo}

  require Logger

  schema "generated_part" do
    field :workspace_id, :integer
    field :day, :date
    field :slot, :string
    field :front, :map
    field :side, :map
    field :back, :map
  end

  @doc "Every kept part of `ws`, oldest first: `[%{id, day, slot, front, side, back}]` (views are row-index → 12-char row)."
  def library(ws) do
    from(p in __MODULE__, where: p.workspace_id == ^ws, order_by: p.day)
    |> Repo.all()
    |> Enum.map(fn p ->
      %{id: id(p.day), day: Date.to_iso8601(p.day), slot: p.slot, front: p.front, side: p.side, back: p.back}
    end)
  end

  @doc "Invent and keep `day`'s part unless one is kept already: `{:ok, part}`, `{:ok, :fresh}` or `{:error, why}`."
  def refresh_due(ws, day \\ Date.utc_today()) do
    if Repo.exists?(from(p in __MODULE__, where: p.workspace_id == ^ws and p.day == ^day)) do
      {:ok, :fresh}
    else
      with {:ok, out} <- Generator.run(prompt(day)),
           {:ok, raw} <- parsed(out),
           {:ok, checked} <- check(raw, day) do
        row = struct!(__MODULE__, Map.merge(checked, %{workspace_id: ws, day: day}))
        Repo.insert!(row, on_conflict: :nothing, conflict_target: [:workspace_id, :day])
        {:ok, Map.merge(checked, %{id: id(day), day: Date.to_iso8601(day)})}
      end
    end
  end

  defp parsed(out) do
    case JsonBlob.first_valid(out, &part/1) do
      %{} = raw -> {:ok, raw}
      _ -> {:error, :unparsed}
    end
  end

  defp part(%{"part" => %{} = p}), do: p
  defp part(_), do: nil

  defp check(raw, day) do
    case PartCheck.validate(raw) do
      {:ok, _} = ok ->
        ok

      {:error, why} ->
        Logger.warning("generated part for #{day} rejected: #{inspect(why)}")
        {:error, {:rejected, why}}
    end
  end

  defp id(day), do: "gen:" <> Date.to_iso8601(day)

  defp prompt(day) do
    "You draw accessories for a pixel-art office of AI coworkers. Invent ONE new accessory for #{day}: a hat, a scarf or necklace, or a thing held in the hand. " <>
      "Each figure is a 12-wide grid. Give the accessory in three views (front, side, back) as rows, row numbers 0-17 (hats sit on rows 0-3, the neck is rows 9-10, the hand is rows 11-12), " <>
      "every row exactly 12 characters. Letters: . leaves the pixel alone, _ clears it, and y c g e w r o are colours (y yellow, c grey, g green, e teal, w white, r red, o orange). Use no other letter. " <>
      ~s(Reply with ONLY JSON: {"part": {"slot": "head"|"neck"|"hand", "front": {"3": "..yyyyyy...."}, "side": {…}, "back": {…}}})
  end
end
