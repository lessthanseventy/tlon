defmodule Server.Home.Source.BankTest do
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Server.Home.Bank
  alias Server.Home.Bank.Transaction
  alias Server.Home.Keep
  alias Server.Home.Source.Bank, as: Source
  alias Server.Proposal
  alias Server.Repo

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
  defp rows, do: Repo.all(from(t in Transaction, order_by: [t.date, t.transaction_id]))

  defp xmins,
    do: Map.new(Repo.query!("select transaction_id, xmin::text from home_bank_transactions").rows, &List.to_tuple/1)

  test "5,000 transactions are rows, not a body, and a later sync touches only what changed" do
    many =
      for i <- 1..5000,
          do: t("t#{i}", String.replace("2026-11-#{rem(i, 20) + 1}", ~r/-(\d)$/, "-0\\1"), 1.0 + i, "Shop #{i}")

    {http, _} = plaid([page(many, cursor: "c1")], accounts(1500.0))
    {:ok, _, []} = fetch(http)

    assert length(rows()) == 5000
    assert byte_size(Keep.get("home_bank")) < 2_000
    before = xmins()

    added = for i <- 5001..5003, do: t("t#{i}", "2026-11-19", 2.0, "New #{i}")

    {http, _} =
      plaid(
        [
          page(added,
            modified: [t("t7", "2026-11-19", 99.0, "Shop 7")],
            removed: [%{"transaction_id" => "t9"}],
            cursor: "c2"
          )
        ],
        accounts(1500.0)
      )

    {:ok, _, []} = fetch(http)
    after_sync = xmins()

    assert map_size(after_sync) == 5002
    changed = for {id, xmin} <- after_sync, before[id] != xmin, do: id
    assert Enum.sort(changed) == ["t5001", "t5002", "t5003", "t7"]
    assert Enum.find(rows(), &(&1.transaction_id == "t7")).amount_cents == 9900
  end

  describe "a keep in the earlier shape" do
    defp old_row(id, date, cents, name),
      do: %{
        "id" => id,
        "account_id" => "chk",
        "cents" => cents,
        "date" => date,
        "name" => name,
        "merchant" => nil,
        "pending" => false
      }

    defp old_keep(transactions) do
      Keep.put(
        "home_bank",
        JSON.encode!(%{
          "cursor" => "c1",
          "transactions" => transactions,
          "accounts" => [
            %{
              "id" => "chk",
              "name" => "Chk",
              "type" => "depository",
              "subtype" => "checking",
              "current" => 125_000,
              "available" => 124_000
            }
          ],
          "as_of" => "2026-11-19T12:00:00Z"
        })
      )
    end

    defp old_rent,
      do:
        for(
          {d, i} <- Enum.with_index(["2026-08-22", "2026-09-22", "2026-10-22"]),
          do: old_row("rent#{i}", d, 120_000, "Rent")
        )

    test "the first refresh moves its rows into the table and the keep loses the list, cursor kept" do
      old_keep(old_rent())
      {http, calls} = plaid([page([], cursor: "c2")], accounts(1500.0))
      assert {:ok, _, []} = fetch(http)

      assert [{"/transactions/sync", %{"cursor" => "c1"}}, _] = calls.()
      assert Enum.map(rows(), & &1.transaction_id) == ["rent0", "rent1", "rent2"]
      assert %{"cursor" => "c2"} = kept = kept()
      refute Map.has_key?(kept, "transactions")
    end

    test "a summary read before any refresh moves them too, and is idempotent" do
      old_keep(old_rent())
      assert %{due_this_week: [%{name: "Rent"}]} = Bank.summary(now: @now)
      assert Bank.summary(now: @now).due_this_week == Bank.summary(now: @now).due_this_week
      assert length(rows()) == 3
      refute Map.has_key?(kept(), "transactions")
    end

    test "an empty or absent list is fine" do
      old_keep([])
      {http, _} = plaid([page([], cursor: "c2")], accounts(1500.0))
      assert {:ok, _, []} = fetch(http)
      assert rows() == []
      refute Map.has_key?(kept(), "transactions")
    end

    test "rows that do not parse are skipped and the cursor is dropped, with a log line" do
      old_keep([old_row("bad", "not-a-date", 1, "X") | old_rent()])
      {http, calls} = plaid([page([], cursor: "c2")], accounts(1500.0))

      log = ExUnit.CaptureLog.capture_log(fn -> assert {:ok, _, []} = fetch(http) end)
      assert log =~ "1 kept transactions did not parse"
      assert [{"/transactions/sync", body}, _] = calls.()
      refute Map.has_key?(body, "cursor")
      assert length(rows()) == 3
    end
  end

  test "a stored summary is used the day it was made and worked out again on another day" do
    {http, _} = plaid([page(rent())], accounts(1500.0))
    {:ok, _, []} = fetch(http)
    assert %{"for" => "2026-11-20", "due_this_week" => [%{"name" => "Rent"}]} = kept()["summary"]

    Repo.delete_all(Transaction)
    assert [%{name: "Rent"}] = Bank.summary(now: @now).due_this_week

    assert [] = Bank.summary(now: ~U[2026-11-24 12:00:00Z]).due_this_week
  end

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
    assert %{"cursor" => "c2", "as_of" => "2026-11-20T12:00:00Z"} = kept = kept()
    refute Map.has_key?(kept, "transactions")
    assert length(rows()) == 3
    assert Enum.all?(paths(calls.()), &(&1 in Server.Home.Bank.Plaid.paths()))
  end

  test "a charge due within five days is proposed as money to move when the balance is short" do
    {http, _} = plaid([page(rent())], accounts(1160.0))

    assert {:ok, [proposal], []} = fetch(http)
    assert proposal.kind == "todo"
    assert proposal.text == "Move money: the balance is $40 short for Rent $1,200, due Sun 22 Nov"
    assert proposal.key =~ ~r/^bank:due:[0-9a-f]{16}:2026-11-22$/
  end

  test "a charge the balance covers is no proposal, and its open row is withdrawn" do
    {http, _} = plaid([page(rent())], accounts(1160.0))
    {:ok, [proposal], []} = fetch(http)
    [] = Proposal.offer("telegram", "bank", [proposal], @now, [])
    assert [%{key: key}] = Proposal.open()

    {http, _} = plaid([page([], cursor: "c2")], accounts(1500.0))
    assert {:ok, [], [^key]} = fetch(http)
  end

  test "a charge whose account has no known balance is not proposed" do
    unknown = ok(%{"accounts" => [%{"account_id" => "other", "name" => "X", "balances" => %{}}]})
    {http, _} = plaid([page(rent())], unknown)
    assert {:ok, [], []} = fetch(http)
  end

  test "a charge far off, or one already paid, is not proposed" do
    {http, _} = plaid([page(rent() ++ [t("rent3", "2026-11-22", 1200.0, "Rent")])], accounts(1500.0))
    assert {:ok, [], []} = fetch(http)
  end

  test "a double charge is proposed as a check, a new subscription is only a notice" do
    streamr =
      for {d, i} <- Enum.with_index(["2026-09-17", "2026-10-17", "2026-11-17"]), do: t("s#{i}", d, 9.99, "Streamr")

    double = [t("d1", "2026-11-18", 14.99, "Cloudy"), t("d2", "2026-11-19", 14.99, "Cloudy")]
    {http, _} = plaid([page(streamr ++ double)], accounts(1500.0))

    assert {:ok, [proposal], []} = fetch(http)
    assert proposal.text == "Check for a double charge from Cloudy: two of $14.99 on Thu"
    assert proposal.kind == "todo"
    assert proposal.key =~ ~r/^bank:double:/

    assert [%{kind: "new", text: "Streamr looks like a new subscription: $9.99 monthly"}] = Source.notices(@today)
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

  test "modified rows replace, removed rows go, and what is older than 800 days is dropped" do
    old = t("old", "2024-09-01", 5.0, "Ancient")
    {http, _} = plaid([page(rent() ++ [old], cursor: "c1")], accounts(1500.0))
    {:ok, _, []} = fetch(http)
    assert [%{transaction_id: "rent0"} | _] = rows()
    refute Enum.any?(rows(), &(&1.transaction_id == "old"))

    changed = t("rent2", "2026-10-22", 1250.0, "Rent")

    {http, calls} =
      plaid([page([], modified: [changed], removed: [%{"transaction_id" => "rent0"}], cursor: "c2")], accounts(1500.0))

    {:ok, _, []} = fetch(http)

    assert [{"/transactions/sync", %{"cursor" => "c1"}}, _] = calls.()
    rows = rows()
    assert Enum.map(rows, & &1.transaction_id) == ["rent1", "rent2"]
    assert Enum.find(rows, &(&1.transaction_id == "rent2")).amount_cents == 125_000
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

  test "a yearly charge two years back survives the keep and is found, then proposed when due" do
    domain = [t("y1", "2024-11-25", 49.0, "Domain"), t("y2", "2025-11-25", 49.0, "Domain")]
    {http, _} = plaid([page(domain)], accounts(1500.0))

    assert {:ok, [], []} = fetch(http)
    assert length(rows()) == 2

    assert [%{period: :yearly, next: ~D[2026-11-25]}] = Server.Home.Bank.Recurring.series(Bank.transactions(), :out)
  end

  test "a price change is a notice of its own and not a new subscription, never a proposal" do
    dates = ~w(2026-06-17 2026-07-17 2026-08-17 2026-09-17 2026-10-17 2026-11-17)

    rows =
      for {d, i} <- Enum.with_index(dates), do: t("s#{i}", d, if(i < 3, do: 9.99, else: 12.99), "Streamr")

    {http, _} = plaid([page(rows)], accounts(1500.0))
    assert {:ok, [], []} = fetch(http)
    assert [%{kind: "price", text: "Streamr went up from $9.99 to $12.99", key: key}] = Source.notices(@today)
    assert key =~ ~r/^bank:price:[0-9a-f]{16}:1299$/
  end

  test "accounts with none spendable are logged once, by type and subtype, without balances" do
    savings =
      ok(%{
        "accounts" => [
          %{
            "account_id" => "sav",
            "name" => "S",
            "type" => "depository",
            "subtype" => "savings",
            "balances" => %{"current" => 77_123.0}
          }
        ]
      })

    {http, _} = plaid([page([]), page([], cursor: "c2")], savings)

    log = ExUnit.CaptureLog.capture_log(fn -> fetch(http) end)
    assert log =~ "no account is a checking account"
    assert log =~ "savings"
    refute log =~ ~r/77[,_]?123/

    assert ExUnit.CaptureLog.capture_log(fn -> fetch(http) end) == ""
  end

  describe "proposals that no longer hold" do
    defp hash(merchant),
      do:
        :sha256
        |> :crypto.hash(Server.Home.Bank.Recurring.key(merchant))
        |> Base.encode16(case: :lower)
        |> binary_part(0, 16)

    defp todo(key), do: %{key: key, kind: "todo", text: key}
    defp file(keys), do: Proposal.offer("telegram", "bank", Enum.map(keys, &todo/1), @now, [])
    defp open_keys, do: Enum.sort(Enum.map(Proposal.open(), & &1.key))

    defp poll(rows, available \\ 1500.0) do
      {http, _} = plaid([page(rows)], accounts(available))
      {:ok, _, resolved} = fetch(http)
      Proposal.resolve("bank", resolved, @now)
      resolved
    end

    test "every open new-subscription and price row is withdrawn, whatever the engine says" do
      new = "bank:new:#{hash("Streamr")}"
      price = "bank:price:#{hash("Streamr")}:1299"
      file([new, price])

      streamr =
        for {d, i} <- Enum.with_index(~w(2026-09-17 2026-10-17 2026-11-17)), do: t("s#{i}", d, 9.99, "Streamr")

      assert Enum.sort(poll(streamr)) == Enum.sort([new, price])
      assert open_keys() == []
    end

    test "a due row dated before today is withdrawn, a short one dated today or later is not" do
      past = "bank:due:#{hash("Rent")}:2026-11-19"
      later = "bank:due:#{hash("Rent")}:2026-11-22"
      file([past, later])
      assert poll(rent(), 1160.0) == [past]
      assert open_keys() == [later]
    end

    test "a due row the balance now covers is withdrawn, one not due any more as well" do
      covered = "bank:due:#{hash("Rent")}:2026-11-22"
      gone = "bank:due:#{hash("Gone")}:2026-11-23"
      file([covered, gone])
      assert Enum.sort(poll(rent(), 1500.0)) == Enum.sort([covered, gone])
      assert open_keys() == []
    end

    test "a taken and a dismissed row are left alone" do
      taken = "bank:new:#{hash("Gone")}"
      dismissed = "bank:new:#{hash("Gone Too")}"
      file([taken, dismissed])

      for p <- Proposal.open(),
          do: if(p.key == taken, do: Proposal.take("telegram", p.id, @now), else: Proposal.dismiss(p.id))

      assert poll(rent()) == []
      assert [%{state: :taken}] = Repo.all(from(p in Proposal, where: p.key == ^taken))
      assert [%{state: :dismissed}] = Repo.all(from(p in Proposal, where: p.key == ^dismissed))
    end

    test "double and relink rows are never withdrawn" do
      keys = ["bank:double:#{hash("Gone")}:1499:2026-11-01", "bank:relink:2026-10"]
      file(keys)
      assert poll(rent()) == []
      assert Enum.all?(keys, &(&1 in open_keys()))
    end
  end

  describe "notices" do
    defp streamr_price_up do
      dates = ~w(2026-06-17 2026-07-17 2026-08-17 2026-09-17 2026-10-17 2026-11-17)

      for {d, i} <- Enum.with_index(dates), do: t("s#{i}", d, if(i < 3, do: 9.99, else: 12.99), "Cloudy")
    end

    defp streamr_new,
      do: for({d, i} <- Enum.with_index(~w(2026-09-17 2026-10-17 2026-11-17)), do: t("n#{i}", d, 7.5, "Streamr"))

    defp keys, do: @today |> Source.notices() |> Enum.map(& &1.key) |> Enum.sort()

    setup do
      {http, _} = plaid([page(streamr_price_up() ++ streamr_new())], accounts(1500.0))
      {:ok, [], []} = fetch(http)
      :ok
    end

    test "a new subscription and a price change are listed, with the wording and a why" do
      assert [
               %{kind: "new", key: "bank:new:" <> _, text: new_text, why: "three steady charges, the last on 17 Nov"},
               %{kind: "price", key: "bank:price:" <> _, text: "Cloudy went up from $9.99 to $12.99", why: why}
             ] = Enum.sort_by(Source.notices(@today), & &1.kind)

      assert new_text == "Streamr looks like a new subscription: $7.50 monthly"
      assert why == "monthly, the last on 17 Nov"
    end

    test "a seen key is gone, marking twice is fine, and the other stays" do
      [new, price] = keys()
      assert Source.see(new) == :ok
      assert Source.see(new) == :ok
      assert keys() == [price]
      assert JSON.decode!(Keep.get("home_bank_seen")) == [new]
    end

    test "only a new or a price key can be marked" do
      assert Source.see("bank:due:abc:2026-11-22") == :error
      assert Source.see("bank:relink:2026-11") == :error
      assert Source.see(nil) == :error
      assert Keep.get("home_bank_seen") == nil
    end

    test "a key whose proposal was taken or dismissed is no notice" do
      [new, price] = keys()
      Proposal.offer("telegram", "bank", [todo(new), todo(price)], @now, [])

      for p <- Proposal.open(),
          do: if(p.key == new, do: Proposal.take("telegram", p.id, @now), else: Proposal.dismiss(p.id))

      assert keys() == []
    end

    test "an open bank proposal with the key does not hide it" do
      [new, _] = keys()
      Proposal.offer("telegram", "bank", [todo(new)], @now, [])
      assert [%{key: ^new}] = Proposal.open()
      assert new in keys()
    end

    test "a dismissed proposal from another source does not hide it" do
      [new, _] = keys()
      Proposal.offer("telegram", "mail", [todo(new)], @now, [])
      [row] = Proposal.open()
      Proposal.dismiss(row.id)
      assert new in keys()
    end
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

    test "the morning message carries the line, and the home answers it as JSON" do
      assert {text, []} = Server.Home.Morning.compose("telegram", @now)
      assert text =~ "Money: $1,240 available. Due this week: Rent $1,200 Sun, Phone Co $45 Tue."

      assert %{"due_this_week" => [%{"name" => "Rent", "on" => "2026-11-22"} | _], "balance" => 125_000} =
               @now |> then(&Bank.summary(now: &1)) |> JSON.encode!() |> JSON.decode!()
    end

    test "a regular transfer to savings is no deposit, and a deposit into savings is not the next deposit" do
      transfers =
        for {d, i} <- Enum.with_index(["2026-09-24", "2026-10-24", "2026-11-17"]) do
          [
            t("to#{i}", d, 300.0, "To Savings"),
            t("from#{i}", d, -300.0, "From Checking", %{"account_id" => "sav"})
          ]
        end

      interest =
        for {d, i} <- Enum.with_index(["2026-09-26", "2026-10-26", "2026-11-26"]),
            do: t("int#{i}", d, -2.0, "Interest", %{"account_id" => "sav"})

      {http, _} = plaid([page(List.flatten(transfers) ++ interest, cursor: "c2")], accounts(1240.0))
      {:ok, _, []} = fetch(http)

      summary = Bank.summary(now: @now)
      assert summary.next_deposit == %{name: "Acme Payroll", amount: 150_000, on: ~D[2026-11-27]}
      refute Enum.any?(summary.due_this_week, &(&1.name == "To Savings"))
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
