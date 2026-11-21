defmodule Server.Home.Source.Bank do
  @moduledoc """
  The operator's bank as a source of proposals (`Server.Home.Source`), enabled by `home_sources:
  "bank"` and an access token (`Server.Home.Bank.Plaid`); with no token every fetch is
  `{:error, "no Plaid access token"}`, which the poller logs once. Each fetch syncs the transactions
  and the accounts (`Server.Home.Bank.refresh/1`, read-only) and proposes, as to-dos, only where
  there is something to do:

  - a recurring charge expected within five days, with whether the available balance of its account
    covers it, keyed `bank:due:<merchant hash>:<expected date>`;
  - two charges of one amount at one merchant within two days that are not a habit, keyed by merchant,
    amount and the later day;
  - a merchant whose third steady charge has just made it recurring ("looks like a new
    subscription"), keyed by the merchant, so once ever.

  A key is filed once and a dismissed one never returns, as `Server.Proposal.offer/5` has it;
  nothing is filed without a yes (`auto/0` is empty). Merchant names are outside text: shortened to a
  line, shown, never obeyed. Plaid's `ITEM_LOGIN_REQUIRED` is one proposal that the bank needs
  linking again, keyed by the month; any other failure is returned for the poller to log and the next
  fetch retries from the cursor kept with the data.
  """
  @behaviour Server.Home.Source

  alias Server.Home.Bank
  alias Server.Home.Bank.Plaid
  alias Server.Home.Bank.Recurring

  @due_days 5

  @impl true
  def name, do: "bank"

  @impl true
  def auto, do: []

  @doc """
  What the bank suggests at `opts[:now]` (default the clock): `{:ok, proposals, []}` or
  `{:error, reason}`. Options for a test are `Server.Home.Bank.refresh/1`'s.
  """
  @impl true
  @spec fetch(keyword()) :: {:ok, [map()], []} | {:error, term()}
  def fetch(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    today = Bank.today(now)

    with token when is_binary(token) <- Plaid.access_token(opts) || {:error, "no Plaid access token"} do
      case Bank.refresh(Keyword.put(opts, :now, now)) do
        {:ok, state} -> {:ok, proposals(state, accounts(state), today), []}
        {:error, {:plaid, "ITEM_LOGIN_REQUIRED"}} -> {:ok, [relink(today)], []}
        {:error, _} = error -> error
      end
    end
  end

  @doc "The proposals the kept `state` gives on `today`."
  @spec proposals(map(), %{String.t() => map()}, Date.t()) :: [map()]
  def proposals(state, accounts, today) do
    txns = Bank.transactions(state)
    out = Recurring.series(txns, :out)

    for(series <- Recurring.due_within(out, today, @due_days), do: due(series, accounts)) ++
      for(double <- Recurring.doubles(txns, today), do: double(double)) ++
      for series <- Recurring.new_series(out, today), do: new(series)
  end

  defp accounts(state), do: Map.new(Map.get(state, "accounts", []), &{&1["id"], &1})

  defp due(series, accounts) do
    %{
      key: "bank:due:#{hash(series.key)}:#{Date.to_iso8601(series.next)}",
      kind: "todo",
      text:
        "#{series.label} #{Bank.money(series.amount)} is due #{Calendar.strftime(series.next, "%a %-d %b")}" <>
          cover(accounts[series.account_id], series.amount),
      why: "#{series.period}, last on #{Calendar.strftime(series.last, "%-d %b")}"
    }
  end

  defp cover(nil, _amount), do: ""

  defp cover(account, amount) do
    case account["available"] || account["current"] do
      nil -> ""
      available when available >= amount -> "; the balance covers it"
      available -> "; the balance is #{Bank.money(amount - available)} short"
    end
  end

  defp double(%{key: key, label: label, cents: cents, on: on}) do
    %{
      key: "bank:double:#{hash(key)}:#{cents}:#{Date.to_iso8601(on)}",
      kind: "todo",
      text: "Two charges of #{Bank.money(cents)} from #{label} on #{Calendar.strftime(on, "%a")}: check for a double",
      why: "same merchant and amount within two days"
    }
  end

  defp new(series) do
    %{
      key: "bank:new:#{hash(series.key)}",
      kind: "todo",
      text: "#{series.label} looks like a new subscription: #{Bank.money(series.amount)} #{series.period}",
      why: "three steady charges, the last on #{Calendar.strftime(series.last, "%-d %b")}"
    }
  end

  defp relink(today) do
    %{
      key: "bank:relink:#{Calendar.strftime(today, "%Y-%m")}",
      kind: "todo",
      text: "The bank needs linking again",
      why: "its login expired, so nothing more is read"
    }
  end

  defp hash(key), do: :sha256 |> :crypto.hash(key) |> Base.encode16(case: :lower) |> binary_part(0, 16)
end
