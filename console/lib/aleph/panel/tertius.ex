defmodule Console.Panel.Tertius do
  @moduledoc """
  The permanent tertius command line (Slice 3, 2026-08-30): the bottom band of the Tlön center,
  where the Ticker pulse used to live. Always shows the orchestrator input (`tertius ▸ …`) plus a
  short log of the last few dispatch RECEIPTS — a command line you talk into with no confirmation
  is the exact failure this repo opened on, so the log keeps the last actions visible.

  Data is `%{receipts: [String.t()], input: input_map | nil}`. When the orchestrate input is
  active its buffer renders live with a caret; otherwise a placeholder invites a command. Pure
  render — the cockpit assembles the receipts + input.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2]

  @placeholder "‹file a ticket · tell @x · remember… — click or : to focus›"

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{} = data, rect) do
    log =
      (data[:receipts] || [])
      |> Enum.take(2)
      |> Enum.reverse()
      |> Enum.map(&line("  #{&1}", :dim))

    Console.Panel.clip(log ++ [input_row(data[:input])], rect)
  end

  # The live orchestrate buffer with a trailing caret, or the idle placeholder.
  defp input_row(%{kind: :orchestrate, buffer: buffer}),
    do: [{"tertius ▸ ", :accent}, {buffer, :normal}, {"▎", :accent}]

  defp input_row(_idle), do: [{"tertius ▸ ", :accent}, {@placeholder, :dim}]
end
