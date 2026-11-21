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

    test "a series whose last charge is past its window has ended: no event, no skip, no series" do
      ended = [monthly("Old gym", 4_000, ~D[2026-03-10], 6), weekly("Old coffee", 900, ~D[2026-02-01], 5)]
      old_pay = monthly("Old employer", -300_000, ~D[2026-03-13], 5)
      f = forecast!(data([ended, old_pay, base().transactions]), ~D[2027-01-20])

      refute Enum.any?(f.events, &(&1.name in ["Old gym", "Old coffee", "Old employer"]))
      assert f.basis.skipped == []
      refute :skipped_charge in f.basis.caveats
      assert f.basis.series == forecast!(base()).basis.series
    end

    test "one payer under three labels over time: only the live label is a deposit" do
      fortnightly = fn name, last, n -> repeated(name, -300_000, last, n, &[day: -14 * &1]) end

      pay = [
        fortnightly.("Acme Payroll", Date.add(@today, -550), 11),
        fortnightly.("ACME PAYROLL INC", Date.add(@today, -480), 5),
        fortnightly.("Acme Co Salary", Date.add(@today, -7), 35)
      ]

      f = forecast!(data([pay, everyday(100)]), Date.add(@today, 28))
      deposits = Enum.filter(f.events, &(&1.kind == :deposit))

      assert Enum.map(deposits, & &1.name) == ["Acme Co Salary", "Acme Co Salary"]
      assert Enum.map(deposits, & &1.date) == [Date.add(@today, 7), Date.add(@today, 21)]
    end

    test "ended series leave afford, what_if and subscriptions too" do
      d = data([monthly("Old gym", 4_000, ~D[2026-03-10], 6), base().transactions])

      assert {:ok, afford} = Projection.afford(d, @today, 10_000, nil)
      refute Enum.any?(afford.without.events, &(&1.name == "Old gym"))

      assert {:error, {:no_series, "Old gym", _}} = Projection.what_if(d, @today, [{:drop, "Old gym"}], ~D[2026-12-31])

      assert {:error, {:no_series, "Old gym", _}} =
               Projection.what_if(d, @today, [{:change, "Old gym", 100}], ~D[2026-12-31])

      refute Enum.any?(Projection.subscriptions(d, @today), &(&1.name == "Old gym"))
    end

    test "the window edge: live on the last day of it, ended the day after, per rhythm" do
      for {txns, edge} <- [
            {&weekly("W", 500, &1, 4), 16},
            {&repeated("F", 500, &1, 4, fn i -> [day: -14 * i] end), 31},
            {&monthly("M", 500, &1, 4), 64},
            {&[txn(&1, 500, "Y"), txn(Date.shift(&1, year: -1), 500, "Y")], 395}
          ] do
        live = data([txns.(Date.add(@today, -edge)), everyday(100)])
        gone = data([txns.(Date.add(@today, -edge - 1)), everyday(100)])

        assert Projection.subscriptions(live, @today) != []
        assert Projection.subscriptions(gone, @today) == []
      end
    end

    test "one cycle late is still overdue, past the grace skipped, beyond the window ended" do
      overdue = forecast!(data([monthly("Rent", 120_000, ~D[2026-10-15], 4), everyday(100)]))
      assert [%{overdue: true}, %{overdue: false}] = overdue.events |> Enum.filter(&(&1.name == "Rent")) |> Enum.take(2)

      skipped = forecast!(data([monthly("Rent", 120_000, ~D[2026-09-25], 4), everyday(100)]))
      assert skipped.basis.skipped == ["Rent"]

      ended = forecast!(data([monthly("Rent", 120_000, ~D[2026-09-10], 4), everyday(100)]))
      assert ended.basis.skipped == []
      refute Enum.any?(ended.events, &(&1.name == "Rent"))
    end

    test "a charge under a longer label of the merchant, at any amount, means the series was not skipped" do
      rent = monthly("Corner Shop", 4_000, ~D[2026-10-01], 3)
      skipped = forecast!(data([rent, everyday(100)]), ~D[2026-12-31])
      assert skipped.basis.skipped == ["Corner Shop"]

      visit = txn(Date.add(@today, -7), 912, "Corner Shop 042")
      arrived = forecast!(data([rent, visit, everyday(100)]), ~D[2026-12-31])
      assert arrived.basis.skipped == []
    end

    test "series outflow and everyday outflow add up to all the non-transfer outflow over the window" do
      often = for i <- 1..30, do: txn(Date.add(@today, -3 * i - rem(i * i, 4)), 600 + 100 * rem(i, 3), "Corner Market")
      rent = monthly("Rent", 12_000, ~D[2026-10-27], 3)

      transfer = [
        txn(Date.add(@today, -5), 50_000, "To savings"),
        txn(Date.add(@today, -5), -50_000, "From checking", %{"account_id" => "s1"})
      ]

      d = data([often, rent, transfer])
      f = forecast!(d)

      window = Date.add(@today, 1 - f.everyday.history_days)

      outflow =
        for t <- d.transactions,
            t.cents > 0,
            t.account_id == "a1",
            Date.compare(t.date, window) != :lt,
            t.label != "To savings",
            do: t.cents

      series_out = for t <- rent, Date.compare(t.date, window) != :lt, do: t.cents

      assert Enum.sum(outflow) > 0

      rounding =
        abs(Enum.sum(outflow) - Enum.sum(series_out) - f.everyday.expected_daily_cents * f.everyday.history_days)

      assert rounding <= div(f.everyday.history_days, 2)
    end

    test "an overdue deposit is placed tomorrow and bounds before_next_deposit there" do
      f = forecast!(data([monthly("Salary", -300_000, ~D[2026-10-17], 4), everyday(100)]), ~D[2026-12-31])

      assert f.basis.next_deposit == %{name: "Salary", date: ~D[2026-11-21], overdue: true}
      assert f.before_next_deposit.date == @today
    end

    test "a checking account with no transactions of its own forecasts with zero everyday spending" do
      other = txn(Date.add(@today, -3), 900, "Elsewhere", %{"account_id" => "s1"})
      f = forecast!(data([other]))

      assert f.everyday == %{expected_daily_cents: 0, low_daily_cents: 0, high_daily_cents: 0, history_days: 0}
      assert List.last(f.days).expected_cents == 480_000
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

    test "moves between checking and savings, either way and a day apart, never reach everyday spending or the series" do
      labels = ["Transfer to Acme Savings Account", "Moved to Acme Savings account", "Acme transfer"]

      moves =
        for i <- 1..60, {cents, from, to} <- [{20_000 + 100 * i, "a1", "s1"}, {7_000 + 100 * i, "s1", "a1"}] do
          day = Date.add(@today, -rem(i * 7, 85) - 2)
          label = Enum.at(labels, rem(i, 3))
          lag = if rem(i, 2) == 0, do: 1, else: 0

          [
            txn(day, cents, label, %{"account_id" => from}),
            txn(Date.add(day, lag), -cents, "Acme transfer", %{"account_id" => to})
          ]
        end

      only_shops = forecast!(data([everyday(100)]))
      with_moves = forecast!(data([everyday(100), moves]))

      assert with_moves.everyday == only_shops.everyday
      assert with_moves.basis.series == only_shops.basis.series
      assert with_moves.events == only_shops.events
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

    test "savings is named beside the forecast and says whether it covers a shortfall or a tight low" do
      checking = %{
        "id" => "a1",
        "type" => "depository",
        "subtype" => "checking",
        "current" => 50_000,
        "available" => 50_000
      }

      saving = fn available ->
        %{
          "id" => "s1",
          "name" => "Acme Savings",
          "type" => "depository",
          "subtype" => "savings",
          "current" => available,
          "available" => available
        }
      end

      rent = monthly("Rent", 120_000, ~D[2026-10-27], 4)

      big = afford!(data([rent, everyday(100)], [checking, saving.(9_000_000)]), 5_000)

      assert %{
               verdict: :short,
               other_available_cents: 9_000_000,
               other_accounts: ["Acme Savings"],
               covered_by_other: true
             } = big

      assert big.with.other_available_cents == 9_000_000
      assert big.with.start_cents == 50_000

      small = afford!(data([rent, everyday(100)], [checking, saving.(1_000)]), 5_000)
      assert %{verdict: :short, covered_by_other: false} = small

      assert %{verdict: :covers, covered_by_other: nil} = afford!(base(), 1_000)

      assert %{other_available_cents: 9_000_000, other_accounts: []} =
               base() |> afford!(1_000) |> Map.take([:other_available_cents, :other_accounts])
    end

    test "a baseline that is already short says so, with the shortfall and what the purchase adds" do
      low = [
        %{"id" => "a1", "type" => "depository", "subtype" => "checking", "current" => 50_000, "available" => 50_000}
      ]

      a = afford!(data([monthly("Rent", 120_000, ~D[2026-10-27], 4), everyday(100)], low), 5_000)

      assert %{verdict: :short, short_without: true, baseline_short_on: on, baseline_shortfall_cents: base} = a
      assert on == ~D[2026-11-27]
      assert base == -a.without.lowest.balance_cents
      assert a.adds_cents == 5_000
      assert a.shortfall_cents == base + 5_000

      covered = afford!(base(), 1_000)
      assert %{short_without: false, baseline_shortfall_cents: nil, baseline_short_on: nil, adds_cents: nil} = covered
    end

    test "an amount that is not a positive integer is a bad amount" do
      for bad <- [0, -500, 10.5, "20"],
          do: assert({:error, :bad_amount} = Projection.afford(base(), @today, bad))
    end

    test "a purchase past the 180-day cap is refused, on the cap it is counted" do
      assert {:error, :beyond_horizon} = Projection.afford(base(), @today, 1_000, Date.add(@today, 181))

      a = afford!(base(), 1_000, Date.add(@today, 180))
      assert a.without.until == Date.add(@today, 180)
      assert List.last(a.without.days).expected_cents - List.last(a.with.days).expected_cents == 1_000
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

    test "a cost the change cannot take is a bad amount; a negative one-off is money in" do
      for change <- [
            {:one_off, 0, ~D[2026-12-02], "X"},
            {:one_off, 1.5, ~D[2026-12-02], "X"},
            {:recurring, 0, :weekly, ~D[2026-12-02], "X"},
            {:recurring, -5, :weekly, ~D[2026-12-02], "X"},
            {:change, "salary", 0},
            {:change, "salary", -1},
            {:change, "salary", "9"}
          ],
          do: assert({:error, :bad_amount} = Projection.what_if(base(), @today, [change], ~D[2026-12-31]))

      assert {:ok, r} = Projection.what_if(base(), @today, [{:one_off, -7_000, ~D[2026-12-02], "Gift"}], ~D[2026-12-31])
      assert r.difference.end_cents == 7_000
    end

    test "a one-off past the horizon is refused, a recurring past until but within the cap is not" do
      assert {:error, :beyond_horizon} =
               Projection.what_if(base(), @today, [{:one_off, 100, ~D[2026-12-02], "X"}], ~D[2026-12-01])

      assert {:error, :beyond_horizon} =
               Projection.what_if(base(), @today, [{:one_off, 100, Date.add(@today, 181), "X"}], ~D[2030-01-01])

      assert {:error, :beyond_horizon} =
               Projection.what_if(
                 base(),
                 @today,
                 [{:recurring, 100, :weekly, Date.add(@today, 181), "X"}],
                 ~D[2030-01-01]
               )

      assert {:ok, r} =
               Projection.what_if(base(), @today, [{:recurring, 100, :weekly, ~D[2026-12-10], "X"}], ~D[2026-12-01])

      assert r.changed == r.baseline
    end

    test "the result says when the horizon was clamped" do
      assert what_if!([], ~D[2030-01-01]).clamped
      refute what_if!([]).clamped
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
               Projection.history(data([everyday(5), special()]), %{match: match, from: from, to: to})

      result
    end

    defp special do
      [
        txn(~D[2026-09-30], 1_000, "Corner Cafe"),
        txn(~D[2026-10-01], 2_000, "CORNER CAFE #2"),
        txn(~D[2026-10-31], 3_000, "corner cafe"),
        txn(~D[2026-11-02], -500, "Corner Cafe refund"),
        txn(~D[2026-11-03], 700, "Other", %{"pending" => true}),
        txn(~D[2026-11-04], 99_900, "Move out"),
        txn(~D[2026-11-04], -99_900, "Move in", %{"account_id" => "a2"})
      ]
    end

    test "a list of matches is any-of, and the merchants counted are named with their totals" do
      h = history!(["cafe refund", "move out", "no such store"], ~D[2026-09-01], ~D[2026-11-30])
      assert h.count == 1
      assert h.merchants == [%{name: "Corner Cafe refund", out_cents: 0, in_cents: 500, count: 1}]

      both = history!(["corner cafe", "shop 1"], ~D[2026-09-01], ~D[2026-11-30])
      assert both.count == history!("corner cafe", ~D[2026-09-01], ~D[2026-11-30]).count + 1
      assert [%{out_cents: -4_000, count: 2} = top | _] = both.merchants
      assert String.downcase(top.name) == "corner cafe"
      assert history!(nil, ~D[2026-09-01], ~D[2026-11-30]).merchants == []
      assert history!([], ~D[2026-09-01], ~D[2026-11-30]).count == 0
    end

    test "merchants lists labels of the last 90 days by frequency, capped, transfers and old rows out" do
      shops =
        for i <- 1..70, do: txn(Date.add(@today, -1 - rem(i, 80)), 500, "Store #{String.pad_leading("#{i}", 2, "0")}")

      often = for d <- 1..5, do: txn(Date.add(@today, -d), 300, "Daily Bread")
      old = txn(Date.add(@today, -91), 500, "Long Ago")
      pending = txn(@today, 500, "Pending Place", %{"pending" => true})
      long = txn(@today, 500, String.duplicate("x", 60))

      move = [
        txn(@today, 90_000, "Move out"),
        txn(@today, -90_000, "Move in", %{"account_id" => "a2"})
      ]

      labels = Projection.merchants(data([shops, often, old, pending, long, move]), @today)

      assert hd(labels) == "Daily Bread"
      assert length(labels) == 60
      refute Enum.any?(labels, &(&1 in ["Long Ago", "Pending Place", "Move out", "Move in"]))
      assert Enum.all?(labels, &(String.length(&1) <= 40))
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
      refute Enum.any?(h.largest, &(&1.name in ["Other", "Move out", "Move in"]))
      assert Enum.sum(Enum.map(h.months, & &1.out_cents)) == -15_000
      assert Enum.sum(Enum.map(h.months, & &1.in_cents)) == 500
    end

    test "from after to is a bad range, never a crash" do
      assert {:error, :bad_range} =
               Projection.history(data([everyday(5)]), %{match: nil, from: ~D[2026-11-02], to: ~D[2026-11-01]})
    end

    test "a range inside one empty month gives zeros" do
      assert {:ok, %{months: [%{month: "2025-03", out_cents: 0, in_cents: 0, count: 0}], count: 0, largest: []} = h} =
               Projection.history(data([everyday(5)]), %{match: nil, from: ~D[2025-03-05], to: ~D[2025-03-05]})

      assert h.average_out_cents == 0 and h.average_in_cents == 0
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
