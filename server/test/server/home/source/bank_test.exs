defmodule Server.Home.Source.BankTest do
  use ExUnit.Case, async: false

  alias Server.Home.Bank
  alias Server.Home.Keep
  alias Server.Home.Source.Bank, as: Source
  alias Server.Proposal

  @now ~U[2026-11-20 12:00:00Z]
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

    {:ok, config: config}
  end

  # A scripted Plaid: `sync` replies are taken in order, `accounts` is one reply.
  defp plaid(syncs, accounts) do
    {:ok, agent} = Agent.start_link(fn -> %{syncs: syncs, calls: []} end)

    http = fn url, body ->
      path = URI.parse(url).path
      body = JSON.decode!(body)
      Agent.update(agent, &%{&1 | calls: &1.calls ++ [{path, body}]})

      case path do
        "/transactions/sync" -> Agent.get_and_update(agent, &next_sync/1)
        "/accounts/get" -> accounts
      end
    end

    {http, fn -> Agent.get(agent, & &1.calls) end}
  end

  defp next_sync(%{syncs: [next | rest]} = state), do: {next, %{state | syncs: rest}}

  defp ok(map), do: {:ok, 200, JSON.encode!(map)}
  defp err(code), do: {:ok, 400, JSON.encode!(%{"error_code" => code})}

  defp page(added, opts \\ []) do
    ok(%{
      "added" => added,
      "modified" => opts[:modified] || [],
      "removed" => opts[:removed] || [],
      "next_cursor" => opts[:cursor] || "c1",
      "has_more" => opts[:more] == true
    })
  end

  defp t(id, date, amount, name, extra \\ %{}) do
    Map.merge(
      %{
        "transaction_id" => id,
        "account_id" => "chk",
        "amount" => amount,
        "date" => date,
        "name" => name,
        "merchant_name" => nil,
        "pending" => false
      },
      extra
    )
  end

  defp rent,
    do: for({d, i} <- Enum.with_index(["2026-08-22", "2026-09-22", "2026-10-22"]), do: t("rent#{i}", d, 1200.0, "Rent"))

  defp accounts(available) do
    ok(%{
      "accounts" => [
        %{
          "account_id" => "chk",
          "name" => "Chime Checking",
          "type" => "depository",
          "subtype" => "checking",
          "balances" => %{"current" => available + 10, "available" => available}
        },
        %{
          "account_id" => "sav",
          "name" => "Savings",
          "type" => "depository",
          "subtype" => "savings",
          "balances" => %{"current" => 500.0, "available" => 500.0}
        },
        %{
          "account_id" => "cc",
          "name" => "Credit Builder",
          "type" => "credit",
          "subtype" => "credit card",
          "balances" => %{"current" => 80.0, "available" => nil}
        }
      ]
    })
  end

  defp fetch(http), do: Source.fetch(http: http, now: @now)
  defp paths(calls), do: Enum.map(calls, &elem(&1, 0))
  defp kept, do: JSON.decode!(Keep.get("home_bank"))

  test "it is the bank source, filing nothing by itself" do
    assert Source.name() == "bank"
    assert Source.auto() == []
  end

  test "a first fetch syncs every page from no cursor, reads the accounts, and keeps the cursor with the data" do
    {http, calls} =
      plaid(
        [page(Enum.take(rent(), 2), cursor: "c1", more: true), page(Enum.drop(rent(), 2), cursor: "c2")],
        accounts(1160.0)
      )

    assert {:ok, _, []} = fetch(http)

    assert [{"/transactions/sync", first}, {"/transactions/sync", second}, {"/accounts/get", _}] = calls.()
    refute Map.has_key?(first, "cursor")
    assert second["cursor"] == "c1"
    assert %{"cursor" => "c2", "transactions" => rows, "as_of" => "2026-11-20T12:00:00Z"} = kept()
    assert length(rows) == 3
    assert Enum.all?(paths(calls.()), &(&1 in Server.Home.Bank.Plaid.paths()))
  end

  test "a charge due within five days is proposed with whether the balance covers it" do
    {http, _} = plaid([page(rent())], accounts(1160.0))

    assert {:ok, [proposal], []} = fetch(http)
    assert proposal.kind == "todo"
    assert proposal.text == "Rent $1,200 is due Sun 22 Nov; the balance is $40 short"
    assert proposal.key =~ ~r/^bank:due:[0-9a-f]{16}:2026-11-22$/

    {http, _} = plaid([page([], cursor: "c2")], accounts(1500.0))
    assert {:ok, [%{text: "Rent $1,200 is due Sun 22 Nov; the balance covers it", key: key}], []} = fetch(http)
    assert key == proposal.key
  end

  test "a charge far off, or one already paid, is not proposed" do
    {http, _} = plaid([page(rent() ++ [t("rent3", "2026-11-22", 1200.0, "Rent")])], accounts(1500.0))
    assert {:ok, [], []} = fetch(http)
  end

  test "a double charge and a new subscription are proposed" do
    streamr =
      for {d, i} <- Enum.with_index(["2026-09-17", "2026-10-17", "2026-11-17"]), do: t("s#{i}", d, 9.99, "Streamr")

    double = [t("d1", "2026-11-18", 14.99, "Cloudy"), t("d2", "2026-11-19", 14.99, "Cloudy")]
    {http, _} = plaid([page(streamr ++ double)], accounts(1500.0))

    assert {:ok, proposals, []} = fetch(http)
    texts = Enum.sort(Enum.map(proposals, & &1.text))

    assert texts == [
             "Streamr looks like a new subscription: $9.99 monthly",
             "Two charges of $14.99 from Cloudy on Thu: check for a double"
           ]

    assert Enum.all?(proposals, &(&1.kind == "todo" and String.starts_with?(&1.key, "bank:")))
  end

  test "the proposals are filed once, and a dismissed one does not come back" do
    {http, _} = plaid([page(rent()), page([], cursor: "c2")], accounts(1160.0))
    {:ok, proposals, []} = fetch(http)

    assert [] = Proposal.offer("telegram", "bank", proposals, @now, Source.auto())
    assert [%{id: id}] = Proposal.open()
    {:ok, proposals, []} = fetch(http)
    Proposal.offer("telegram", "bank", proposals, @now, [])
    assert [%{id: ^id}] = Proposal.open()

    {:ok, _} = Proposal.dismiss(id)

    {:ok, proposals, []} =
      fetch(fn url, body -> elem(plaid([page([], cursor: "c3")], accounts(1160.0)), 0).(url, body) end)

    Proposal.offer("telegram", "bank", proposals, @now, [])
    assert Proposal.open() == []
  end

  test "modified rows replace, removed rows go, and what is older than 400 days is dropped" do
    old = t("old", "2025-09-01", 5.0, "Ancient")
    {http, _} = plaid([page(rent() ++ [old], cursor: "c1")], accounts(1500.0))
    {:ok, _, []} = fetch(http)
    assert [%{"id" => "rent0"} | _] = kept()["transactions"]
    refute Enum.any?(kept()["transactions"], &(&1["id"] == "old"))

    changed = t("rent2", "2026-10-22", 1250.0, "Rent")

    {http, calls} =
      plaid([page([], modified: [changed], removed: [%{"transaction_id" => "rent0"}], cursor: "c2")], accounts(1500.0))

    {:ok, _, []} = fetch(http)

    assert [{"/transactions/sync", %{"cursor" => "c1"}}, _] = calls.()
    rows = kept()["transactions"]
    assert Enum.map(rows, & &1["id"]) == ["rent1", "rent2"]
    assert Enum.find(rows, &(&1["id"] == "rent2"))["cents"] == 125_000
  end

  test "a page that fails mid-pagination restarts from the cursor the update began with, and keeps nothing until it ends" do
    {:ok, _, []} = fetch(elem(plaid([page(rent(), cursor: "c1")], accounts(1500.0)), 0))

    mutation = err("TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION")
    {http, calls} = plaid([page([], cursor: "x1", more: true), mutation, page([], cursor: "c2")], accounts(1500.0))
    assert {:ok, _, []} = fetch(http)

    cursors = for {"/transactions/sync", body} <- calls.(), do: body["cursor"]
    assert cursors == ["c1", "x1", "c1"]
    assert kept()["cursor"] == "c2"
  end

  test "an error keeps nothing, moves no cursor, and is returned for the poller to log" do
    {:ok, _, []} = fetch(elem(plaid([page(rent(), cursor: "c1")], accounts(1500.0)), 0))
    before = Keep.get("home_bank")

    {http, _} = plaid([page([], cursor: "c2", more: true), err("INTERNAL_SERVER_ERROR")], accounts(1500.0))
    assert {:error, {:plaid, "INTERNAL_SERVER_ERROR"}} = fetch(http)

    {http, _} = plaid([page([], cursor: "c2")], err("RATE_LIMIT_EXCEEDED"))
    assert {:error, {:plaid, "RATE_LIMIT_EXCEEDED"}} = fetch(http)
    assert Keep.get("home_bank") == before
  end

  test "a login that needs doing again is one proposal for the month, and the data is left alone" do
    {:ok, _, []} = fetch(elem(plaid([page(rent(), cursor: "c1")], accounts(1500.0)), 0))
    before = Keep.get("home_bank")

    {http, _} = plaid([err("ITEM_LOGIN_REQUIRED")], accounts(1500.0))
    assert {:ok, [%{key: "bank:relink:2026-11", text: "The bank needs linking again", kind: "todo"}], []} = fetch(http)
    assert Keep.get("home_bank") == before
  end

  test "with no access token the fetch says so and calls nothing" do
    System.delete_env("PLAID_ACCESS_TOKEN")
    {http, calls} = plaid([], accounts(0.0))
    assert {:error, "no Plaid access token"} = fetch(http)
    assert calls.() == []
    refute Bank.enabled?()
    assert Bank.summary(now: @now) == nil
  end

  describe "summary" do
    setup do
      pay =
        for {d, i} <- Enum.with_index(["2026-10-16", "2026-10-30", "2026-11-13"]),
            do: t("pay#{i}", d, -1500.0, "Acme Payroll")

      phone =
        for {d, i} <- Enum.with_index(["2026-08-24", "2026-09-24", "2026-10-24"]), do: t("ph#{i}", d, 45.0, "Phone Co")

      {http, _} = plaid([page(rent() ++ phone ++ pay)], accounts(1240.0))
      {:ok, _, []} = fetch(http)
      :ok
    end

    test "the spendable money is the checking accounts alone; savings and credit are listed, not counted" do
      assert %{balance: 125_000, available: 124_000, as_of: "2026-11-20T12:00:00Z", accounts: accounts} =
               Bank.summary(now: @now)

      assert Enum.map(accounts, &{&1.id, &1.spendable}) == [{"chk", true}, {"sav", false}, {"cc", false}]
      assert %{balance: 50_000} = Enum.find(accounts, &(&1.id == "sav"))
    end

    test "what is due this week and the next deposit" do
      summary = Bank.summary(now: @now)

      assert summary.due_this_week == [
               %{name: "Rent", amount: 120_000, on: ~D[2026-11-22]},
               %{name: "Phone Co", amount: 4_500, on: ~D[2026-11-24]}
             ]

      assert summary.next_deposit == %{name: "Acme Payroll", amount: 150_000, on: ~D[2026-11-27]}
    end

    test "the morning line, calm, with what it has" do
      summary = %{Bank.summary(now: @now) | next_deposit: %{name: "Pay", amount: 1, on: ~D[2026-11-24]}}

      assert Bank.line(summary, @today) ==
               "Money: $1,240 available. Due this week: Rent $1,200 Sun, Phone Co $45 Tue. Next deposit about Tue."

      assert Bank.line(Bank.summary(now: @now), @today) =~ "Next deposit about Fri 27 Nov."

      assert Bank.line(%{summary | due_this_week: [], next_deposit: nil}, @today) == "Money: $1,240 available."
      assert Bank.line(%{summary | available: nil, due_this_week: [], next_deposit: nil}, @today) == nil
      assert Bank.line(nil, @today) == nil
    end

    test "it is nil when the source is off" do
      :ok = Server.OperatorConfig.put("home_sources", "mail")
      assert Bank.summary(now: @now) == nil
    end
  end

  test "money is said in dollars aloud" do
    assert Bank.money(120_000) == "$1,200"
    assert Bank.money(1_499) == "$14.99"
    assert Bank.money(5) == "$0.05"
    assert Bank.money(123_456_789) == "$1,234,567.89"
    assert Bank.money(-4_000) == "-$40"
  end
end
