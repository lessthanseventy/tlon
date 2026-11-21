defmodule Server.Home.BankTest do
  use ExUnit.Case, async: false

  alias Server.Home.Bank
  alias Server.Home.Keep
  alias Server.Repo

  @today ~D[2026-11-20]

  setup do
    Server.TestDB.clean!()
    config = Server.TestDB.continuation_gap_off!()
    :ok = Server.OperatorConfig.put("home_sources", "bank", config)

    previous =
      for name <- ~w(PLAID_CLIENT_ID PLAID_SECRET PLAID_ACCESS_TOKEN XDG_RUNTIME_DIR), do: {name, System.get_env(name)}

    for {name, _} <- previous, do: System.delete_env(name)
    System.put_env("PLAID_CLIENT_ID", "cid")
    System.put_env("PLAID_SECRET", "sec")
    System.put_env("PLAID_ACCESS_TOKEN", "tok")

    System.put_env(
      "XDG_RUNTIME_DIR",
      System.tmp_dir!() <> "/no-secrets-#{System.pid()}-#{System.unique_integer([:positive])}"
    )

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)
  end

  defp store do
    accounts = [
      %{
        "id" => "a1",
        "name" => "Current",
        "type" => "depository",
        "subtype" => "checking",
        "current" => 300_000,
        "available" => 290_000
      }
    ]

    Keep.put("home_bank", JSON.encode!(%{"accounts" => accounts, "as_of" => "2026-11-20T12:00:00Z"}))

    rows =
      for {name, cents, date} <- rent() ++ salary() ++ shops() do
        %{
          transaction_id: "#{name}-#{date}",
          account_id: "a1",
          amount_cents: cents,
          date: date,
          name: name,
          merchant_name: nil,
          pending: false
        }
      end

    Repo.insert_all(Server.Home.Bank.Transaction, rows)
  end

  defp rent, do: for(m <- 0..3, do: {"Rent", 120_000, Date.shift(~D[2026-10-27], month: -m)})
  defp salary, do: for(m <- 0..3, do: {"Salary", -300_000, Date.shift(~D[2026-11-13], month: -m)})
  defp shops, do: for(i <- 1..60, do: {"Shop #{i}", 2_000, Date.add(@today, -i)})

  test "every wrapper is no data when nothing is stored or the source is off" do
    assert {:error, :no_data} = Bank.forecast(~D[2026-12-20], @today)
    assert {:error, :no_data} = Bank.afford(1_000, nil, today: @today)
    assert {:error, :no_data} = Bank.what_if([], ~D[2026-12-20], @today)
    assert {:error, :no_data} = Bank.history(%{match: nil, from: ~D[2026-01-01], to: @today}, @today)
    assert {:error, :no_data} = Bank.subscriptions(@today)

    store()

    System.delete_env("PLAID_ACCESS_TOKEN")
    assert {:error, :no_data} = Bank.forecast(~D[2026-12-20], @today)
  end

  test "forecast reads the stored rows and the keep" do
    store()
    assert {:ok, f} = Bank.forecast(~D[2026-12-20], @today)

    assert f.start_cents == 290_000
    assert Enum.any?(f.events, &(&1.name == "Rent" and &1.date == ~D[2026-11-27]))
    assert f.basis.next_deposit == %{name: "Salary", date: ~D[2026-12-13], overdue: false}
  end

  test "afford, what_if, history and subscriptions use the same rows" do
    store()

    assert {:ok, %{verdict: :covers}} = Bank.afford(1_000, nil, today: @today)
    assert {:ok, %{verdict: :short}} = Bank.afford(5_000_000, ~D[2026-12-01], today: @today)

    assert {:ok, %{difference: %{end_cents: 120_000}}} = Bank.what_if([{:drop, "rent"}], ~D[2026-12-20], @today)
    assert {:error, {:no_series, "Rant", ["Rent" | _]}} = Bank.what_if([{:drop, "Rant"}], ~D[2026-12-20], @today)

    assert {:ok, %{months: [%{month: "2026-10", out_cents: -120_000}]}} =
             Bank.history(%{match: "RENT", from: ~D[2026-10-01], to: ~D[2026-10-31]}, @today)

    assert {:ok, [%{name: "Rent", amount_cents: -120_000, next: ~D[2026-11-27]}]} = Bank.subscriptions(@today)
  end
end
