defmodule Server.Home.Reader do
  @moduledoc """
  What a jot means: one small model call reads a message the operator texted the home's inbox and
  answers a reading, `%{kind, text, due_at, amends}`. `kind` is `"reminder"` (a time to be told,
  `due_at` in UTC) or `"note"`; `amends` says the message corrects the jot before it, and the reading
  is then that jot's, corrected. Times are read and said in the machine's own zone. The model is
  Haiku on the operator's Claude login, with no tools (`:home_reader_cmd` and `:home_reader_model`
  name another): what a person texts themselves stays with the provider they already use.
  """

  require Logger

  @type reading :: %{kind: String.t(), text: String.t(), due_at: DateTime.t() | nil, amends: boolean()}

  @doc "Read `body`, `previous` the jot filed before it (nil when none): `{:ok, reading}`, `:error` when no reading came back."
  @spec read(String.t(), Server.Jot.t() | nil) :: {:ok, reading()} | :error
  def read(body, previous) do
    now = NaiveDateTime.from_erl!(:calendar.local_time())
    opts = [timeout_s: 60, tools: "", settings: "user"]

    case Server.ModelCli.prompt(
           prompt(body, previous, now),
           :home_reader_cmd,
           :home_reader_model,
           {"claude", "haiku"},
           opts
         ) do
      {:ok, out} ->
        parse(out)

      {:error, why} ->
        Logger.warning("home reader: no reading: #{inspect(why)}")
        :error
    end
  end

  @doc "The reading in a model's reply: `{:ok, reading}`, `:error` when it holds none. A reminder with no time is a note."
  @spec parse(String.t()) :: {:ok, reading()} | :error
  def parse(out) do
    with [json] <- Regex.run(~r/\{.*\}/s, out),
         {:ok, %{"kind" => kind, "text" => text} = map} when kind in ["reminder", "note"] and is_binary(text) <-
           JSON.decode(json),
         text when text != "" <- String.trim(text) do
      {:ok, reading(kind, text, at(map["at"]), map["amends"] == true)}
    else
      _ -> :error
    end
  end

  @doc "A reading, or a filed jot, as the helper says it back."
  @spec say(%{kind: String.t(), text: String.t(), due_at: DateTime.t() | nil}) :: String.t()
  def say(%{kind: "reminder", text: text, due_at: %DateTime{} = due}),
    do: "I'll remind you #{Calendar.strftime(local(due), "%a %-d %b %H:%M")}: #{text}"

  def say(%{kind: "note", text: text}), do: "noted: #{text}"

  defp reading("reminder", text, %DateTime{} = due, amends),
    do: %{kind: "reminder", text: text, due_at: due, amends: amends}

  defp reading(_kind, text, _at, amends), do: %{kind: "note", text: text, due_at: nil, amends: amends}

  defp at(text) when is_binary(text) do
    case NaiveDateTime.from_iso8601(if String.length(text) == 16, do: text <> ":00", else: text) do
      {:ok, local} -> utc(local)
      _ -> nil
    end
  end

  defp at(_none), do: nil

  # an hour that happens twice (clocks back) is its first; one that never happens is the hour after
  defp utc(local) do
    case :calendar.local_time_to_universal_time_dst(NaiveDateTime.to_erl(local)) do
      [utc | _] -> utc |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
      [] -> utc(NaiveDateTime.add(local, 3600))
    end
  end

  defp local(utc) do
    utc
    |> DateTime.to_naive()
    |> NaiveDateTime.to_erl()
    |> :calendar.universal_time_to_local_time()
    |> NaiveDateTime.from_erl!()
  end

  defp prompt(body, previous, now) do
    """
    You file one message a person texted to their own helper so that they do not forget it.
    Where they are it is now #{Calendar.strftime(now, "%A %Y-%m-%d %H:%M")}.

    Answer with one line of JSON and nothing else:
    {"kind": "reminder" or "note", "text": "...", "at": "YYYY-MM-DDTHH:MM" or null, "amends": true or false}

    - "reminder": the message names or implies a time they should be told. "at" is that time, local
      and in the future. A day with no hour is 09:00; "tonight" is 19:00; "later" is in three hours.
    - "note": anything else. "at" is null.
    - "text": what to do or remember, short, in their own words, without the time.
    - "amends": true only when the message plainly corrects the previous one ("no, saturday").
      Then answer the previous one's reading, corrected, in full.
    #{previous(previous)}
    MESSAGE: #{body}
    """
  end

  defp previous(nil), do: ""
  defp previous(jot), do: "\nPREVIOUS MESSAGE: #{jot.body}\nIT WAS FILED AS: #{say(jot)}\n"
end
