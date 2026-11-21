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
      txn(~D[2026-09-26], 6_000, "Phone"),
      txn(~D[2026-10-27], 4_650, "Phone")
    ]

    assert [%{amount: 4_650, count: 3}] = Recurring.series(near, :out)
    assert Recurring.series(far, :out) == []
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
