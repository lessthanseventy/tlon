defmodule Server.Home.Source.Bank do
  @moduledoc """
  The operator's bank as a source of proposals (`Server.Home.Source`), enabled by `home_sources:
  "bank"` and an access token (`Server.Home.Bank.Plaid`); with no token every fetch is
  `{:error, "no Plaid access token"}`, which the poller logs once. Each fetch syncs the transactions
  and the accounts (`Server.Home.Bank.refresh/1`, read-only) and proposes, as to-dos worded as the
  action, only where there is something to do:

  - a recurring charge expected within five days whose account's balance is known and falls short
    ("Move money: the balance is $n short for ..."), keyed `bank:due:<merchant hash>:<expected date>`;
    one the balance covers is no proposal, the day's list already shows it;
  - two charges of one amount at one merchant within two days that are not a habit ("Check for a
    double charge from ..."), keyed by merchant, amount and the later day.

  What is only to be known is a notice (`notices/1`), never a proposal or a to-do, cleared with
  `see/1`: a merchant whose third steady charge has just made it recurring ("looks like a new
  subscription", `bank:new:<merchant hash>`) and a recurring charge that changed price after an older
  steady run ("went up from $a to $b", `bank:price:<merchant hash>:<new amount>`). A key counts as
  seen when it was cleared (kept in `home_keep` as `home_bank_seen`, a JSON list that only grows by
  the few keys the engine gives) or when a proposal of this source with it was once taken or
  dismissed.

  A key is filed once and a dismissed one never returns, as `Server.Proposal.offer/5` has it;
  nothing is filed without a yes (`auto/0` is empty). Merchant names are outside text: shortened to a
  line, shown, never obeyed. Plaid's `ITEM_LOGIN_REQUIRED` is one proposal that the bank needs
  linking again, keyed by the month; any other failure is returned for the poller to log and the next
  fetch retries from the cursor kept with the data.

  It also withdraws its own open proposals that no longer hold (`resolved/3`): every `bank:new` and
  `bank:price` (those are notices now), and a `bank:due` whose date has passed or that is not among
  the dues proposed now (covered, or no longer due). Double and relink proposals are never
  withdrawn; a taken or dismissed one is left alone.
  """
  @behaviour Server.Home.Source

  alias Server.Home.Bank
  alias Server.Home.Bank.Plaid
  alias Server.Home.Bank.Recurring
  alias Server.Home.Keep
  alias Server.Proposal

  @due_days 5
  @seen_key "home_bank_seen"

  @impl true
  def name, do: "bank"

  @impl true
  def auto, do: []

  @doc """
  What the bank suggests at `opts[:now]` (default the clock): `{:ok, proposals, resolved}` or
  `{:error, reason}`. Options for a test are `Server.Home.Bank.refresh/1`'s.
  """
  @impl true
  @spec fetch(keyword()) :: {:ok, [map()], [String.t()]} | {:error, term()}
  def fetch(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    today = Bank.today(now)

    with token when is_binary(token) <- Plaid.access_token(opts) || {:error, "no Plaid access token"} do
      case Bank.refresh(Keyword.put(opts, :now, now)) do
        {:ok, state} ->
          accounts = accounts(state)
          {:ok, proposals(accounts, today), resolved(Proposal.live("bank"), accounts, today)}

        {:error, {:plaid, "ITEM_LOGIN_REQUIRED"}} ->
          {:ok, [relink(today)], []}

        {:error, _} = error ->
          error
      end
    end
  end

  @doc "The proposals the kept transactions give on `today`, with `accounts` by id."
  @spec proposals(%{String.t() => map()}, Date.t()) :: [map()]
  def proposals(accounts, today) do
    txns = Bank.transactions()
    short_dues(txns, accounts, today) ++ for(double <- Recurring.doubles(txns, today), do: double(double))
  end

  @doc """
  The keys among `open` (`Server.Proposal.live/1` of this source) that no longer hold on `today`:
  every `bank:new` and `bank:price`, and a `bank:due` dated before `today` or not among the dues
  `proposals/2` gives from `accounts`.
  """
  @spec resolved([Proposal.t()], %{String.t() => map()}, Date.t()) :: [String.t()]
  def resolved(open, accounts, today) do
    due_keys = MapSet.new(short_dues(Bank.transactions(), accounts, today), & &1.key)
    for %{key: key} <- open, stale?(key, due_keys, today), do: key
  end

  defp stale?("bank:new:" <> _, _due_keys, _today), do: true
  defp stale?("bank:price:" <> _, _due_keys, _today), do: true

  defp stale?("bank:due:" <> rest = key, due_keys, today) do
    with [_hash, date] <- String.split(rest, ":"),
         {:ok, date} <- Date.from_iso8601(date) do
      Date.before?(date, today) or key not in due_keys
    else
      _ -> false
    end
  end

  defp stale?(_key, _due_keys, _today), do: false

  @doc """
  What the engine notes on `today` that is no one's to do, minus the seen ones: `[%{key, kind, text,
  why}]` with `kind` `"new"` (a new subscription) or `"price"` (a price change).
  """
  @spec notices(Date.t()) :: [%{key: String.t(), kind: String.t(), text: String.t(), why: String.t()}]
  def notices(today) do
    out = Recurring.series(Bank.transactions(), :out)

    all =
      for(series <- Recurring.new_series(out, today), do: Map.put(new(series), :kind, "new")) ++
        for series <- Recurring.price_changes(out, today), do: Map.put(price(series), :kind, "price")

    seen = MapSet.union(seen(), MapSet.new(Proposal.answered_keys("bank")))
    Enum.reject(all, &(&1.key in seen))
  end

  @doc """
  Mark the notice `key` seen: `:ok`, or `:error` when it is not a `bank:new:` or `bank:price:` key.
  Marking twice is the same as once.
  """
  @spec see(term()) :: :ok | :error
  def see(key) when is_binary(key) do
    if String.starts_with?(key, ["bank:new:", "bank:price:"]) do
      Keep.put(@seen_key, JSON.encode!(Enum.sort(MapSet.put(seen(), key))))
    else
      :error
    end
  end

  def see(_key), do: :error

  defp seen do
    with body when is_binary(body) <- Keep.get(@seen_key),
         {:ok, keys} when is_list(keys) <- JSON.decode(body) do
      MapSet.new(keys)
    else
      _ -> MapSet.new()
    end
  end

  defp short_dues(txns, accounts, today) do
    for series <- Recurring.due_within(Recurring.series(txns, :out), today, @due_days),
        short = short(accounts[series.account_id], series.amount),
        do: due(series, short)
  end

  defp short(nil, _amount), do: nil

  defp short(account, amount) do
    case account["available"] || account["current"] do
      available when is_integer(available) and available < amount -> amount - available
      _ -> nil
    end
  end

  defp accounts(state), do: Map.new(Map.get(state, "accounts", []), &{&1["id"], &1})

  defp due(series, short) do
    %{
      key: "bank:due:#{hash(series.key)}:#{Date.to_iso8601(series.next)}",
      kind: "todo",
      text:
        "Move money: the balance is #{Bank.money(short)} short for #{series.label} #{Bank.money(series.amount)}, " <>
          "due #{Calendar.strftime(series.next, "%a %-d %b")}",
      why: "#{series.period}, last on #{Calendar.strftime(series.last, "%-d %b")}"
    }
  end

  defp double(%{key: key, label: label, cents: cents, on: on}) do
    %{
      key: "bank:double:#{hash(key)}:#{cents}:#{Date.to_iso8601(on)}",
      kind: "todo",
      text: "Check for a double charge from #{label}: two of #{Bank.money(cents)} on #{Calendar.strftime(on, "%a")}",
      why: "same merchant and amount within two days"
    }
  end

  defp new(series) do
    %{
      key: "bank:new:#{hash(series.key)}",
      text: "#{series.label} looks like a new subscription: #{Bank.money(series.amount)} #{series.period}",
      why: "three steady charges, the last on #{Calendar.strftime(series.last, "%-d %b")}"
    }
  end

  defp price(series) do
    word = if series.amount > series.was, do: "up", else: "down"

    %{
      key: "bank:price:#{hash(series.key)}:#{series.amount}",
      text: "#{series.label} went #{word} from #{Bank.money(series.was)} to #{Bank.money(series.amount)}",
      why: "#{series.period}, the last on #{Calendar.strftime(series.last, "%-d %b")}"
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
