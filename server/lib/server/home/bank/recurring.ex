defmodule Server.Home.Bank.Recurring do
  @moduledoc """
  What a list of bank transactions says about the days ahead, in plain arithmetic with no IO.

  A transaction (`txn/1`) has `cents` as Plaid gives it: positive is money out, negative money in.
  A **series** is one merchant (its normalised `merchant_name`, else `name`) with at least three
  posted charges at a steady rhythm, the latest run of them: the gaps all within one of weekly
  (5 to 9 days), fortnightly (11 to 17), monthly (26 to 34) or yearly (355 to 375; two charges do, a
  year being all Plaid gives), and every amount within 10% of the latest. Pending transactions never count; several on one day count once. Its
  `next` date and `amount` come from the latest charge. `series/2` finds them for outflows
  (`:out`) or deposits (`:in`); amounts are integers of cents, magnitudes in a series.
  """

  @type txn :: %{
          id: String.t(),
          account_id: String.t() | nil,
          cents: integer(),
          date: Date.t(),
          key: String.t(),
          label: String.t(),
          pending: boolean()
        }
  @type series :: %{
          key: String.t(),
          label: String.t(),
          period: :weekly | :fortnightly | :monthly | :yearly,
          amount: pos_integer(),
          last: Date.t(),
          next: Date.t(),
          count: pos_integer(),
          was: pos_integer() | nil,
          account_id: String.t() | nil
        }

  @bands [weekly: 5..9, fortnightly: 11..17, monthly: 26..34, yearly: 355..375]
  @label_max 40

  @doc """
  A stored row (`%{"id", "account_id", "cents", "date", "name", "merchant", "pending"}`) as a
  transaction, or nil when its date or amount is not usable. The label is the merchant's name else the
  description, as one short line of plain text: it came from outside and is only ever shown.
  """
  @spec txn(map()) :: txn() | nil
  def txn(%{"id" => id, "cents" => cents, "date" => date} = row) when is_binary(id) and is_integer(cents) do
    with {:ok, date} <- Date.from_iso8601(date),
         label when label != "" <- label(row["merchant"], row["name"]) do
      %{
        id: id,
        account_id: row["account_id"],
        cents: cents,
        date: date,
        key: key(label),
        label: label,
        pending: row["pending"] == true
      }
    else
      _ -> nil
    end
  end

  def txn(_), do: nil

  @doc "The normalised form of a merchant name that series are matched on: lower case, letters and digits in single-space runs."
  @spec key(String.t()) :: String.t()
  def key(label), do: label |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, " ") |> String.trim()

  defp label(merchant, name) do
    [merchant, name]
    |> Enum.find("", &(is_binary(&1) and String.trim(&1) != ""))
    |> line(@label_max)
  end

  @doc "Outside `text` as one plain line of at most `max` characters: control characters and runs of space become one space."
  @spec line(term(), pos_integer()) :: String.t()
  def line(text, max) when is_binary(text),
    do: text |> String.replace(~r/[\p{C}\s]+/u, " ") |> String.trim() |> String.slice(0, max)

  def line(_, _max), do: ""

  @doc "The series among `txns` in the direction `:out` (charges) or `:in` (deposits)."
  @spec series([txn()], :out | :in) :: [series()]
  def series(txns, direction) do
    txns
    |> Enum.filter(&(not &1.pending and direction?(&1, direction)))
    |> Enum.group_by(& &1.key)
    |> Enum.flat_map(fn {_key, group} -> run(group) end)
    |> Enum.sort_by(&{&1.next, &1.key})
  end

  defp direction?(%{cents: cents}, :out), do: cents > 0
  defp direction?(%{cents: cents}, :in), do: cents < 0

  defp run(group) do
    [last | older] = group |> Enum.sort_by(& &1.date, {:desc, Date}) |> Enum.uniq_by(& &1.date)

    with [previous | _] <- older,
         {period, band} <- band(Date.diff(last.date, previous.date)),
         {steady, rest} = steady([last], older, band, abs(last.cents)),
         true <- length(steady) >= minimum(period) do
      [
        %{
          key: last.key,
          label: last.label,
          period: period,
          amount: abs(last.cents),
          last: last.date,
          next: next(last.date, period),
          count: length(steady),
          was: was(steady, rest, band, period),
          account_id: last.account_id
        }
      ]
    else
      _ -> []
    end
  end

  defp band(gap) do
    Enum.find(@bands, fn {_period, range} -> gap in range end)
  end

  defp steady([head | _] = taken, [older | rest] = all, band, amount) do
    if Date.diff(head.date, older.date) in band and close?(abs(older.cents), amount),
      do: steady([older | taken], rest, band, amount),
      else: {taken, all}
  end

  defp steady(taken, [], _band, _amount), do: {taken, []}

  defp close?(a, b), do: abs(a - b) * 10 <= b

  defp next(date, :weekly), do: Date.shift(date, day: 7)
  defp next(date, :fortnightly), do: Date.shift(date, day: 14)
  defp next(date, :monthly), do: Date.shift(date, month: 1)
  defp next(date, :yearly), do: Date.shift(date, year: 1)

  @doc "The series whose next date falls from `today` through `days` days after it."
  @spec due_within([series()], Date.t(), non_neg_integer()) :: [series()]
  def due_within(series, today, days),
    do: Enum.filter(series, &(Date.compare(&1.next, today) != :lt and Date.diff(&1.next, today) <= days))

  @doc """
  Charges that look doubled: two posted charges of one amount at one merchant within two days of each
  other, the later one in the last three days, and not a habit (three or more of that amount at that
  merchant inside six days). `%{key, label, cents, account_id, on}`, `on` the later date.
  """
  @spec doubles([txn()], Date.t()) :: [map()]
  def doubles(txns, today) do
    txns
    |> Enum.filter(&(not &1.pending and &1.cents > 0))
    |> Enum.group_by(&{&1.key, &1.cents})
    |> Enum.flat_map(fn {{_key, _cents}, group} -> doubled(Enum.sort_by(group, & &1.date, Date), today) end)
  end

  defp doubled(group, today) do
    group
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [a, b] ->
      Date.diff(b.date, a.date) in 0..2 and Date.diff(today, b.date) in 0..3 and
        Enum.count(group, &(abs(Date.diff(b.date, &1.date)) <= 6)) < 3
    end)
    |> Enum.map(fn [_a, b] -> %{key: b.key, label: b.label, cents: b.cents, account_id: b.account_id, on: b.date} end)
  end

  @doc """
  The series that are new: made by just enough charges (three, a yearly one two), the latest within
  the last ten days, with no older steady run at that rhythm behind them.
  """
  @spec new_series([series()], Date.t()) :: [series()]
  def new_series(series, today), do: Enum.filter(series, &(fresh?(&1, today) and &1.was == nil))

  @doc """
  The series that are a price change: just made by enough charges as `new_series/2` has it, but with
  an older steady run at that rhythm and another amount (`was`) behind them.
  """
  @spec price_changes([series()], Date.t()) :: [series()]
  def price_changes(series, today), do: Enum.filter(series, &(fresh?(&1, today) and &1.was != nil))

  @doc """
  `txns` without the transfers between the item's own accounts: a charge and a deposit of equal and
  opposite amounts on two different accounts within a day of each other. Neither is a charge or a
  deposit.
  """
  @spec without_transfers([txn()]) :: [txn()]
  def without_transfers(txns) do
    {charges, deposits} = Enum.split_with(txns, &(&1.cents > 0))

    {unpaired_charges, unpaired_deposits} =
      Enum.reduce(charges, {[], deposits}, fn charge, {kept, deposits} ->
        case Enum.split_while(deposits, &(not mirror?(charge, &1))) do
          {before, [_pair | after_]} -> {kept, before ++ after_}
          {_all, []} -> {[charge | kept], deposits}
        end
      end)

    unpaired_charges ++ unpaired_deposits
  end

  defp mirror?(charge, deposit),
    do:
      deposit.cents == -charge.cents and deposit.account_id != charge.account_id and
        abs(Date.diff(charge.date, deposit.date)) <= 1

  defp minimum(:yearly), do: 2
  defp minimum(_period), do: 3

  defp was([first | _], [candidate | tail], band, period) do
    with true <- Date.diff(first.date, candidate.date) in band,
         {older, _} = steady([candidate], tail, band, abs(candidate.cents)),
         true <- length(older) >= minimum(period) do
      abs(candidate.cents)
    else
      _ -> nil
    end
  end

  defp was(_steady, [], _band, _period), do: nil

  defp fresh?(series, today), do: series.count == minimum(series.period) and Date.diff(today, series.last) in 0..10
end
