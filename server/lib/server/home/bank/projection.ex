defmodule Server.Home.Bank.Projection do
  @moduledoc """
  Where the checking balance goes in the days ahead, worked out from the transactions kept: pure
  arithmetic, no IO and no clock (`today` is always passed in). Every number it returns is computed
  here; nothing is a guess dressed as a fact, and nothing is an opinion on the spending.

  `data` is `%{transactions: [Recurring.txn()], accounts: [map()]}`: transactions as
  `Server.Home.Bank.Recurring.txn/1` makes them (`cents` positive for money out), accounts as the
  keep stores them (`"id"`, `"type"`, `"subtype"`, `"current"`, `"available"`). Transfers between
  the accounts are dropped here. Only spendable accounts (`Server.Home.Bank.spendable?/1`) are
  projected.

  **Sign convention.** What you hand in is a magnitude: the cost of a purchase, the new size of a
  series. What comes back is the effect on the balance: money out is negative, money in positive.

  A series (`Recurring.series/2`) repeats at its rhythm from its latest charge; a monthly one keeps
  its day of the month, falling on the month's last day when it has none. Events start tomorrow.
  The horizon is capped at 180 days.

  **Overdue.** An expected event dated today or earlier with no charge of that merchant since (a
  posted or pending transaction on or after its date less half the width of the rhythm's band in
  `Recurring`) is overdue: it stays in the forecast on tomorrow, with `overdue: true` and
  `expected_on`, for a grace of half its rhythm (at most 14 days; a yearly one 30). Past the grace
  it is skipped: rolled to its next date and named in `basis.skipped` (caveat `:skipped_charge`).
  An overdue deposit is placed tomorrow too, and `basis.next_deposit` carries `overdue: true`. A
  pending charge of the series counts as the charge arriving: the available balance already holds
  it, so it is not counted again.

  **Everyday spending**, what is in no series: the posted outflows of the spendable accounts in the
  last 90 days (or the history there is), without series charges and transfers, are spread evenly
  over those days for the expected daily figure. Rolling 30-day totals of the same give the 25th
  and 75th percentile (nearest rank) as the low and high daily figures; under 30 days of history
  all three are equal and the caveat is `:short_history`. Per-day figures are the one place a
  total is rounded to a cent.
  """

  alias Server.Home.Bank
  alias Server.Home.Bank.Recurring

  @cap 180
  @window 90
  @month 30
  @afford_days 60
  @cushion_days 7
  @tolerance %{weekly: 2, fortnightly: 3, monthly: 4, yearly: 10}

  @type rhythm :: :weekly | :fortnightly | :monthly | :yearly | :once
  @type data :: %{transactions: [Recurring.txn()], accounts: [map()]}
  @type event :: %{
          date: Date.t(),
          amount_cents: integer(),
          name: String.t(),
          kind: :charge | :deposit,
          rhythm: rhythm(),
          count: non_neg_integer(),
          overdue: boolean(),
          expected_on: Date.t() | nil
        }
  @type day :: %{date: Date.t(), low_cents: integer(), expected_cents: integer(), high_cents: integer()}
  @type point :: %{date: Date.t(), balance_cents: integer()}
  @type everyday :: %{
          expected_daily_cents: non_neg_integer(),
          low_daily_cents: non_neg_integer(),
          high_daily_cents: non_neg_integer(),
          history_days: non_neg_integer()
        }
  @type caveat :: :pending_ignored | :short_history | :skipped_charge | :no_deposit_seen | :one_off_bills_unknown
  @type basis :: %{
          months_of_history: non_neg_integer(),
          series: non_neg_integer(),
          next_deposit: %{name: String.t(), date: Date.t(), overdue: boolean()} | nil,
          skipped: [String.t()],
          caveats: [caveat()]
        }
  @type forecast :: %{
          start_cents: integer(),
          until: Date.t(),
          clamped: boolean(),
          events: [event()],
          everyday: everyday(),
          days: [day()],
          lowest: point(),
          before_next_deposit: point() | nil,
          basis: basis()
        }
  @type verdict :: :covers | :tight | :short
  @type afford :: %{
          verdict: verdict(),
          worst_case: verdict(),
          with: forecast(),
          without: forecast(),
          shortfall_cents: pos_integer() | nil,
          short_on: Date.t() | nil,
          cushion_cents: integer()
        }
  @type change ::
          {:one_off, integer(), Date.t(), String.t()}
          | {:recurring, pos_integer(), :weekly | :fortnightly | :monthly | :yearly, Date.t(), String.t()}
          | {:drop, String.t()}
          | {:change, String.t(), pos_integer()}
  @type what_if :: %{
          clamped: boolean(),
          baseline: forecast(),
          changed: forecast(),
          difference: %{end_cents: integer(), lowest_cents: integer()}
        }
  @type query :: %{match: String.t() | nil, from: Date.t(), to: Date.t()}
  @type month :: %{month: String.t(), out_cents: integer(), in_cents: integer(), count: non_neg_integer()}
  @type history :: %{
          months: [month()],
          count: non_neg_integer(),
          largest: [%{date: Date.t(), name: String.t(), amount_cents: integer()}],
          average_out_cents: integer(),
          average_in_cents: integer()
        }
  @type subscription :: %{
          name: String.t(),
          amount_cents: integer(),
          rhythm: rhythm(),
          next: Date.t(),
          count: pos_integer(),
          was_cents: integer() | nil
        }

  @doc """
  The balance day by day from `today` to `until` (clamped to #{@cap} days ahead, saying so in
  `clamped`), with the expected charges and deposits and the everyday spending between.
  `{:error, :no_data}` with no accounts, no transactions or no spendable account.
  """
  @spec forecast(data(), Date.t(), Date.t()) :: {:ok, forecast()} | {:error, :no_data}
  def forecast(data, today, until) do
    with {:ok, ctx} <- context(data, today), do: {:ok, build(ctx, today, until, items(ctx, today))}
  end

  @doc """
  Whether a purchase of `amount_cents` on `on` is covered: the forecast with and without it, to the
  later of #{@afford_days} days and the second next deposit (within the cap). `:covers` when the
  lowest expected balance with it is at least the cushion (`opts[:cushion_cents]`, default seven days
  of expected everyday spending), `:tight` when it is zero or more, `:short` below zero, with the
  `shortfall_cents` at the lowest point and `short_on`, the first day below zero. `worst_case` is the
  same verdict on the low line. A date earlier than today counts as today; one past the 180-day cap
  is `{:error, :beyond_horizon}`, never a purchase left uncounted.
  """
  @spec afford(data(), Date.t(), pos_integer(), Date.t() | nil, keyword()) ::
          {:ok, afford()} | {:error, :no_data | :beyond_horizon}
  def afford(data, today, amount_cents, on \\ nil, opts \\ []) when is_integer(amount_cents) and amount_cents > 0 do
    on = on || today

    with :ok <- within(on, Date.add(today, @cap)),
         {:ok, ctx} <- context(data, today) do
      base = items(ctx, today)
      until = Enum.max([Date.add(today, @afford_days), second_deposit(ctx, base, today), on], Date)
      purchase = user_item("Purchase", -amount_cents, :once, on, today)
      without = build(ctx, today, until, base)
      with = build(ctx, today, until, [purchase | base])
      cushion = Keyword.get(opts, :cushion_cents, @cushion_days * ctx.everyday.expected_daily_cents)
      {short_on, shortfall} = shortfall(with.days)

      {:ok,
       %{
         verdict: verdict(Enum.min_by(with.days, & &1.expected_cents).expected_cents, cushion),
         worst_case: verdict(Enum.min(Enum.map(with.days, & &1.low_cents)), cushion),
         with: with,
         without: without,
         shortfall_cents: shortfall,
         short_on: short_on,
         cushion_cents: cushion
       }}
    end
  end

  @doc """
  The forecast to `until` as it is and with `changes` made: a `{:one_off, cost, date, name}`, a
  `{:recurring, cost, rhythm, from_date, name}`, a `{:drop, series_name}` or a
  `{:change, series_name, new_amount}`. A series is named by its merchant, in any case; an unknown
  one is `{:error, {:no_series, name, suggestions}}` with the nearest names. A one-off past the
  horizon (`until`, clamped to the cap) or a recurring change starting past the cap is
  `{:error, :beyond_horizon}`. `difference` is the change in the balance at the end and in the lowest
  point; `clamped` says the horizon was cut to the cap.
  """
  @spec what_if(data(), Date.t(), [change()], Date.t()) ::
          {:ok, what_if()} | {:error, :no_data | :beyond_horizon | {:no_series, String.t(), [String.t()]}}
  def what_if(data, today, changes, until) do
    cap = Date.add(today, @cap)
    horizon = Enum.min([until, cap], Date)

    with {:ok, ctx} <- context(data, today),
         base = items(ctx, today),
         {:ok, changed} <- apply_changes(base, changes, today, horizon, cap) do
      baseline = build(ctx, today, until, base)
      changed = build(ctx, today, until, changed)

      {:ok,
       %{
         clamped: baseline.clamped,
         baseline: baseline,
         changed: changed,
         difference: %{
           end_cents: List.last(changed.days).expected_cents - List.last(baseline.days).expected_cents,
           lowest_cents: changed.lowest.balance_cents - baseline.lowest.balance_cents
         }
       }}
    end
  end

  @doc """
  What went out and came in by calendar month from `from` through `to`, for the posted transactions
  (all accounts, transfers left out) whose merchant or name contains `match` in any case (nil is all).
  Months with nothing show zeros; the five largest are by size, either way; the averages are per
  month of the range. `{:error, :bad_range}` when `from` is after `to`.
  """
  @spec history(data(), Date.t(), query()) :: {:ok, history()} | {:error, :bad_range}
  def history(data, _today, %{from: from, to: to} = query) do
    if Date.compare(from, to) == :gt, do: {:error, :bad_range}, else: months_of(data, query)
  end

  @doc "The recurring outflow series for display, by next date: amounts are signed, `was_cents` the price before a change."
  @spec subscriptions(data(), Date.t()) :: [subscription()]
  def subscriptions(%{transactions: txns}, today) do
    txns
    |> Recurring.without_transfers()
    |> Recurring.series(:out)
    |> Enum.map(fn s ->
      item = series_item(s, :charge, -1, today)

      %{
        name: s.label,
        amount_cents: -s.amount,
        rhythm: s.period,
        next: first_date(item),
        count: s.count,
        was_cents: s.was && -s.was
      }
    end)
    |> Enum.sort_by(&{Date.to_erl(&1.next), &1.name})
  end

  defp contains?(_key, nil), do: true
  defp contains?(key, needle), do: String.contains?(key, needle)

  defp month(first, rows) do
    {out, into} = Enum.split_with(rows, &(&1.cents > 0))

    %{
      month: Calendar.strftime(first, "%Y-%m"),
      out_cents: -Enum.sum(Enum.map(out, & &1.cents)),
      in_cents: -Enum.sum(Enum.map(into, & &1.cents)),
      count: length(rows)
    }
  end

  defp context(%{transactions: [_ | _] = txns, accounts: [_ | _] = accounts}, today) do
    case Bank.spendable_available(accounts) do
      start when is_integer(start) ->
        ids = for account <- accounts, Bank.spendable?(account), do: account["id"]
        mine = txns |> Recurring.without_transfers() |> Enum.filter(&(&1.account_id in ids))
        out = Recurring.series(mine, :out)

        {:ok,
         %{
           start: start,
           out: out,
           deposits: Recurring.series(mine, :in),
           everyday: everyday(mine, out, today),
           pending?: Enum.any?(txns, & &1.pending),
           txns: mine,
           months: months_of_history(mine, today)
         }}

      _ ->
        {:error, :no_data}
    end
  end

  defp context(_data, _today), do: {:error, :no_data}

  defp months_of_history([], _today), do: 0

  defp months_of_history(mine, today), do: div(Date.diff(today, Enum.min(Enum.map(mine, & &1.date), Date)), @month)

  defp everyday(mine, out, today) do
    keys = MapSet.new(out, & &1.key)
    posted = Enum.filter(mine, &(not &1.pending and Date.compare(&1.date, today) != :gt))
    span = history_days(posted, today)
    from = Date.add(today, 1 - span)

    totals =
      posted
      |> Enum.filter(&(&1.cents > 0 and &1.key not in keys and Date.compare(&1.date, from) != :lt))
      |> Enum.group_by(& &1.date, & &1.cents)
      |> Map.new(fn {date, cents} -> {date, Enum.sum(cents)} end)

    per_day = for i <- 0..(span - 1)//1, do: Map.get(totals, Date.add(today, -i), 0)
    expected = per(Enum.sum(per_day), max(span, 1))

    {low, high} =
      if span < @month do
        {expected, expected}
      else
        sums = per_day |> Enum.chunk_every(@month, 1, :discard) |> Enum.map(&Enum.sum/1) |> Enum.sort()
        {min(per(rank(sums, 25), @month), expected), max(per(rank(sums, 75), @month), expected)}
      end

    %{expected_daily_cents: expected, low_daily_cents: low, high_daily_cents: high, history_days: span}
  end

  defp history_days([], _today), do: 0

  defp history_days(posted, today), do: min(Date.diff(today, Enum.min(Enum.map(posted, & &1.date), Date)) + 1, @window)

  defp rank(sorted, percent), do: Enum.at(sorted, max(div(length(sorted) * percent + 99, 100), 1) - 1)

  defp per(total, days), do: div(2 * total + days, 2 * days)

  defp items(ctx, today) do
    Enum.flat_map(ctx.out, &series_items(ctx, &1, :charge, -1, today)) ++
      Enum.flat_map(ctx.deposits, &series_items(ctx, &1, :deposit, 1, today))
  end

  defp series_items(ctx, series, kind, sign, today) do
    normal = series_item(series, kind, sign, Date.add(today, 1))

    cond do
      Date.compare(series.next, today) == :gt or arrived?(ctx.txns, series, sign) ->
        [normal]

      Date.diff(today, series.next) <= grace(series.period) ->
        [%{normal | overdue: true, anchor: normal.from, expected_on: series.next}, normal]

      true ->
        [%{normal | skipped: true}]
    end
  end

  defp arrived?(txns, series, sign) do
    since = Date.add(series.next, -@tolerance[series.period])
    Enum.any?(txns, &(&1.key == series.key and &1.cents * sign < 0 and Date.compare(&1.date, since) != :lt))
  end

  defp grace(:yearly), do: 30
  defp grace(:monthly), do: 14
  defp grace(:fortnightly), do: 7
  defp grace(:weekly), do: 3

  defp series_item(series, kind, sign, from) do
    %{
      name: series.label,
      key: series.key,
      kind: kind,
      amount: sign * series.amount,
      rhythm: series.period,
      anchor: series.last,
      from: from,
      count: series.count,
      overdue: false,
      expected_on: nil,
      skipped: false
    }
  end

  defp user_item(name, effect, rhythm, anchor, today) do
    %{
      name: name,
      key: Recurring.key(name),
      kind: if(effect < 0, do: :charge, else: :deposit),
      amount: effect,
      rhythm: rhythm,
      anchor: if(rhythm == :once, do: Enum.max([anchor, today], Date), else: anchor),
      from: today,
      count: 0,
      overdue: false,
      expected_on: nil,
      skipped: false
    }
  end

  defp dates(%{rhythm: :once, anchor: date, from: from}, until), do: single(date, from, until)
  defp dates(%{overdue: true, anchor: date, from: from}, until), do: single(date, from, until)
  defp dates(item, until), do: item |> occurrences() |> Enum.take_while(&(Date.compare(&1, until) != :gt))

  defp single(date, from, until),
    do: Enum.filter([date], &(Date.compare(&1, from) != :lt and Date.compare(&1, until) != :gt))

  defp occurrences(%{anchor: anchor, rhythm: rhythm, from: from}) do
    0
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&shift(anchor, rhythm, &1))
    |> Stream.drop_while(&(Date.compare(&1, from) == :lt))
  end

  defp shift(date, :weekly, k), do: Date.shift(date, day: 7 * k)
  defp shift(date, :fortnightly, k), do: Date.shift(date, day: 14 * k)
  defp shift(date, :monthly, k), do: Date.shift(date, month: k)
  defp shift(date, :yearly, k), do: Date.shift(date, year: k)

  defp first_date(%{overdue: true, anchor: date}), do: date
  defp first_date(item), do: item |> occurrences() |> Enum.at(0)

  defp events(items, until) do
    Enum.sort_by(
      for item <- items, date <- dates(item, until) do
        %{
          date: date,
          amount_cents: item.amount,
          name: item.name,
          kind: item.kind,
          rhythm: item.rhythm,
          count: item.count,
          overdue: item.overdue,
          expected_on: item.expected_on
        }
      end,
      &{Date.to_erl(&1.date), &1.amount_cents, &1.name}
    )
  end

  defp next_deposit(items) do
    items
    |> Enum.filter(&(&1.kind == :deposit and &1.rhythm != :once))
    |> Enum.map(&%{name: &1.name, date: first_date(&1), overdue: &1.overdue})
    |> Enum.min_by(&Date.to_erl(&1.date), fn -> nil end)
  end

  defp second_deposit(_ctx, items, today) do
    cap = Date.add(today, @cap)

    items
    |> Enum.filter(&(&1.kind == :deposit))
    |> events(cap)
    |> Enum.at(1, %{date: cap})
    |> Map.fetch!(:date)
  end

  defp build(ctx, today, until, items) do
    cap = Date.add(today, @cap)
    clamped = Date.compare(until, cap) == :gt
    until = if clamped, do: cap, else: until
    until = if Date.compare(until, today) == :lt, do: today, else: until
    events = events(items, until)
    effects = events |> Enum.group_by(& &1.date, & &1.amount_cents) |> Map.new(fn {d, a} -> {d, Enum.sum(a)} end)
    every = ctx.everyday

    {days, _} =
      Enum.map_reduce(0..Date.diff(until, today), ctx.start, fn i, running ->
        date = Date.add(today, i)
        running = running + Map.get(effects, date, 0)

        {%{
           date: date,
           low_cents: running - i * every.high_daily_cents,
           expected_cents: running - i * every.expected_daily_cents,
           high_cents: running - i * every.low_daily_cents
         }, running}
      end)

    deposit = next_deposit(items)
    skipped = for %{skipped: true, name: name} <- items, do: name

    %{
      start_cents: ctx.start,
      until: until,
      clamped: clamped,
      events: events,
      everyday: every,
      days: days,
      lowest: lowest(days),
      before_next_deposit: deposit && lowest(Enum.filter(days, &(Date.compare(&1.date, deposit.date) == :lt))),
      basis: %{
        months_of_history: ctx.months,
        series: length(ctx.out) + length(ctx.deposits),
        next_deposit: deposit,
        skipped: skipped,
        caveats:
          Enum.concat([
            if(ctx.pending?, do: [:pending_ignored], else: []),
            if(every.history_days < @month, do: [:short_history], else: []),
            if(skipped == [], do: [], else: [:skipped_charge]),
            if(deposit == nil, do: [:no_deposit_seen], else: []),
            [:one_off_bills_unknown]
          ])
      }
    }
  end

  defp lowest(days) do
    day = Enum.min_by(days, & &1.expected_cents)
    %{date: day.date, balance_cents: day.expected_cents}
  end

  defp verdict(low, cushion) when low >= cushion, do: :covers
  defp verdict(low, _cushion) when low >= 0, do: :tight
  defp verdict(_low, _cushion), do: :short

  defp shortfall(days) do
    case Enum.find(days, &(&1.expected_cents < 0)) do
      nil -> {nil, nil}
      day -> {day.date, -Enum.min(Enum.map(days, & &1.expected_cents))}
    end
  end

  defp within(date, limit), do: if(Date.compare(date, limit) == :gt, do: {:error, :beyond_horizon}, else: :ok)

  defp apply_changes(items, changes, today, horizon, cap) do
    Enum.reduce_while(changes, {:ok, items}, fn change, {:ok, items} ->
      case checked(change, horizon, cap) || apply_change(items, change, today) do
        {:error, _} = error -> {:halt, error}
        items -> {:cont, {:ok, items}}
      end
    end)
  end

  defp checked({:one_off, _cost, date, _name}, horizon, _cap), do: error_of(within(date, horizon))
  defp checked({:recurring, _cost, _rhythm, from, _name}, _horizon, cap), do: error_of(within(from, cap))
  defp checked(_change, _horizon, _cap), do: nil

  defp error_of(:ok), do: nil
  defp error_of(error), do: error

  defp apply_change(items, {:one_off, cost, date, name}, today) when is_integer(cost),
    do: [user_item(name, -cost, :once, date, today) | items]

  defp apply_change(items, {:recurring, cost, rhythm, from_date, name}, today) when cost > 0,
    do: [user_item(name, -cost, rhythm, from_date, today) | items]

  defp apply_change(items, {:drop, name}, _today) do
    with {:ok, key} <- series_key(items, name), do: Enum.reject(items, &(&1.key == key))
  end

  defp apply_change(items, {:change, name, cost}, _today) when cost > 0 do
    with {:ok, key} <- series_key(items, name) do
      Enum.map(items, fn
        %{key: ^key, amount: amount} = item -> %{item | amount: if(amount < 0, do: -cost, else: cost)}
        item -> item
      end)
    end
  end

  defp series_key(items, name) do
    key = Recurring.key(name)

    if Enum.any?(items, &(&1.key == key)),
      do: {:ok, key},
      else: {:error, {:no_series, name, suggestions(items, key)}}
  end

  defp suggestions(items, key) do
    items
    |> Enum.uniq_by(& &1.key)
    |> Enum.map(&{String.jaro_distance(&1.key, key), &1.name})
    |> Enum.filter(fn {score, _} -> score >= 0.6 end)
    |> Enum.sort(:desc)
    |> Enum.take(3)
    |> Enum.map(&elem(&1, 1))
  end

  defp months_of(%{transactions: txns}, %{match: match, from: from, to: to}) do
    needle = match && Recurring.key(match)

    rows =
      txns
      |> Recurring.without_transfers()
      |> Enum.filter(
        &(not &1.pending and Date.compare(&1.date, from) != :lt and Date.compare(&1.date, to) != :gt and
            contains?(&1.key, needle))
      )

    by_month = Enum.group_by(rows, &Date.beginning_of_month(&1.date))

    months =
      from
      |> Date.beginning_of_month()
      |> Stream.iterate(&Date.shift(&1, month: 1))
      |> Enum.take_while(&(Date.compare(&1, to) != :gt))

    entries = Enum.map(months, &month(&1, Map.get(by_month, &1, [])))

    {:ok,
     %{
       months: entries,
       count: length(rows),
       largest:
         rows
         |> Enum.sort_by(&abs(&1.cents), :desc)
         |> Enum.take(5)
         |> Enum.map(&%{date: &1.date, name: &1.label, amount_cents: -&1.cents}),
       average_out_cents: -per(-Enum.sum(Enum.map(entries, & &1.out_cents)), length(entries)),
       average_in_cents: per(Enum.sum(Enum.map(entries, & &1.in_cents)), length(entries))
     }}
  end
end
