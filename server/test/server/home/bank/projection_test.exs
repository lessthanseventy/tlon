defmodule Server.Home.Bank.ProjectionTest do
  use ExUnit.Case, async: true

  alias Server.Home.Bank.Projection
  alias Server.Home.Bank.Recurring

  @today ~D[2026-11-20]
  @accounts [
    %{"id" => "a1", "type" => "depository", "subtype" => "checking", "current" => 500_000, "available" => 480_000},
    %{"id" => "s1", "type" => "depository", "subtype" => "savings", "current" => 9_000_000, "available" => 9_000_000}
  ]

  defp txn(date, cents, name, extra \\ %{}) do
    %{
      "id" => "#{name}-#{date}-#{cents}",
      "account_id" => "a1",
      "cents" => cents,
      "date" => Date.to_iso8601(date),
      "name" => name,
      "merchant" => nil,
      "pending" => false
    }
    |> Map.merge(extra)
    |> Recurring.txn()
  end

  defp repeated(name, cents, last, n, shift),
    do: for(i <- 0..(n - 1), do: txn(Date.shift(last, shift.(i)), cents, name))

  defp monthly(name, cents, last, n), do: repeated(name, cents, last, n, &[month: -&1])
  defp weekly(name, cents, last, n), do: repeated(name, cents, last, n, &[day: -7 * &1])

  defp everyday(n, cents \\ 3_000), do: for(i <- 1..n, do: txn(Date.add(@today, -i), cents, "Shop #{i}"))

  defp data(txns, accounts \\ @accounts), do: %{transactions: List.flatten(txns), accounts: accounts}

  defp base do
    data([
      monthly("Rent", 120_000, ~D[2026-10-27], 4),
      monthly("Salary", -300_000, ~D[2026-11-13], 4),
      weekly("Gym", 1_500, ~D[2026-11-17], 5),
      everyday(100)
    ])
  end

  defp forecast!(data, until \\ ~D[2027-01-20]) do
    assert {:ok, forecast} = Projection.forecast(data, @today, until)
    forecast
  end

  describe "forecast" do
    test "starts at the spendable available balance and lists the events at their rhythms" do
      f = forecast!(base())

      assert f.start_cents == 480_000

      assert f.events |> Enum.filter(&(&1.name == "Rent")) |> Enum.map(&{&1.date, &1.amount_cents}) ==
               [{~D[2026-11-27], -120_000}, {~D[2026-12-27], -120_000}]

      assert [%{date: ~D[2026-12-13], amount_cents: 300_000, kind: :deposit, rhythm: :monthly, count: 4}] =
               f.events |> Enum.filter(&(&1.name == "Salary")) |> Enum.take(1)

      assert f.basis.next_deposit == %{name: "Salary", date: ~D[2026-12-13], overdue: false}
      assert :one_off_bills_unknown in f.basis.caveats
      refute :short_history in f.basis.caveats
    end

    test "the end balance is the start plus the events minus everyday spending for each day" do
      f = forecast!(base(), ~D[2026-12-31])
      days = Date.diff(f.until, @today)
      events = f.events |> Enum.map(& &1.amount_cents) |> Enum.sum()

      assert List.last(f.days).expected_cents ==
               f.start_cents + events - f.everyday.expected_daily_cents * days

      assert length(f.days) == days + 1
      assert hd(f.days) == %{date: @today, low_cents: 480_000, expected_cents: 480_000, high_cents: 480_000}
    end

    test "the low line is never above the expected line, nor the high line below it" do
      for day <- forecast!(base()).days,
          do: assert(day.low_cents <= day.expected_cents and day.expected_cents <= day.high_cents)
    end

    test "the horizon is capped at 180 days and says so" do
      f = forecast!(base(), ~D[2030-01-01])
      assert f.clamped and f.until == Date.add(@today, 180)
      refute forecast!(base(), ~D[2026-12-01]).clamped
    end

    test "lowest and before_next_deposit" do
      f = forecast!(base(), ~D[2026-12-31])
      assert f.lowest.balance_cents == f.days |> Enum.map(& &1.expected_cents) |> Enum.min()

      before = Enum.filter(f.days, &(Date.compare(&1.date, ~D[2026-12-13]) == :lt))
      assert f.before_next_deposit.balance_cents == before |> Enum.map(& &1.expected_cents) |> Enum.min()
    end

    test "no deposit series gives no before_next_deposit and the caveat" do
      f = forecast!(data([monthly("Rent", 120_000, ~D[2026-10-27], 3), everyday(100)]))
      assert f.before_next_deposit == nil
      assert :no_deposit_seen in f.basis.caveats
    end

    test "no accounts, no transactions or no spendable account is no data" do
      assert {:error, :no_data} = Projection.forecast(data([everyday(10)], []), @today, @today)
      assert {:error, :no_data} = Projection.forecast(data([], @accounts), @today, @today)
      assert {:error, :no_data} = Projection.forecast(data([everyday(10)], tl(@accounts)), @today, @today)
    end

    test "an overdue charge inside the grace stays, tomorrow, and lowers the line" do
      late = data([monthly("Rent", 120_000, ~D[2026-10-17], 4), everyday(100)])
      f = forecast!(late, ~D[2026-12-31])

      assert [%{date: ~D[2026-11-21], amount_cents: -120_000, overdue: true, expected_on: ~D[2026-11-17]}, next] =
               f.events |> Enum.filter(&(&1.name == "Rent")) |> Enum.take(2)

      assert %{date: ~D[2026-12-17], overdue: false, expected_on: nil} = next
      assert Enum.at(f.days, 1).expected_cents == 480_000 - 120_000 - f.everyday.expected_daily_cents
      assert f.basis.skipped == []

      days = Date.diff(f.until, @today)
      events = f.events |> Enum.map(& &1.amount_cents) |> Enum.sum()
      assert List.last(f.days).expected_cents == 480_000 + events - f.everyday.expected_daily_cents * days
    end

    test "a charge that has arrived is not expected again, and a pending one is not counted twice" do
      posted = data([monthly("Rent", 120_000, ~D[2026-11-18], 4), everyday(100)])
      assert [%{date: ~D[2026-12-18], overdue: false}] = forecast!(posted, ~D[2026-12-31]).events

      pending =
        data([
          monthly("Rent", 120_000, ~D[2026-10-17], 4),
          txn(~D[2026-11-19], 120_000, "Rent", %{"pending" => true}),
          everyday(100)
        ])

      assert [%{date: ~D[2026-12-17], overdue: false}] = forecast!(pending, ~D[2026-12-31]).events
    end

    test "past the grace a charge is skipped, rolled forward, and named" do
      f = forecast!(data([monthly("Rent", 120_000, ~D[2026-10-01], 4), everyday(100)]), ~D[2026-12-31])

      assert [%{date: ~D[2026-12-01], overdue: false}] = f.events
      assert f.basis.skipped == ["Rent"]
      assert :skipped_charge in f.basis.caveats
    end

    test "an overdue deposit is placed tomorrow and bounds before_next_deposit there" do
      f = forecast!(data([monthly("Salary", -300_000, ~D[2026-10-17], 4), everyday(100)]), ~D[2026-12-31])

      assert f.basis.next_deposit == %{name: "Salary", date: ~D[2026-11-21], overdue: true}
      assert f.before_next_deposit.date == @today
    end

    test "pending transactions are named as ignored" do
      pending = txn(@today, 900, "Cafe", %{"pending" => true})
      assert :pending_ignored in forecast!(data([pending, base().transactions])).basis.caveats
    end

    test "a monthly charge dated the 31st falls on the last day of a short month and keeps the 31st after" do
      d = data([monthly("Loan", 10_000, ~D[2026-10-31], 3), everyday(100)])
      dates = forecast!(d, ~D[2027-03-31]).events |> Enum.filter(&(&1.name == "Loan")) |> Enum.map(& &1.date)

      assert dates == [~D[2026-11-30], ~D[2026-12-31], ~D[2027-01-31], ~D[2027-02-28], ~D[2027-03-31]]
    end

    test "weekly and fortnightly counts over a horizon" do
      d =
        data([
          weekly("Gym", 1_500, ~D[2026-11-17], 4),
          repeated("Cleaner", 5_000, ~D[2026-11-12], 4, &[day: -14 * &1]),
          everyday(100)
        ])

      f = forecast!(d, Date.add(@today, 28))

      assert Enum.count(f.events, &(&1.name == "Gym")) == 4
      assert Enum.count(f.events, &(&1.name == "Cleaner")) == 2
    end

    test "a yearly charge is there once or not at all" do
      yearly = [txn(~D[2025-12-05], 9_900, "Domain"), txn(~D[2024-12-05], 9_900, "Domain")]

      assert [%{date: ~D[2026-12-05]}] =
               Enum.filter(forecast!(data([yearly, everyday(100)]), ~D[2027-01-01]).events, &(&1.name == "Domain"))

      assert [] = Enum.filter(forecast!(data([yearly, everyday(100)]), ~D[2026-12-01]).events, &(&1.name == "Domain"))
    end

    test "recurring charges and transfers do not count toward everyday spending" do
      transfer = [
        txn(Date.add(@today, -3), 50_000, "To savings"),
        txn(Date.add(@today, -3), -50_000, "From checking", %{"account_id" => "s1"})
      ]

      only_shops = forecast!(data([everyday(100)]))
      with_rest = forecast!(data([everyday(100), monthly("Rent", 120_000, ~D[2026-10-27], 4), transfer]))

      assert with_rest.everyday.expected_daily_cents == only_shops.everyday.expected_daily_cents
      assert only_shops.everyday.expected_daily_cents == 2_967
    end

    test "under 30 days of history the three everyday figures are equal and the caveat is named" do
      f = forecast!(data([everyday(10)]))
      assert f.everyday.history_days == 11
      assert f.everyday.low_daily_cents == f.everyday.expected_daily_cents
      assert f.everyday.high_daily_cents == f.everyday.expected_daily_cents
      assert :short_history in f.basis.caveats
    end

    test "low and high come from the 25th and 75th percentile of rolling 30-day totals" do
      quiet = for i <- 61..90, do: txn(Date.add(@today, -i), 1_000, "Old #{i}")
      busy = for i <- 1..60, do: txn(Date.add(@today, -i), 4_000, "New #{i}")
      f = forecast!(data([quiet, busy]))

      assert f.everyday.low_daily_cents <= f.everyday.expected_daily_cents
      assert f.everyday.high_daily_cents == 4_000
      assert f.everyday.low_daily_cents < 4_000
    end
  end

  describe "afford" do
    defp afford!(data, cents, on \\ @today, opts \\ []) do
      assert {:ok, result} = Projection.afford(data, @today, cents, on, opts)
      result
    end

    test "a purchase lowers every day on and after its date by exactly its amount, none before" do
      a = afford!(base(), 12_345, ~D[2026-12-01])

      for {w, wo} <- Enum.zip(a.with.days, a.without.days) do
        expected = if Date.compare(w.date, ~D[2026-12-01]) == :lt, do: 0, else: 12_345
        assert wo.expected_cents - w.expected_cents == expected
        assert wo.low_cents - w.low_cents == expected
      end
    end

    test "a purchase today lowers today too" do
      a = afford!(base(), 1_000)
      assert hd(a.with.days).expected_cents == 479_000
    end

    test "the verdict turns at exactly the cushion and exactly zero" do
      base_low = afford!(base(), 1).without.lowest.balance_cents
      cushion = 50_000
      fits = base_low - cushion

      assert %{verdict: :covers, shortfall_cents: nil, short_on: nil} =
               afford!(base(), fits, @today, cushion_cents: cushion)

      assert afford!(base(), fits + 1, @today, cushion_cents: cushion).verdict == :tight
      assert afford!(base(), base_low, @today, cushion_cents: cushion).verdict == :tight
      assert %{verdict: :short, shortfall_cents: 1} = afford!(base(), base_low + 1, @today, cushion_cents: cushion)
    end

    test "short names the first day below zero" do
      a = afford!(base(), 470_000, @today, cushion_cents: 0)
      assert a.verdict == :short
      first = Enum.find(a.with.days, &(&1.expected_cents < 0))
      assert a.short_on == first.date
      assert a.shortfall_cents == -Enum.min(Enum.map(a.with.days, & &1.expected_cents))
    end

    test "the worst case judges the low line and the default cushion is a week of everyday spending" do
      a = afford!(base(), 1_000)
      assert a.cushion_cents == 7 * a.with.everyday.expected_daily_cents
      assert a.worst_case in [:covers, :tight, :short]
      assert afford!(base(), 1_000, @today, cushion_cents: 10_000_000).worst_case == :tight
      assert afford!(base(), 900_000).worst_case == :short
    end

    test "the horizon is the later of 60 days and the second next deposit" do
      a = afford!(base(), 1_000)
      assert Date.diff(a.with.until, @today) == 60
      assert a.with.until == a.without.until
    end
  end

  describe "what_if" do
    defp what_if!(changes, until \\ ~D[2027-01-20]) do
      assert {:ok, result} = Projection.what_if(base(), @today, changes, until)
      result
    end

    test "an empty list of changes equals the baseline" do
      r = what_if!([])
      assert r.changed == r.baseline
      assert r.difference == %{end_cents: 0, lowest_cents: 0}
    end

    test "dropping a series removes exactly its events, matched in any case" do
      r = what_if!([{:drop, "rEnT"}])
      assert r.changed.events == Enum.reject(r.baseline.events, &(&1.name == "Rent"))
      assert r.difference.end_cents == 240_000
    end

    test "a recurring change appears at its rhythm from its date" do
      r = what_if!([{:recurring, 2_000, :weekly, ~D[2026-12-01], "Course"}], ~D[2026-12-31])
      added = r.changed.events -- r.baseline.events

      assert Enum.map(added, & &1.date) == [
               ~D[2026-12-01],
               ~D[2026-12-08],
               ~D[2026-12-15],
               ~D[2026-12-22],
               ~D[2026-12-29]
             ]

      assert Enum.all?(added, &(&1.amount_cents == -2_000 and &1.name == "Course"))
    end

    test "a one-off is a single event and a change resizes a series" do
      r = what_if!([{:one_off, 7_000, ~D[2026-12-02], "Fridge"}, {:change, "salary", 350_000}], ~D[2026-12-31])

      assert Enum.any?(r.changed.events, &(&1.name == "Fridge" and &1.amount_cents == -7_000))
      assert Enum.any?(r.changed.events, &(&1.name == "Salary" and &1.amount_cents == 350_000))
      assert r.difference.end_cents == 50_000 - 7_000
    end

    test "an unknown series is an error with the nearest names" do
      assert {:error, {:no_series, "Rant", suggestions}} =
               Projection.what_if(base(), @today, [{:drop, "Rant"}], ~D[2026-12-31])

      assert "Rent" in suggestions
    end
  end

  describe "history" do
    defp history!(match, from, to) do
      assert {:ok, result} =
               Projection.history(data([everyday(5), special()]), @today, %{match: match, from: from, to: to})

      result
    end

    defp special do
      [
        txn(~D[2026-09-30], 1_000, "Corner Cafe"),
        txn(~D[2026-10-01], 2_000, "CORNER CAFE #2"),
        txn(~D[2026-10-31], 3_000, "corner cafe"),
        txn(~D[2026-11-02], -500, "Corner Cafe refund"),
        txn(~D[2026-11-03], 700, "Other", %{"pending" => true})
      ]
    end

    test "buckets by calendar month with the case-insensitive match, out and in apart" do
      h = history!("CAFE", ~D[2026-09-01], ~D[2026-11-30])

      assert h.months == [
               %{month: "2026-09", out_cents: -1_000, in_cents: 0, count: 1},
               %{month: "2026-10", out_cents: -5_000, in_cents: 0, count: 2},
               %{month: "2026-11", out_cents: 0, in_cents: 500, count: 1}
             ]

      assert h.count == 4
      assert h.average_out_cents == -2_000
      assert h.average_in_cents == 167
      assert hd(h.largest) == %{date: ~D[2026-10-31], name: "corner cafe", amount_cents: -3_000}
    end

    test "a nil match is everything posted, and pending and transfers stay out" do
      h = history!(nil, ~D[2026-11-01], ~D[2026-11-30])
      assert h.count == 5 + 1
      refute Enum.any?(h.largest, &(&1.name == "Other"))
    end

    test "the five largest" do
      assert length(history!(nil, ~D[2026-01-01], ~D[2026-12-31]).largest) == 5
    end
  end

  describe "subscriptions" do
    test "lists the outflow series with their next date and a changed price" do
      raised = for m <- [~D[2026-11-05], ~D[2026-10-05], ~D[2026-09-05]], do: txn(m, 1_299, "Stream")

      older = for m <- [~D[2026-08-05], ~D[2026-07-05], ~D[2026-06-05]], do: txn(m, 999, "Stream")
      subs = Projection.subscriptions(data([base().transactions, raised, older]), @today)

      assert %{amount_cents: -1_299, rhythm: :monthly, next: ~D[2026-12-05], was_cents: -999} =
               Enum.find(subs, &(&1.name == "Stream"))

      assert %{amount_cents: -120_000, was_cents: nil, count: 4} = Enum.find(subs, &(&1.name == "Rent"))
      refute Enum.any?(subs, &(&1.name == "Salary"))
      assert subs == Enum.sort_by(subs, &{Date.to_erl(&1.next), &1.name})
    end
  end

  test "the module never reads the clock" do
    source = File.read!("lib/server/home/bank/projection.ex")

    refute source =~
             ~r/utc_now|Date\.utc_today|System\.(os_time|system_time)|Clock\.|:calendar\.local_time|NaiveDateTime\.local/
  end
end
