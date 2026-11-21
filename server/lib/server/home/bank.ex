defmodule Server.Home.Bank do
  @moduledoc """
  What the home knows of the operator's bank, read-only through Plaid (`Server.Home.Bank.Plaid`),
  kept in two places: the transactions of the last 800 days, one row each in `home_bank_transactions`
  (`Server.Home.Bank.Transaction`, upserted by `transaction_id`, `removed` ones dropped), and in
  `home_keep` as one small JSON value, `home_bank`: the sync cursor, the accounts with their cached
  balances, when they were read and the summary's dated part. `refresh/1` syncs and writes rows and
  keep in one database transaction, so a sync that fails anywhere keeps nothing and the next one
  starts from the cursor this update began with.

  A `home_bank` still carrying a `transactions` list (the earlier storage) is moved into the table by
  the first read or refresh that sees it, in one database transaction with the keep rewritten
  without the list. Rows that do not parse are skipped, and then the cursor is dropped too so the next
  sync fetches them again.

  `summary/0` is what the morning message and `GET /api/home` (`money`) say, worked out once per
  refresh from the rows with no call to Plaid (`Server.Home.Bank.Recurring`) and read from the keep;
  the parts that depend on today (due this week, the next deposit) are stored with the local day they
  were worked out for and recomputed from the rows when read on another day. It is nil when the
  `bank` source is off (`home_sources` without it, or no access token) or nothing was read yet. Its accounts are listed
  all; the spendable ones are the depository accounts of subtype checking, summed into `balance` and
  `available` (the available balance, else the current); savings and credit accounts are listed and
  never counted, so any number of accounts, whichever Plaid shows for the bank, works. All amounts
  are integers of cents.
  """

  import Ecto.Query, only: [from: 2]

  alias Server.Home.Bank.Plaid
  alias Server.Home.Bank.Projection
  alias Server.Home.Bank.Recurring
  alias Server.Home.Bank.Transaction
  alias Server.Home.Clock
  alias Server.Home.Keep
  alias Server.Home.Sources
  alias Server.Repo

  require Logger

  @key "home_bank"
  @keep_days 800
  @page 500
  @batch 1000
  @pages 40
  @retries 2
  @mutation "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION"

  @type money :: %{
          balance: integer() | nil,
          available: integer() | nil,
          as_of: String.t(),
          due_this_week: [%{name: String.t(), amount: integer(), on: Date.t()}],
          next_deposit: %{name: String.t(), amount: integer(), on: Date.t()} | nil,
          accounts: [map()]
        }

  @doc "Whether the bank source is on: `home_sources` names `bank` and an access token is present."
  @spec enabled?() :: boolean()
  def enabled?,
    do: "bank" in Sources.names(Server.OperatorConfig.setting("home_sources")) and Plaid.access_token() != nil

  @doc "What is kept in the keep: `%{}` before the first refresh. The transactions are `transactions/0`."
  @spec state() :: map()
  def state do
    with body when is_binary(body) <- Keep.get(@key),
         {:ok, %{} = state} <- JSON.decode(body) do
      state
    else
      _ -> %{}
    end
  end

  @doc """
  Sync the transactions and read the accounts, then keep both with the new cursor: `{:ok, state}` or
  the first `{:error, reason}` of `Server.Home.Bank.Plaid`, with nothing kept. Options: `:now`, and
  those of the client.
  """
  @spec refresh(keyword()) :: {:ok, map()} | {:error, term()}
  def refresh(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    state = state!()
    today = today(now)

    with {:ok, changes} <- sync(state["cursor"], opts, @retries),
         {:ok, accounts} <- Plaid.accounts(opts) do
      accounts = accounts |> Enum.map(&account/1) |> Enum.reject(&is_nil/1)
      warn_unspendable(accounts, Map.get(state, "accounts", []))

      Repo.transaction(fn ->
        apply_changes(changes, today)

        kept = %{
          "cursor" => changes.cursor,
          "accounts" => accounts,
          "as_of" => DateTime.to_iso8601(now),
          "summary" => accounts |> fresh(today) |> stored(today)
        }

        Keep.put(@key, JSON.encode!(kept))
        kept
      end)
    end
  end

  defp sync(start, opts, retries) do
    case pages(start, %{cursor: start, rows: [], removed: []}, opts, @pages) do
      {:error, {:plaid, @mutation}} when retries > 0 -> sync(start, opts, retries - 1)
      other -> other
    end
  end

  defp pages(_cursor, _acc, _opts, 0), do: {:error, :too_many_pages}

  defp pages(cursor, acc, opts, left) do
    case Plaid.sync(cursor, @page, opts) do
      {:ok, %{"next_cursor" => next} = page} when is_binary(next) ->
        acc = %{
          cursor: next,
          rows: acc.rows ++ Enum.flat_map(list(page["added"]) ++ list(page["modified"]), &row/1),
          removed: acc.removed ++ for(%{"transaction_id" => id} <- list(page["removed"]), do: id)
        }

        if page["has_more"] == true, do: pages(next, acc, opts, left - 1), else: {:ok, acc}

      {:ok, _} ->
        {:error, :unexpected_reply}

      {:error, _} = error ->
        error
    end
  end

  defp list(items) when is_list(items), do: items
  defp list(_), do: []

  defp row(%{"transaction_id" => id, "amount" => amount, "date" => date} = txn)
       when is_binary(id) and is_number(amount) and is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} ->
        [
          %{
            transaction_id: id,
            account_id: txn["account_id"],
            amount_cents: round(amount * 100),
            date: date,
            name: txn["name"],
            merchant_name: txn["merchant_name"],
            pending: txn["pending"] == true
          }
        ]

      {:error, _} ->
        []
    end
  end

  defp row(_), do: []

  defp account(%{"account_id" => id} = account) when is_binary(id) do
    balances = account["balances"] || %{}

    %{
      "id" => id,
      "name" => Recurring.line(account["name"], 40),
      "type" => account["type"],
      "subtype" => account["subtype"],
      "current" => cents(balances["current"]),
      "available" => cents(balances["available"])
    }
  end

  defp account(_), do: nil

  defp cents(amount) when is_number(amount), do: round(amount * 100)
  defp cents(_), do: nil

  @doc """
  The money as the morning message and the home say it at `opts[:now]`: `%{balance, available, as_of,
  due_this_week, next_deposit, accounts}`, nil when the source is off or nothing was read yet.
  `due_this_week` is the recurring charges expected from today through six days on, soonest first.
  """
  @spec summary(keyword()) :: money() | nil
  def summary(opts \\ []) do
    with true <- enabled?(),
         %{"accounts" => [_ | _] = accounts, "as_of" => as_of} = state <- state!() do
      today = opts |> Keyword.get_lazy(:now, &DateTime.utc_now/0) |> today()
      spendable = Enum.filter(accounts, &spendable?/1)
      dated = dated(state["summary"], accounts, today)

      %{
        balance: total(spendable, & &1["current"]),
        available: spendable_available(accounts),
        as_of: as_of,
        due_this_week: dated.due_this_week,
        next_deposit: dated.next_deposit,
        accounts: Enum.map(accounts, &Map.put(listed(&1), :spendable, spendable?(&1)))
      }
    else
      _ -> nil
    end
  end

  @doc "The transactions kept, as `Server.Home.Bank.Recurring.txn/1` reads them."
  @spec transactions() :: [Recurring.txn()]
  def transactions do
    from(t in Transaction,
      order_by: [t.date, t.transaction_id],
      select: %{
        "id" => t.transaction_id,
        "account_id" => t.account_id,
        "cents" => t.amount_cents,
        "date" => t.date,
        "name" => t.name,
        "merchant" => t.merchant_name,
        "pending" => t.pending
      }
    )
    |> Repo.all()
    |> Enum.map(&(&1 |> Map.update!("date", fn date -> Date.to_iso8601(date) end) |> Recurring.txn()))
    |> Enum.reject(&is_nil/1)
    |> Recurring.without_transfers()
  end

  @doc """
  The balance day by day to `until` (`Server.Home.Bank.Projection.forecast/3`), from the transactions
  and accounts kept; `{:error, :no_data}` when the source is off or nothing is stored. `today` is the
  local day.
  """
  @spec forecast(Date.t(), Date.t()) :: {:ok, Projection.forecast()} | {:error, :no_data}
  def forecast(until, today \\ local_today()), do: projected(&Projection.forecast(&1, today, until))

  @doc """
  Whether a purchase of `amount_cents` on `on` (default today) is covered
  (`Server.Home.Bank.Projection.afford/5`). Options: `:today`, `:cushion_cents`. An amount that is
  not a positive integer is `{:error, :bad_amount}`.
  """
  @spec afford(term(), Date.t() | nil, keyword()) ::
          {:ok, Projection.afford()} | {:error, :no_data | :beyond_horizon | :bad_amount}
  def afford(amount_cents, on \\ nil, opts \\ []) do
    {today, opts} = Keyword.pop_lazy(opts, :today, &local_today/0)
    projected(&Projection.afford(&1, today, amount_cents, on, opts))
  end

  @doc """
  The forecast with and without `changes` (`Server.Home.Bank.Projection.what_if/4`); a cost that is
  not an amount the change allows is `{:error, :bad_amount}`.
  """
  @spec what_if([Projection.change()], Date.t(), Date.t()) ::
          {:ok, Projection.what_if()}
          | {:error, :no_data | :beyond_horizon | :bad_amount | {:no_series, String.t(), [String.t()]}}
  def what_if(changes, until, today \\ local_today()), do: projected(&Projection.what_if(&1, today, changes, until))

  @doc "What went out and came in by month for a query (`Server.Home.Bank.Projection.history/2`)."
  @spec history(Projection.query()) :: {:ok, Projection.history()} | {:error, :no_data | :bad_range}
  def history(query), do: projected(&Projection.history(&1, query))

  @doc "The recurring charges for display (`Server.Home.Bank.Projection.subscriptions/2`)."
  @spec subscriptions(Date.t()) :: {:ok, [Projection.subscription()]} | {:error, :no_data}
  def subscriptions(today \\ local_today()), do: projected(&{:ok, Projection.subscriptions(&1, today)})

  @doc "The local calendar date of the instant `now`."
  @spec today(DateTime.t()) :: Date.t()
  def today(now), do: now |> Clock.local() |> NaiveDateTime.to_date()

  @doc "Whether a kept account counts toward the money: a depository account of subtype checking."
  @spec spendable?(map()) :: boolean()
  def spendable?(%{"type" => "depository", "subtype" => "checking"}), do: true
  def spendable?(_), do: false

  @doc "The available balance (else the current) summed over the spendable kept accounts, in cents; nil when there is none."
  @spec spendable_available([map()]) :: integer() | nil
  def spendable_available(accounts),
    do: accounts |> Enum.filter(&spendable?/1) |> total(&(&1["available"] || &1["current"]))

  @doc """
  The available balance (else the current) of the depository accounts that are not spendable, as
  `%{cents, names}`: savings and the like, the working buffer beside checking. Zero cents and no
  names when there are none.
  """
  @spec other_available([map()]) :: %{cents: integer(), names: [String.t()]}
  def other_available(accounts) do
    others = Enum.filter(accounts, &(&1["type"] == "depository" and not spendable?(&1)))

    %{
      cents: total(others, &(&1["available"] || &1["current"])) || 0,
      names: for(account <- others, is_binary(account["name"]) and account["name"] != "", do: account["name"])
    }
  end

  defp total([], _), do: nil

  defp total(accounts, amount) do
    accounts
    |> Enum.map(amount)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      amounts -> Enum.sum(amounts)
    end
  end

  defp item(series), do: %{name: series.label, amount: series.amount, on: series.next}

  defp listed(account) do
    %{
      id: account["id"],
      name: account["name"],
      type: account["type"],
      subtype: account["subtype"],
      balance: account["current"],
      available: account["available"]
    }
  end

  @doc "Dollars as said aloud: `$1,200` for whole dollars, `$14.99` otherwise."
  @spec money(integer()) :: String.t()
  def money(cents) when cents < 0, do: "-" <> money(-cents)

  def money(cents) do
    dollars =
      cents
      |> div(100)
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    if rem(cents, 100) == 0,
      do: "$#{dollars}",
      else: "$#{dollars}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  @doc """
  The one calm line the morning message gives `summary` at `today`, nil when it has nothing to say:
  `Money: $1,240 available. Due this week: Rent $1,200 Fri. Next deposit about Fri.`
  """
  @spec line(money() | nil, Date.t()) :: String.t() | nil
  def line(nil, _today), do: nil

  def line(%{available: available, due_this_week: due, next_deposit: deposit}, today) do
    case Enum.reject([available(available), due(due), deposit(deposit, today)], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  defp available(nil), do: nil
  defp available(cents), do: "Money: #{money(cents)} available."

  defp due([]), do: nil

  defp due(items),
    do: "Due this week: " <> Enum.map_join(items, ", ", &"#{&1.name} #{money(&1.amount)} #{day(&1.on)}") <> "."

  defp deposit(nil, _today), do: nil

  defp deposit(%{on: on}, today),
    do: "Next deposit about #{if Date.diff(on, today) <= 6, do: day(on), else: Calendar.strftime(on, "%a %-d %b")}."

  defp day(date), do: Calendar.strftime(date, "%a")

  defp warn_unspendable([], _before), do: :ok

  defp warn_unspendable(accounts, before) do
    if not Enum.any?(accounts, &spendable?/1) and kinds(accounts) != kinds(before) do
      Logger.warning(
        "home bank: no account is a checking account, so there is no money line: #{inspect(kinds(accounts))}"
      )
    end

    :ok
  end

  defp kinds(accounts), do: accounts |> Enum.map(&{&1["type"], &1["subtype"]}) |> Enum.sort()

  defp next_deposit(series, spendable, today) do
    ids = Enum.map(spendable, & &1["id"])

    case Enum.find(series, &(&1.account_id in ids and Date.compare(&1.next, today) != :lt)) do
      nil -> nil
      found -> item(found)
    end
  end

  defp state! do
    case state() do
      %{"transactions" => carried} = state -> carry_over(state, carried)
      state -> state
    end
  end

  defp carry_over(state, carried) do
    parsed = Enum.map(list(carried), &carried_row/1)
    rows = for {:ok, row} <- parsed, do: row
    skipped = length(parsed) - length(rows)
    kept = Map.delete(state, "transactions")

    kept =
      if skipped == 0 do
        kept
      else
        Logger.warning("home bank: #{skipped} kept transactions did not parse, so the next sync starts from no cursor")
        Map.delete(kept, "cursor")
      end

    {:ok, kept} =
      Repo.transaction(fn ->
        upsert(rows)
        Keep.put(@key, JSON.encode!(kept))
        kept
      end)

    kept
  end

  defp carried_row(%{"id" => id, "cents" => cents, "date" => date} = row) when is_binary(id) and is_integer(cents) do
    case Date.from_iso8601(to_string(date)) do
      {:ok, date} ->
        {:ok,
         %{
           transaction_id: id,
           account_id: row["account_id"],
           amount_cents: cents,
           date: date,
           name: row["name"],
           merchant_name: row["merchant"],
           pending: row["pending"] == true
         }}

      {:error, _} ->
        :error
    end
  end

  defp carried_row(_), do: :error

  defp apply_changes(%{rows: rows, removed: removed}, today) do
    upsert(rows)

    for ids <- Enum.chunk_every(removed, @batch),
        do: Repo.delete_all(from(t in Transaction, where: t.transaction_id in ^ids))

    oldest = Date.add(today, -@keep_days)
    Repo.delete_all(from(t in Transaction, where: t.date < ^oldest))
    :ok
  end

  defp upsert(rows) do
    for batch <- rows |> Map.new(&{&1.transaction_id, &1}) |> Map.values() |> Enum.chunk_every(@batch) do
      Repo.insert_all(Transaction, batch,
        on_conflict: {:replace_all_except, [:transaction_id]},
        conflict_target: :transaction_id
      )
    end

    :ok
  end

  defp dated(%{"for" => day, "due_this_week" => due, "next_deposit" => deposit}, accounts, today) do
    if day == Date.to_iso8601(today),
      do: %{due_this_week: Enum.map(due, &read_item/1), next_deposit: deposit && read_item(deposit)},
      else: fresh(accounts, today)
  end

  defp dated(_, accounts, today), do: fresh(accounts, today)

  defp fresh(accounts, today) do
    txns = transactions()
    spendable = Enum.filter(accounts, &spendable?/1)

    %{
      due_this_week: txns |> Recurring.series(:out) |> Recurring.due_within(today, 6) |> Enum.map(&item/1),
      next_deposit: txns |> Recurring.series(:in) |> next_deposit(spendable, today)
    }
  end

  defp stored(%{due_this_week: due, next_deposit: deposit}, today),
    do: %{"for" => Date.to_iso8601(today), "due_this_week" => due, "next_deposit" => deposit}

  defp read_item(%{"name" => name, "amount" => amount, "on" => on}),
    do: %{name: name, amount: amount, on: Date.from_iso8601!(on)}

  defp local_today, do: today(DateTime.utc_now())

  defp projected(fun) do
    with true <- enabled?(),
         %{"accounts" => [_ | _] = accounts} <- state() do
      fun.(%{transactions: transactions(), accounts: accounts})
    else
      _ -> {:error, :no_data}
    end
  end
end
