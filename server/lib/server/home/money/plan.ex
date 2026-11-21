defmodule Server.Home.Money.Plan do
  @moduledoc """
  The model's plan for a money question, read strictly. The model answers
  `{"asks": [ask, ...]}` (one to four asks) or `{"cannot": "why"}`; each ask is one of
  `{"ask": "summary"}`, `{"ask": "subscriptions"}`, `{"ask": "forecast", "until": date}`,
  `{"ask": "afford", "amount_cents": n, "on": date | null}`,
  `{"ask": "what_if", "until": date, "changes": [change, ...]}` or
  `{"ask": "history", "match": text | [text, ...] | null, "from": date, "to": date}` (a list is one to
  twelve merchant labels of one to forty characters, any of which matches), with a change one of
  `{"kind": "one_off", "amount_cents": n, "on": date, "name": s}` (a negative amount is money in),
  `{"kind": "recurring", "amount_cents": n, "rhythm": "weekly" | "fortnightly" | "monthly" |
  "yearly", "from": date, "name": s}`, `{"kind": "drop", "name": s}` or
  `{"kind": "change", "name": s, "amount_cents": n}`. Dates are `YYYY-MM-DD` and amounts whole
  cents; anything else, an unknown ask or kind, a date outside a year ahead (a history's `from` may
  go ten years back), an amount outside $1,000,000 is no plan: nothing is guessed. Names go to the
  engine as text and are matched there.
  """

  alias Server.Home.Bank.Projection

  @max_asks 4
  @max_changes 10
  @max_cents 100_000_000
  @max_name 80
  @max_matches 12
  @max_label 40
  @horizon 365
  @past 3_650
  @rhythms %{"weekly" => :weekly, "fortnightly" => :fortnightly, "monthly" => :monthly, "yearly" => :yearly}

  @type call ::
          :summary
          | :subscriptions
          | {:forecast, Date.t()}
          | {:afford, pos_integer(), Date.t() | nil}
          | {:what_if, [Projection.change()], Date.t()}
          | {:history, Projection.query()}
  @type ask :: %{json: map(), call: call()}

  @doc """
  The plan in a model's reply as of `today`: `{:ok, asks}` with each ask's canonical JSON and the
  call it names, `{:cannot, sentence}`, or `:error` when the reply holds no valid plan.
  """
  @spec parse(String.t(), Date.t()) :: {:ok, [ask()]} | {:cannot, String.t()} | :error
  def parse(out, today) do
    with [json] <- Regex.run(~r/\{.*\}/s, out),
         {:ok, %{} = plan} <- JSON.decode(json) do
      plan(plan, today)
    else
      _ -> :error
    end
  end

  defp plan(%{"cannot" => why}, _today) when is_binary(why) do
    case String.trim(why) do
      "" -> :error
      why -> {:cannot, why}
    end
  end

  defp plan(%{"asks" => [_ | _] = asks}, today) when length(asks) <= @max_asks, do: each(asks, &ask(&1, today))
  defp plan(_other, _today), do: :error

  defp each(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      :error -> :error
    end
  end

  defp ask(%{"ask" => "summary"}, _today), do: {:ok, %{json: %{"ask" => "summary"}, call: :summary}}

  defp ask(%{"ask" => "subscriptions"}, _today), do: {:ok, %{json: %{"ask" => "subscriptions"}, call: :subscriptions}}

  defp ask(%{"ask" => "forecast", "until" => until}, today) do
    with {:ok, until} <- ahead(until, today) do
      {:ok, %{json: %{"ask" => "forecast", "until" => Date.to_iso8601(until)}, call: {:forecast, until}}}
    end
  end

  defp ask(%{"ask" => "afford", "amount_cents" => cents} = ask, today)
       when is_integer(cents) and cents in 1..@max_cents do
    with {:ok, on} <- optional_on(Map.get(ask, "on"), today) do
      json = %{"ask" => "afford", "amount_cents" => cents, "on" => on && Date.to_iso8601(on)}
      {:ok, %{json: json, call: {:afford, cents, on}}}
    end
  end

  defp ask(%{"ask" => "what_if", "until" => until, "changes" => [_ | _] = changes}, today)
       when length(changes) <= @max_changes do
    with {:ok, until} <- ahead(until, today),
         {:ok, parsed} <- each(changes, &change(&1, today)) do
      {:ok,
       %{
         json: %{"ask" => "what_if", "until" => Date.to_iso8601(until), "changes" => Enum.map(parsed, & &1.json)},
         call: {:what_if, Enum.map(parsed, & &1.change), until}
       }}
    end
  end

  defp ask(%{"ask" => "history", "from" => from, "to" => to} = ask, today) do
    with {:ok, from} <- date(from, Date.add(today, -@past), Date.add(today, @horizon)),
         {:ok, to} <- date(to, from, Date.add(today, @horizon)),
         {:ok, match} <- match(Map.get(ask, "match")) do
      json = %{"ask" => "history", "match" => match, "from" => Date.to_iso8601(from), "to" => Date.to_iso8601(to)}
      {:ok, %{json: json, call: {:history, %{match: match, from: from, to: to}}}}
    end
  end

  defp ask(_other, _today), do: :error

  defp change(%{"kind" => "one_off", "amount_cents" => cents, "on" => on, "name" => name}, today)
       when is_integer(cents) and cents != 0 and abs(cents) <= @max_cents do
    with {:ok, on} <- ahead(on, today),
         {:ok, name} <- name(name) do
      json = %{"kind" => "one_off", "amount_cents" => cents, "on" => Date.to_iso8601(on), "name" => name}
      {:ok, %{json: json, change: {:one_off, cents, on, name}}}
    end
  end

  defp change(
         %{"kind" => "recurring", "amount_cents" => cents, "rhythm" => rhythm, "from" => from, "name" => name},
         today
       )
       when is_integer(cents) and cents in 1..@max_cents and is_map_key(@rhythms, rhythm) do
    with {:ok, from} <- ahead(from, today),
         {:ok, name} <- name(name) do
      json = %{
        "kind" => "recurring",
        "amount_cents" => cents,
        "rhythm" => rhythm,
        "from" => Date.to_iso8601(from),
        "name" => name
      }

      {:ok, %{json: json, change: {:recurring, cents, Map.fetch!(@rhythms, rhythm), from, name}}}
    end
  end

  defp change(%{"kind" => "drop", "name" => name}, _today) do
    with {:ok, name} <- name(name), do: {:ok, %{json: %{"kind" => "drop", "name" => name}, change: {:drop, name}}}
  end

  defp change(%{"kind" => "change", "name" => name, "amount_cents" => cents}, _today)
       when is_integer(cents) and cents in 1..@max_cents do
    with {:ok, name} <- name(name) do
      {:ok, %{json: %{"kind" => "change", "name" => name, "amount_cents" => cents}, change: {:change, name, cents}}}
    end
  end

  defp change(_other, _today), do: :error

  defp optional_on(nil, _today), do: {:ok, nil}
  defp optional_on(on, today), do: ahead(on, today)

  defp ahead(text, today), do: date(text, today, Date.add(today, @horizon))

  defp date(text, first, last) when is_binary(text) do
    with {:ok, date} <- Date.from_iso8601(text),
         true <- Date.compare(date, first) != :lt and Date.compare(date, last) != :gt do
      {:ok, date}
    else
      _ -> :error
    end
  end

  defp date(_other, _first, _last), do: :error

  defp match(nil), do: {:ok, nil}

  defp match(texts) when is_list(texts) and length(texts) in 1..@max_matches//1 do
    texts
    |> Enum.map(&label/1)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, text}, {:ok, acc} -> {:cont, {:ok, [text | acc]}}
      :error, _acc -> {:halt, :error}
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      :error -> :error
    end
  end

  defp match(texts) when is_list(texts), do: :error
  defp match(text), do: name(text)

  defp label(text) when is_binary(text) do
    case String.trim(text) do
      label when byte_size(label) in 1..@max_label//1 -> {:ok, label}
      _ -> :error
    end
  end

  defp label(_other), do: :error

  defp name(text) when is_binary(text) do
    case String.trim(text) do
      name when byte_size(name) in 1..@max_name//1 -> {:ok, name}
      _ -> :error
    end
  end

  defp name(_other), do: :error
end
