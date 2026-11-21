defmodule Server.Home.Money.Say do
  @moduledoc """
  The engine's results as the money chat shows and checks them. `present/1` turns a result into
  plain JSON data: every `*_cents` key gets a `*_cents_text` beside it in dollars as `Server.Home.Bank.money/1`
  says them, so the model copies amounts and never converts. `render/1` is the deterministic
  wording of the same data, used when the model's phrasing fails the check or the model is down.
  `check/2` finds the money amounts in a model's reply and says which are in no result.
  """

  alias Server.Home.Bank

  @events 40
  @months 36
  @rows 60
  @amount ~r/\$\s?(\d[\d,]*(?:\.\d+)?)([kKmMbB]\b)?|(\d[\d,]*(?:\.\d+)?)\s?(?:dollars|bucks|USD)\b/u

  @type entry :: %{ask: map(), result: {:ok, term()} | {:error, term()}}

  @doc ~s(The results as JSON-ready maps, `%{"ask" => ask, "result" => result}` each, with `*_cents_text` beside every `*_cents`.)
  @spec present([entry()]) :: [map()]
  def present(entries) do
    for %{ask: ask, result: result} <- entries do
      %{"ask" => walk(ask), "result" => walk(result(ask["ask"], result))}
    end
  end

  defp result(_ask, {:error, :no_data}), do: %{error: "no_data"}

  defp result(_ask, {:error, {:no_series, name, suggestions}}),
    do: %{error: "no_series", name: name, suggestions: suggestions}

  defp result("forecast", {:ok, forecast}), do: trim(forecast)

  defp result("afford", {:ok, afford}), do: %{afford | with: trim(afford.with), without: slim(afford.without)}

  defp result("what_if", {:ok, what_if}),
    do: %{what_if | baseline: slim(what_if.baseline), changed: trim(what_if.changed)}

  defp result("history", {:ok, history}), do: %{history | months: Enum.take(history.months, -@months)}
  defp result("subscriptions", {:ok, subscriptions}), do: Enum.take(subscriptions, @rows)
  defp result(_ask, {:ok, other}), do: other

  defp slim(forecast), do: forecast |> Map.drop([:days, :events]) |> Map.put(:end, List.last(forecast.days))

  defp trim(forecast), do: forecast |> slim() |> Map.put(:events, Enum.take(forecast.events, @events))

  defp walk(%Date{} = date), do: Date.to_iso8601(date)

  defp walk(map) when is_map(map) do
    Map.new(
      Enum.flat_map(map, fn {key, value} ->
        key = to_string(key)
        [{key, walk(value)} | text(key, value)]
      end)
    )
  end

  defp walk(list) when is_list(list), do: Enum.map(list, &walk/1)
  defp walk(atom) when is_atom(atom) and atom not in [nil, true, false], do: Atom.to_string(atom)
  defp walk(other), do: other

  defp text(key, cents) when is_integer(cents) do
    if String.ends_with?(key, "_cents"),
      do: [{key <> "_text", Bank.money(cents)}],
      else: []
  end

  defp text(_key, _value), do: []

  @doc """
  The money amounts in `reply` that are in none of `presented`'s `*_text` strings, compared in cents
  and without sign: `:ok` when there are none. An amount written with a suffix (`$1.2k`) or with
  more than two decimals cannot be compared and counts as missing. Only dollar amounts are looked
  at: not percentages, dates, counts, or numbers written in words.
  """
  @spec check(String.t(), [map()]) :: :ok | {:error, [String.t()]}
  def check(reply, presented) do
    known = presented |> texts() |> Enum.flat_map(&cents/1) |> MapSet.new()

    case Enum.reject(amounts(reply), fn {_text, cents} -> (cents != :invalid and cents in known) or cents == 0 end) do
      [] -> :ok
      missing -> {:error, Enum.map(missing, &elem(&1, 0))}
    end
  end

  defp amounts(reply) do
    for [whole | _] = match <- Regex.scan(@amount, reply) do
      {whole, amount(match)}
    end
  end

  defp amount([_, number, ""]), do: parse(number)
  defp amount([_, _number, _suffix]), do: :invalid
  defp amount([_, _, _, number]), do: parse(number)
  defp amount([_, number]), do: parse(number)

  defp cents(text) do
    for {_, cents} <- amounts(text), cents != :invalid, do: cents
  end

  defp parse(number) do
    number
    |> String.replace(",", "")
    |> String.split(".")
    |> case do
      [whole] ->
        String.to_integer(whole) * 100

      [whole, frac] when byte_size(frac) <= 2 ->
        String.to_integer(whole) * 100 + String.to_integer(String.pad_trailing(frac, 2, "0"))

      _ ->
        :invalid
    end
  end

  defp texts(%{} = map) do
    Enum.flat_map(map, fn
      {key, value} when is_binary(value) -> if String.ends_with?(key, "_text"), do: [value], else: []
      {_key, value} -> texts(value)
    end)
  end

  defp texts(list) when is_list(list), do: Enum.flat_map(list, &texts/1)
  defp texts(_other), do: []

  @doc "The presented results in plain words, one paragraph each, from the data alone."
  @spec render([map()]) :: String.t()
  def render(presented), do: Enum.map_join(presented, "\n\n", &entry/1)

  defp entry(%{"result" => %{"error" => "no_data"}}), do: "I have no bank data to work from yet."

  defp entry(%{"result" => %{"error" => "no_series", "name" => name, "suggestions" => suggestions}}) do
    case suggestions do
      [] -> ~s(I don't see a recurring charge called "#{name}".)
      names -> ~s(I don't see a recurring charge called "#{name}". Did you mean #{Enum.join(names, " or ")}?)
    end
  end

  defp entry(%{"ask" => %{"ask" => "summary"}, "result" => r}) do
    [
      "You have #{r["available_cents_text"]} available in checking.",
      due(r["due_this_week"]),
      deposit(r["next_deposit"])
    ]
    |> Enum.join(" ")
    |> String.trim()
  end

  defp entry(%{"ask" => %{"ask" => "subscriptions"}, "result" => []}), do: "I see no recurring charges."

  defp entry(%{"ask" => %{"ask" => "subscriptions"}, "result" => subscriptions}) do
    "Recurring charges: " <>
      Enum.map_join(subscriptions, "; ", &"#{&1["name"]} #{abs_text(&1)} #{&1["rhythm"]}, next #{day(&1["next"])}") <>
      "."
  end

  defp entry(%{"ask" => %{"ask" => "forecast"}, "result" => r}), do: Enum.join([outlook(r) | basis(r)], " ")

  defp entry(%{"ask" => %{"ask" => "afford"} = ask, "result" => r}) do
    on = if ask["on"], do: day(ask["on"]), else: "today"
    low = r["with"]["lowest"]
    purchase = "A purchase of #{ask["amount_cents_text"]} on #{on}"

    verdict =
      case r["verdict"] do
        "covers" ->
          "#{purchase} is covered: your lowest expected balance would be #{low["balance_cents_text"]} on #{day(low["date"])}."

        "tight" ->
          "#{purchase} is tight: your lowest expected balance would be #{low["balance_cents_text"]} on #{day(low["date"])}, under the #{r["cushion_cents_text"]} cushion."

        "short" ->
          "#{purchase} would leave you short by #{r["shortfall_cents_text"]} on #{day(r["short_on"])}."
      end

    worst =
      if r["worst_case"] != r["verdict"],
        do: "If everyday spending runs high it would be #{r["worst_case"]}."

    [verdict, worst | basis(r["with"])] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end

  defp entry(%{"ask" => %{"ask" => "what_if"}, "result" => r}) do
    base = r["baseline"]["end"]
    changed = r["changed"]["end"]

    Enum.join(
      [
        "As things are, your balance on #{day(base["date"])} is expected to be #{base["expected_cents_text"]} (lowest #{r["baseline"]["lowest"]["balance_cents_text"]}). With the change it is #{changed["expected_cents_text"]} (lowest #{r["changed"]["lowest"]["balance_cents_text"]}), a difference of #{r["difference"]["end_cents_text"]}."
        | basis(r["changed"])
      ],
      " "
    )
  end

  defp entry(%{"ask" => %{"ask" => "history"} = ask, "result" => r}) do
    what = if ask["match"], do: ~s( matching "#{ask["match"]}"), else: ""

    largest =
      r["largest"] |> Enum.take(3) |> Enum.map_join("; ", &"#{&1["name"]} #{abs_text(&1)} on #{day(&1["date"])}")

    "From #{day(ask["from"])} to #{day(ask["to"])}#{what}: #{r["count"]} transactions, on average #{r["average_out_cents_text"]} out and #{r["average_in_cents_text"]} in a month." <>
      if(largest == "", do: "", else: " Largest: #{largest}.")
  end

  defp outlook(r) do
    "Your checking balance is #{r["start_cents_text"]} today. By #{day(r["until"])} it is expected to be #{r["end"]["expected_cents_text"]}, and the lowest it is expected to get is #{r["lowest"]["balance_cents_text"]} on #{day(r["lowest"]["date"])}." <>
      if(r["clamped"], do: " That is as far ahead as I can look.", else: "")
  end

  defp basis(r) do
    basis = r["basis"]
    overdue = for %{"overdue" => true} = e <- r["events"] || [], do: overdue(e)

    skipped =
      if basis["skipped"] == [],
        do: [],
        else: ["I left out #{Enum.join(basis["skipped"], ", ")}: no charge has come for a long while."]

    ["This rests on #{months(basis["months_of_history"])} of history and the charges that repeat in it."] ++
      overdue ++ skipped ++ Enum.map(basis["caveats"], &caveat/1)
  end

  defp overdue(%{"name" => name, "expected_on" => on}),
    do: "#{name} was expected on #{day(on)} and has not posted; I have kept it just ahead."

  defp caveat("pending_ignored"), do: "Pending charges are already out of the available balance."
  defp caveat("short_history"), do: "There is under a month of history, so everyday spending is a rough average."
  defp caveat("skipped_charge"), do: "A charge I expected did not come."
  defp caveat("no_deposit_seen"), do: "I have not seen a regular deposit."
  defp caveat("one_off_bills_unknown"), do: "I cannot know about one-off bills that are not in the history."

  defp months(1), do: "1 month"
  defp months(n), do: "#{n} months"

  defp due([]), do: "Nothing recurring is due this week."

  defp due(items),
    do:
      "Due this week: " <>
        Enum.map_join(items, ", ", &"#{&1["name"]} #{&1["amount_cents_text"]} #{day(&1["on"])}") <> "."

  defp deposit(nil), do: ""
  defp deposit(d), do: "Next deposit: #{d["name"]}, #{d["amount_cents_text"]} on #{day(d["on"])}."

  defp abs_text(%{"amount_cents" => cents}), do: Bank.money(abs(cents))

  defp day(iso), do: iso |> Date.from_iso8601!() |> Calendar.strftime("%a %-d %b")
end
