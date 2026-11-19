defmodule Server.Home.Proposals do
  @moduledoc """
  What the home says and does about the proposals sources make (`Server.Proposal`): the list as the
  chat and the desktop say it, the operator's yes and no (a tap, or an ask the reader read), and the
  line for a waiting-on a source has since resolved. Nothing here is said when a proposal arrives:
  the list goes out in the morning message and the daily list, or when the operator asks.
  """

  alias Server.Proposal

  @shown 5

  @doc """
  The open proposals as text and the `say` options that put an Add and a No button under each shown:
  `Proposed (3):`, numbered, the first #{@shown}, then `and N more`. nil when none are open.
  """
  @spec say([Proposal.t()]) :: {String.t(), keyword()} | nil
  def say([]), do: nil

  def say(open) do
    shown = Enum.take(open, @shown)
    choices = for {p, n} <- Enum.with_index(shown, 1), do: [{"Add #{n}", "p:#{p.id}:take"}, {"No #{n}", "p:#{p.id}:no"}]
    {text(open), choices: choices}
  end

  @doc "The open proposals as plain text, for a surface with no buttons; nil when none are open."
  @spec plain([Proposal.t()]) :: String.t() | nil
  def plain([]), do: nil
  def plain(open), do: text(open)

  @doc "The waiting-ons a source has resolved, as a block of lines: `Settled:`, then `• Reviewed: <title>` each. nil when none."
  @spec settled([Proposal.t()]) :: String.t() | nil
  def settled([]), do: nil

  def settled(rows), do: Enum.join(["Settled:" | Enum.map(rows, &"• #{&1.done_text || "Done: #{&1.text}"}")], "\n")

  @doc """
  What the daily list has after the open things: the `settled` waiting-ons, then the open proposals
  with their buttons. nil when there is neither.
  """
  @spec tail([Proposal.t()], [Proposal.t()]) :: {String.t(), keyword()} | nil
  def tail(open, settled) do
    {proposed, opts} = say(open) || {nil, []}

    case Enum.reject([settled(settled), proposed], &is_nil/1) do
      [] -> nil
      parts -> {Enum.join(parts, "\n\n"), opts}
    end
  end

  @doc """
  The reply to the operator's `choice` (`"take"` or `"no"`) on the proposal `id` from `via` at `now`:
  what was done, and what is still proposed under its buttons. `:gone` when it is no longer open.
  """
  @spec tap(String.t(), integer(), String.t(), DateTime.t()) :: {String.t(), keyword()} | :gone
  def tap(via, id, choice, now) do
    case act(choice, via, id, now) do
      nil -> :gone
      line -> join(line, Proposal.open())
    end
  end

  @doc """
  What the operator asked of the proposals (a reading of kind `proposals`, `take` or `dismiss`,
  with `ids`): the reply and its options. An id that is none of the open ones is passed over; when
  none is, the list is said after that.
  """
  @spec ask(map(), String.t(), DateTime.t()) :: {String.t(), keyword()}
  def ask(%{kind: "proposals"}, _via, _now), do: listed("Nothing proposed.")

  def ask(%{kind: kind, ids: ids}, via, now) do
    choice = if kind == "take", do: "take", else: "no"

    case for(id <- ids, line = act(choice, via, id, now), do: line) do
      [] ->
        {text, opts} = listed("Nothing proposed.")
        {"I couldn't tell which one you meant.\n\n" <> text, opts}

      lines ->
        join(Enum.join(lines, "\n"), Proposal.open())
    end
  end

  defp listed(none), do: say(Proposal.open()) || {none, []}

  defp act("take", via, id, now), do: said(Proposal.take(via, id, now), "added: ")
  defp act("no", _via, id, _now), do: said(Proposal.dismiss(id), "left out: ")
  defp act(_choice, _via, _id, _now), do: nil

  defp said({:ok, p}, prefix), do: prefix <> p.text
  defp said(:not_found, _prefix), do: nil

  defp join(line, open) do
    case say(open) do
      nil -> {line, []}
      {text, opts} -> {line <> "\n\n" <> text, opts}
    end
  end

  defp text(open) do
    shown = Enum.take(open, @shown)
    lines = for {p, n} <- Enum.with_index(shown, 1), do: "#{n}. #{p.text}#{why(p)}"
    more = if length(open) > @shown, do: ["and #{length(open) - @shown} more"], else: []
    Enum.join(["Proposed (#{length(open)}):" | lines] ++ more, "\n")
  end

  defp why(%Proposal{why: nil}), do: ""
  defp why(%Proposal{why: why}), do: " (#{why})"
end
