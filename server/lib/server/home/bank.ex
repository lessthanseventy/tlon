defmodule Server.Home.Bank do
  @moduledoc """
  What the home knows of the operator's bank, read-only through Plaid (`Server.Home.Bank.Plaid`),
  kept in `home_keep` as one JSON value, `home_bank`: the sync cursor, the transactions of the last
  400 days (upserted by `transaction_id`, `removed` ones dropped, a few hundred rows in all), the
  accounts with their cached balances and when it was read. `refresh/1` syncs and keeps the cursor
  with its data in one write, so a sync that fails anywhere keeps nothing and the next one starts
  from the cursor this update began with.

  `summary/0` is what the morning message and `GET /api/home` (`money`) say, worked out from what is
  kept with no call to Plaid (`Server.Home.Bank.Recurring`), nil when the `bank` source is off
  (`home_sources` without it, or no access token) or nothing was read yet. Its accounts are listed
  all; the spendable ones are the depository accounts of subtype checking, summed into `balance` and
  `available` (the available balance, else the current); savings and credit accounts are listed and
  never counted, so any number of accounts, whichever Plaid shows for the bank, works. All amounts
  are integers of cents.
  """

  alias Server.Home.Bank.Plaid
  alias Server.Home.Bank.Recurring
  alias Server.Home.Clock
  alias Server.Home.Keep
  alias Server.Home.Sources

  @key "home_bank"
  @keep_days 400
  @page 500
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

  @doc "What is kept: `%{}` before the first refresh."
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
    state = state()

    with {:ok, changes} <- sync(state["cursor"], opts, @retries),
         {:ok, accounts} <- Plaid.accounts(opts) do
      kept = %{
        "cursor" => changes.cursor,
        "transactions" => merge(Map.get(state, "transactions", []), changes, today(now)),
        "accounts" => accounts |> Enum.map(&account/1) |> Enum.reject(&is_nil/1),
        "as_of" => DateTime.to_iso8601(now)
      }

      Keep.put(@key, JSON.encode!(kept))
      {:ok, kept}
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
    [
      %{
        "id" => id,
        "account_id" => txn["account_id"],
        "cents" => round(amount * 100),
        "date" => date,
        "name" => txn["name"],
        "merchant" => txn["merchant_name"],
        "pending" => txn["pending"] == true
      }
    ]
  end

  defp row(_), do: []

  defp merge(kept, %{rows: rows, removed: removed}, today) do
    oldest = today |> Date.add(-@keep_days) |> Date.to_iso8601()

    (kept ++ rows)
    |> Map.new(&{&1["id"], &1})
    |> Map.drop(removed)
    |> Map.values()
    |> Enum.filter(&(is_binary(&1["date"]) and &1["date"] >= oldest))
    |> Enum.sort_by(&{&1["date"], &1["id"]})
  end

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
         %{"accounts" => [_ | _] = accounts, "as_of" => as_of} = state <- state() do
      today = opts |> Keyword.get_lazy(:now, &DateTime.utc_now/0) |> today()
      txns = transactions(state)
      spendable = Enum.filter(accounts, &spendable?/1)

      %{
        balance: total(spendable, & &1["current"]),
        available: total(spendable, &(&1["available"] || &1["current"])),
        as_of: as_of,
        due_this_week: txns |> Recurring.series(:out) |> Recurring.due_within(today, 6) |> Enum.map(&item/1),
        next_deposit: txns |> Recurring.series(:in) |> Enum.find(&(Date.compare(&1.next, today) != :lt)) |> deposit(),
        accounts: Enum.map(accounts, &Map.put(listed(&1), :spendable, spendable?(&1)))
      }
    else
      _ -> nil
    end
  end

  @doc "The transactions kept in `state`, as `Server.Home.Bank.Recurring.txn/1` reads them."
  @spec transactions(map()) :: [Recurring.txn()]
  def transactions(state),
    do: state |> Map.get("transactions", []) |> Enum.map(&Recurring.txn/1) |> Enum.reject(&is_nil/1)

  @doc "The local calendar date of the instant `now`."
  @spec today(DateTime.t()) :: Date.t()
  def today(now), do: now |> Clock.local() |> NaiveDateTime.to_date()

  defp spendable?(%{"type" => "depository", "subtype" => "checking"}), do: true
  defp spendable?(_), do: false

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

  defp deposit(nil), do: nil
  defp deposit(series), do: item(series)

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
end
