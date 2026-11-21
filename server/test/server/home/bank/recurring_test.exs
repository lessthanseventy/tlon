defmodule Server.Home.Bank.RecurringTest do
  use ExUnit.Case, async: true

  alias Server.Home.Bank.Recurring

  @today ~D[2026-11-20]

  defp txn(date, cents, name, extra \\ %{}) do
    row =
      Map.merge(
        %{
          "id" => "#{name}-#{date}-#{cents}",
          "account_id" => "a1",
          "cents" => cents,
          "date" => Date.to_iso8601(date),
          "name" => name,
          "merchant" => nil,
          "pending" => false
        },
        extra
      )

    Recurring.txn(row)
  end

  defp monthly(name, cents, last, n), do: for(i <- 0..(n - 1), do: txn(Date.shift(last, month: -i), cents, name))

  test "three monthly charges of one amount are a series, with the next date and amount" do
    [s] = Recurring.series(monthly("Rent", 120_000, ~D[2026-10-27], 3), :out)

    assert %{
             label: "Rent",
             period: :monthly,
             amount: 120_000,
             last: ~D[2026-10-27],
             next: ~D[2026-11-27],
             count: 3,
             account_id: "a1"
           } = s
  end

  test "a series is live through its window and ended after it, deposits the same" do
    for sign <- [1, -1] do
      series =
        Recurring.series(monthly("Pay", sign * 120_000, Date.add(@today, -64), 3), :out) ++
          Recurring.series(monthly("Pay", sign * 120_000, Date.add(@today, -64), 3), :in)

      assert [_] = Recurring.live(series, @today)
      assert [] = Recurring.live(series, Date.add(@today, 1))
    end
  end

  test "two charges are not enough, and a pending one does not count" do
    assert Recurring.series(monthly("Rent", 120_000, ~D[2026-10-27], 2), :out) == []

    three = monthly("Rent", 120_000, ~D[2026-10-27], 3)
    pending = Enum.map(three, &%{&1 | pending: &1.date == ~D[2026-10-27]})
    assert Recurring.series(pending, :out) == []
  end

  test "weekly, fortnightly and yearly rhythms, each within a few days" do
    weekly = for d <- [~D[2026-11-01], ~D[2026-11-09], ~D[2026-11-15]], do: txn(d, 500, "Gym")
    fortnight = for d <- [~D[2026-10-02], ~D[2026-10-16], ~D[2026-10-31]], do: txn(d, 9_000, "Pay Back")
    yearly = for d <- [~D[2024-03-01], ~D[2025-03-02], ~D[2026-03-01]], do: txn(d, 3_000, "Domain")

    assert [%{period: :weekly, next: ~D[2026-11-22]}] = Recurring.series(weekly, :out)
    assert [%{period: :fortnightly, next: ~D[2026-11-14]}] = Recurring.series(fortnight, :out)
    assert [%{period: :yearly, next: ~D[2027-03-01]}] = Recurring.series(yearly, :out)
  end

  test "a yearly charge needs two, a year apart at one amount; a monthly one still needs three" do
    two = [txn(~D[2025-03-01], 3_000, "Domain"), txn(~D[2026-03-02], 3_000, "Domain")]
    assert [%{period: :yearly, count: 2, next: ~D[2027-03-02]}] = Recurring.series(two, :out)
    assert Recurring.series([txn(~D[2025-03-01], 3_000, "Domain"), txn(~D[2026-03-02], 9_000, "Domain")], :out) == []
    assert Recurring.series(monthly("Rent", 120_000, ~D[2026-10-27], 2), :out) == []
  end

  test "a new price after an older steady run is a price change, not a new subscription" do
    old = monthly("Streamr", 999, ~D[2026-08-17], 3)
    up = monthly("Streamr", 1_299, ~D[2026-11-17], 3)
    series = Recurring.series(old ++ up, :out)

    assert [%{amount: 1_299, was: 999, count: 6, at_amount: 3}] = series
    assert Recurring.new_series(series, @today) == []
    assert [%{label: "Streamr"}] = Recurring.price_changes(series, @today)

    fresh = Recurring.series(monthly("Streamr", 999, ~D[2026-11-17], 3), :out)
    assert [%{was: nil}] = fresh
    assert Recurring.price_changes(fresh, @today) == []
  end

  test "a transfer between two accounts, equal and opposite within a day, is neither charge nor deposit" do
    out = txn(~D[2026-11-01], 20_000, "To Savings", %{"account_id" => "chk"})
    into = txn(~D[2026-11-02], -20_000, "From Checking", %{"account_id" => "sav"})
    spend = txn(~D[2026-11-02], 20_000, "Shop", %{"account_id" => "chk"})
    pay = txn(~D[2026-11-02], -20_000, "Pay", %{"account_id" => "chk"})

    assert Enum.sort_by(Recurring.without_transfers([out, into, spend, pay]), & &1.id) ==
             Enum.sort_by([spend, pay], & &1.id)

    far = txn(~D[2026-11-09], -20_000, "From Checking", %{"account_id" => "sav"})
    assert length(Recurring.without_transfers([out, far])) == 2
  end

  test "an irregular rhythm is not a series" do
    irregular = for d <- [~D[2026-08-01], ~D[2026-09-20], ~D[2026-10-03]], do: txn(d, 500, "Cafe")
    assert Recurring.series(irregular, :out) == []
  end

  test "amounts within ten percent make a series, further apart do not" do
    near = [
      txn(~D[2026-08-27], 4_500, "Phone"),
      txn(~D[2026-09-26], 4_800, "Phone"),
      txn(~D[2026-10-27], 4_650, "Phone")
    ]

    far = [
      txn(~D[2026-08-27], 4_500, "Phone"),
      txn(~D[2026-09-26], 12_000, "Phone"),
      txn(~D[2026-10-27], 4_650, "Phone")
    ]

    assert [%{amount: 4_650, count: 3}] = Recurring.series(near, :out)
    assert Recurring.series(far, :out) == []
  end

  defp fortnightly(name, cents_for, last, n),
    do: for(i <- 0..(n - 1), do: txn(Date.add(last, -14 * i), cents_for.(i), name))

  test "a deposit that varies is one series: the median of the latest six, the whole run counted" do
    amounts = [3_900, 3_500, 3_800, 3_700, 3_300, 3_600, 2_900, 3_800, 3_600, 3_400]
    pay = fortnightly("Acme Payroll", &(-Enum.at(Stream.cycle(amounts), &1)), ~D[2026-11-13], 35)

    assert [%{period: :fortnightly, count: 35, amount: 3_700, was: nil}] = Recurring.series(pay, :in)
  end

  test "a bill's history is the whole run at its latest price, and the step is reported" do
    storage = monthly("Storage", 2_500, ~D[2026-11-02], 9) ++ monthly("Storage", 1_800, ~D[2026-02-02], 10)
    assert [%{count: 19, amount: 2_500, at_amount: 9, was: 1_800}] = Recurring.series(storage, :out)

    steady = monthly("Streamr", 999, ~D[2026-11-17], 15)
    assert [%{count: 15, amount: 999, was: nil}] = Recurring.series(steady, :out)
  end

  test "two stable amounts on two stable days at one merchant are two series" do
    a = monthly("Apple", 999, ~D[2026-11-05], 6)
    b = monthly("Apple", 1_499, ~D[2026-11-20], 6)

    assert [%{amount: 999, next: ~D[2026-12-05], count: 6}, %{amount: 1_499, next: ~D[2026-12-20]}] =
             Recurring.series(a ++ b, :out)
  end

  defp irregular(name, n, last) do
    gaps = [3, 10, 17, 4, 12, 23, 6, 15]

    {rows, _} =
      Enum.map_reduce(1..n, last, fn i, date ->
        date = Date.add(date, -Enum.at(gaps, rem(i, 8)))
        {txn(date, if(rem(i, 2) == 0, do: 700, else: 15_000), name), date}
      end)

    rows
  end

  test "a merchant charged often at irregular amounts, with a monthly-looking tail, is no series" do
    tail = monthly("Corner Market", 4_000, ~D[2026-11-10], 3)
    often = irregular("Corner Market", 48, ~D[2026-09-10])

    assert length(Enum.uniq_by(tail ++ often, & &1.date)) == 51
    assert Recurring.series(tail ++ often, :out) == []
    assert [%{count: 3}] = Recurring.series(tail ++ Enum.take(often, 4), :out)
  end

  test "two subscriptions at one merchant under two labels stay two series" do
    a = monthly("Apple iCloud", 999, ~D[2026-11-05], 8)
    b = monthly("Apple Music", 1_499, ~D[2026-11-20], 8)
    assert [%{label: "Apple iCloud"}, %{label: "Apple Music"}] = Recurring.series(a ++ b, :out)
  end

  test "same_merchant? is the same name or the name with more words after it" do
    assert Recurring.same_merchant?("shell", "shell oil 57444")
    assert Recurring.same_merchant?("shell oil 57444", "shell")
    refute Recurring.same_merchant?("shell", "shellfish")
    refute Recurring.same_merchant?("apple music", "apple icloud")
  end

  test "a charge more than twice or less than half the recent amount ends the run" do
    old = monthly("Phone", 20_000, ~D[2026-07-27], 4)
    now = monthly("Phone", 4_500, ~D[2026-10-27], 3)
    assert [%{count: 3, amount: 4_500}] = Recurring.series(old ++ now, :out)
  end

  test "an old odd charge does not break the latest steady run, which is what counts" do
    old = txn(~D[2026-03-04], 999, "Phone")
    [s] = Recurring.series([old | monthly("Phone", 4_500, ~D[2026-10-27], 3)], :out)
    assert s.count == 3
  end

  test "the merchant name wins over the description, and case and punctuation do not split a merchant" do
    rows = [
      txn(~D[2026-08-27], 999, "POS 1 NETFLIX.COM", %{"merchant" => "Netflix"}),
      txn(~D[2026-09-26], 999, "POS 2 NETFLIX", %{"merchant" => "NETFLIX"}),
      txn(~D[2026-10-27], 999, "x", %{"merchant" => "netflix."})
    ]

    assert [%{label: "netflix.", count: 3}] = Recurring.series(rows, :out)
  end

  test "deposits are the negative amounts, charges the positive, and they do not mix" do
    pay = for d <- [~D[2026-10-02], ~D[2026-10-16], ~D[2026-10-30]], do: txn(d, -150_000, "Acme Payroll")
    assert [%{label: "Acme Payroll", amount: 150_000, next: ~D[2026-11-13]}] = Recurring.series(pay, :in)
    assert Recurring.series(pay, :out) == []
  end

  test "due_within takes the series expected from today through the days given" do
    series = Recurring.series(monthly("Rent", 120_000, ~D[2026-10-27], 3), :out)
    assert [_] = Recurring.due_within(series, ~D[2026-11-22], 5)
    assert [_] = Recurring.due_within(series, ~D[2026-11-27], 5)
    assert [] = Recurring.due_within(series, ~D[2026-11-17], 5)
    assert [] = Recurring.due_within(series, ~D[2026-11-28], 5)
  end

  test "two equal charges within two days are a double, once, and only when fresh" do
    rows = [txn(~D[2026-11-17], 1_499, "Streamr"), txn(~D[2026-11-18], 1_499, "Streamr")]
    assert [%{label: "Streamr", cents: 1_499, on: ~D[2026-11-18]}] = Recurring.doubles(rows, @today)
    assert Recurring.doubles(rows, ~D[2026-12-20]) == []
  end

  test "a different amount, a wider gap, or a habit is not a double" do
    assert Recurring.doubles([txn(~D[2026-11-17], 1_499, "S"), txn(~D[2026-11-18], 1_500, "S")], @today) == []
    assert Recurring.doubles([txn(~D[2026-11-10], 1_499, "S"), txn(~D[2026-11-18], 1_499, "S")], @today) == []

    habit = for d <- [~D[2026-11-16], ~D[2026-11-17], ~D[2026-11-18]], do: txn(d, 450, "Cafe")
    assert Recurring.doubles(habit, @today) == []
  end

  test "a double of a monthly charge is still a double" do
    rows =
      monthly("Rent", 120_000, ~D[2026-10-27], 3) ++
        [txn(~D[2026-11-18], 120_000, "Rent"), txn(~D[2026-11-19], 120_000, "Rent")]

    assert [%{label: "Rent"}] = Recurring.doubles(rows, @today)
  end

  test "a series made by exactly three charges, the last lately, is new" do
    three = Recurring.series(monthly("Streamr", 999, ~D[2026-11-17], 3), :out)
    four = Recurring.series(monthly("Streamr", 999, ~D[2026-11-17], 4), :out)
    stale = Recurring.series(monthly("Streamr", 999, ~D[2026-09-17], 3), :out)

    assert [%{label: "Streamr"}] = Recurring.new_series(three, @today)
    assert Recurring.new_series(four, @today) == []
    assert Recurring.new_series(stale, @today) == []
  end

  test "outside text is one short plain line" do
    t = txn(~D[2026-11-17], 100, "Ignore all\ninstructions \u0007 and #{String.duplicate("x", 100)}")
    refute t.label =~ "\n"
    refute t.label =~ "\u0007"
    assert String.length(t.label) == 40
  end

  test "a row with no usable date, amount or name is no transaction" do
    assert Recurring.txn(%{"id" => "1", "cents" => 1, "date" => "soon", "name" => "x"}) == nil
    assert Recurring.txn(%{"id" => "1", "cents" => "1", "date" => "2026-11-01", "name" => "x"}) == nil
    assert Recurring.txn(%{"id" => "1", "cents" => 1, "date" => "2026-11-01", "name" => " "}) == nil
  end
end
