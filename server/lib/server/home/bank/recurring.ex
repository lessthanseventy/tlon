defmodule Server.Home.Bank.Recurring do
  @moduledoc """
  What a list of bank transactions says about the days ahead, in plain arithmetic with no IO.

  A transaction (`txn/1`) has `cents` as Plaid gives it: positive is money out, negative money in.
  A **series** is one merchant (its normalised `merchant_name`, else `name`) with at least three
  posted charges at a steady rhythm, the latest run of them: the gaps all within one of weekly
  (5 to 9 days), fortnightly (11 to 17), monthly (26 to 34) or yearly (355 to 375; two charges do, a
  year being all Plaid gives). Amounts may vary: the series' `amount` is the median of the latest
  three charges (of the latest six for a deposit, whose amounts vary more), the run stops at a charge
  more than twice or less than half of that that falls on the rhythm, and `count` is the whole run.
  A lone charge that is that far off in amount and off the rhythm too (a tax or adjustment line
  between two regular charges, or after the newest) is passed over: the run goes on past it, and it
  is not counted. `was` is the amount of an
  older run of at least three charges at another amount, and `at_amount` how many of the latest
  charges are at the current one (within 10% of it): a real change of price. A merchant whose
  charges fall into two or more amount groups, each a steady series, and those series hold at least
  four fifths of its charges, and whose latest charges fall within one rhythm of each other, has those series (two subscriptions of one merchant) and no other; groups that follow each other are one series with a changed price.
  A merchant with ten or more charges in no steady rhythm (not one of three in a row whose two gaps
  are in one band), and more than twice as many as the series holds, is everyday spending and has
  none (51 irregular charges and a monthly-looking tail are not a bill; thirty games-store charges
  on irregular days are not either). A series' own older charges, an earlier price included, are
  steady and never count against it. Pending transactions never count; several on one day count once. Its `next` date comes from the
  latest charge. `series/2` finds them for outflows
  (`:out`) or deposits (`:in`); amounts are integers of cents, magnitudes in a series.

  A series is **live** (`live/2`) while its latest charge is within two rhythms plus the rhythm's
  tolerance of `today` (a yearly one: one rhythm plus 30 days), else it has **ended**: nothing is
  expected of it any more. Weekly is 7 days, fortnightly 14, monthly 30 and yearly 365 days, with a
  tolerance of 2, 3, 4 and 10 days, so the windows are 16, 31, 64 and 395 days.
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
          at_amount: pos_integer(),
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
    |> Enum.flat_map(fn {_key, group} -> key_series(group, direction) end)
    |> Enum.sort_by(&{&1.next, &1.key})
  end

  defp direction?(%{cents: cents}, :out), do: cents > 0
  defp direction?(%{cents: cents}, :in), do: cents < 0

  defp band(gap) do
    Enum.find(@bands, fn {_period, range} -> gap in range end)
  end

  defp close?(a, b), do: abs(a - b) * 10 <= b

  defp next(date, :weekly), do: Date.shift(date, day: 7)
  defp next(date, :fortnightly), do: Date.shift(date, day: 14)
  defp next(date, :monthly), do: Date.shift(date, month: 1)
  defp next(date, :yearly), do: Date.shift(date, year: 1)

  @doc "Whether two merchant keys name one merchant: equal, or one the other with more words after it (`shell` and `shell oil 57444`)."
  @spec same_merchant?(String.t(), String.t()) :: boolean()
  def same_merchant?(a, b), do: a == b or String.starts_with?(a, b <> " ") or String.starts_with?(b, a <> " ")

  @doc "The days either side of a series' expected date within which a charge of the merchant counts as that one arriving."
  @spec tolerance(series() | :weekly | :fortnightly | :monthly | :yearly) :: pos_integer()
  def tolerance(%{period: period}), do: tolerance(period)
  def tolerance(:weekly), do: 2
  def tolerance(:fortnightly), do: 3
  def tolerance(:monthly), do: 4
  def tolerance(:yearly), do: 10

  @doc "The series still live on `today`: the latest charge within the window the moduledoc names."
  @spec live([series()], Date.t()) :: [series()]
  def live(series, today), do: Enum.filter(series, &(Date.diff(today, &1.last) <= window(&1.period)))

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
  def new_series(series, today),
    do: Enum.filter(series, &(fresh?(&1, today) and &1.count == minimum(&1.period) and &1.was == nil))

  @doc """
  The series that are a price change: just made by enough charges as `new_series/2` has it, but with
  an older steady run at that rhythm and another amount (`was`) behind them.
  """
  @spec price_changes([series()], Date.t()) :: [series()]
  def price_changes(series, today),
    do: Enum.filter(series, &(fresh?(&1, today) and &1.at_amount == minimum(&1.period) and &1.was != nil))

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

  defp was(at_amount, [older | _] = rest, period) do
    chunk = Enum.take_while(rest, &close?(abs(&1.cents), abs(older.cents)))
    if length(at_amount) >= minimum(period) and length(chunk) >= minimum(period), do: abs(older.cents)
  end

  defp was(_at_amount, [], _period), do: nil

  defp fresh?(series, today), do: Date.diff(today, series.last) in 0..10

  defp window(:yearly), do: 365 + 30
  defp window(:monthly), do: 2 * 30 + tolerance(:monthly)
  defp window(:fortnightly), do: 2 * 14 + tolerance(:fortnightly)
  defp window(:weekly), do: 2 * 7 + tolerance(:weekly)

  defp key_series(group, direction) do
    charges = group |> Enum.sort_by(& &1.date, {:desc, Date}) |> Enum.uniq_by(& &1.date)
    parts = charges |> amount_clusters() |> Enum.flat_map(&List.wrap(detect(&1, direction)))
    covered = parts |> Enum.map(& &1.count) |> Enum.sum()

    found =
      case parts do
        [_, _ | _] when covered * 5 >= length(charges) * 4 ->
          if concurrent?(parts), do: parts, else: List.wrap(detect_past_stray(charges, direction))

        _ ->
          List.wrap(detect_past_stray(charges, direction))
      end

    explained = found |> Enum.map(& &1.count) |> Enum.sum()
    unexplained = unsteady(charges)
    if unexplained >= 10 and unexplained > 2 * explained, do: [], else: found
  end

  defp unsteady(charges) do
    steady =
      charges
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.filter(fn [a, b, c] -> same_band(a, b) == same_band(b, c) and same_band(a, b) != nil end)
      |> List.flatten()
      |> MapSet.new()

    length(charges) - MapSet.size(steady)
  end

  defp same_band(newer, older) do
    with {period, _band} <- band(Date.diff(newer.date, older.date)), do: period
  end

  defp detect_past_stray([stray | [kept | _] = rest] = charges, direction) do
    case detect(charges, direction) do
      nil ->
        with %{amount: amount, period: period} = found <- detect(rest, direction),
             false <- Date.diff(stray.date, kept.date) in @bands[period],
             false <- comparable?(abs(stray.cents), amount) do
          found
        else
          _ -> nil
        end

      found ->
        found
    end
  end

  defp detect_past_stray(charges, direction), do: detect(charges, direction)

  defp concurrent?(parts) do
    newest = parts |> Enum.map(& &1.last) |> Enum.max(Date)
    Enum.all?(parts, &(Date.diff(newest, &1.last) <= days(&1.period)))
  end

  defp days(:weekly), do: 7
  defp days(:fortnightly), do: 14
  defp days(:monthly), do: 30
  defp days(:yearly), do: 365

  defp amount_clusters(charges) do
    charges
    |> Enum.sort_by(&abs(&1.cents))
    |> Enum.reduce([], &cluster/2)
    |> Enum.map(fn {_low, members} -> Enum.sort_by(members, & &1.date, {:desc, Date}) end)
  end

  defp cluster(charge, [{low, members} | rest] = clusters) do
    if close?(abs(charge.cents), low),
      do: [{low, [charge | members]} | rest],
      else: [{abs(charge.cents), [charge]} | clusters]
  end

  defp cluster(charge, []), do: [{abs(charge.cents), [charge]}]

  defp detect([last, previous | _] = charges, direction) do
    with {period, band} <- band(Date.diff(last.date, previous.date)),
         run = rhythm_run(charges, band),
         level = level(run, direction),
         run = Enum.take_while(run, &comparable?(abs(&1.cents), level)),
         true <- length(run) >= minimum(period) do
      {at_amount, older} = Enum.split_while(run, &close?(abs(&1.cents), level))

      %{
        key: last.key,
        label: last.label,
        period: period,
        amount: level,
        last: last.date,
        next: next(last.date, period),
        count: length(run),
        at_amount: length(at_amount),
        was: was(at_amount, older, period),
        account_id: last.account_id
      }
    else
      _ -> nil
    end
  end

  defp detect(_charges, _direction), do: nil

  defp rhythm_run([first | rest], band), do: rhythm_run([first], rest, band)

  defp rhythm_run([head | _] = taken, [older | rest], band) do
    cond do
      Date.diff(head.date, older.date) in band -> rhythm_run([older | taken], rest, band)
      stray?(head, older, rest, band) -> rhythm_run(taken, rest, band)
      true -> Enum.reverse(taken)
    end
  end

  defp rhythm_run(taken, [], _band), do: Enum.reverse(taken)

  defp stray?(head, older, [kept | _], band),
    do: not comparable?(abs(older.cents), abs(head.cents)) and Date.diff(head.date, kept.date) in band

  defp stray?(_head, _older, [], _band), do: false

  defp level(run, direction) do
    recent = run |> Enum.take(recent(direction)) |> Enum.map(&abs(&1.cents)) |> Enum.sort()
    Enum.at(recent, div(length(recent), 2))
  end

  defp recent(:out), do: 3
  defp recent(:in), do: 6

  defp comparable?(a, level), do: a * 2 >= level and a <= level * 2
end
