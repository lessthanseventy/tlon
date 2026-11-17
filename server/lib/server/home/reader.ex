defmodule Server.Home.Reader do
  @moduledoc """
  What a jot means: one small model call reads a message the operator texted the home's inbox and
  answers a reading, `%{kind, text, due_at, every, ids, amends}`. `kind` is `"reminder"` (a time to
  be told, `due_at` in UTC, `every` when it repeats), `"todo"` or `"note"`, each a thing to keep; or
  what the operator wants of the helper: `"done"` (the open things numbered `ids` are done), `"list"`
  (what is open) or `"answer"` (`text` answers their question from their notes and open things).
  `amends` says the message corrects the jot before it, and the reading is then that jot's, corrected.
  The model is shown what it needs for that: the jot before, the open things, the newest notes. Times are read and said in the machine's own zone. The model is
  Haiku on the operator's Claude login, with no tools (`:home_reader_cmd` and `:home_reader_model`
  name another): what a person texts themselves stays with the provider they already use.
  """

  require Logger

  @type reading :: %{
          kind: String.t(),
          text: String.t(),
          due_at: DateTime.t() | nil,
          every: String.t() | nil,
          ids: [integer()],
          amends: boolean()
        }

  @type context :: %{previous: Server.Jot.t() | nil, open: [Server.Jot.t()], notes: [String.t()]}

  @kept ["reminder", "todo", "note"]
  @asked ["done", "list", "answer"]

  @doc """
  Read `body` beside `context`: the jot filed before it, the open reminders and to-dos, the newest
  notes. `{:ok, reading}`, `:error` when no reading came back.
  """
  @spec read(String.t(), context()) :: {:ok, reading()} | :error
  def read(body, context) do
    now = NaiveDateTime.from_erl!(:calendar.local_time())
    opts = [timeout_s: 60, tools: "", settings: "user"]

    case Server.ModelCli.prompt(
           prompt(body, context, now),
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

  @doc """
  The reading in a model's reply: `{:ok, reading}`, `:error` when it holds none. A reminder with no
  time is a to-do; a thing to keep, or an answer, with no text is no reading.
  """
  @spec parse(String.t()) :: {:ok, reading()} | :error
  def parse(out) do
    with [json] <- Regex.run(~r/\{.*\}/s, out),
         {:ok, %{"kind" => kind} = map} when kind in @kept or kind in @asked <- JSON.decode(json),
         {:ok, text} <- text(kind, map["text"]) do
      {:ok, reading(kind, text, at(map["at"]), map)}
    else
      _ -> :error
    end
  end

  @doc "A reading, or a filed jot, as the helper says it back."
  @spec say(%{kind: String.t(), text: String.t(), due_at: DateTime.t() | nil}) :: String.t()
  def say(%{kind: "reminder", text: text, due_at: %DateTime{} = due} = reading) do
    case Map.get(reading, :every) do
      nil -> "I'll remind you #{Server.Home.Clock.say(due)}: #{text}"
      every -> "I'll remind you #{Server.Home.Clock.say(due)}, then every #{every}: #{text}"
    end
  end

  def say(%{kind: "todo", text: text}), do: "to do: #{text}"
  def say(%{kind: "note", text: text}), do: "noted: #{text}"

  defp reading("reminder", text, %DateTime{} = due, map) do
    every = if map["every"] in ["day", "week", "month"], do: map["every"]
    %{kind: "reminder", text: text, due_at: due, every: every, ids: [], amends: map["amends"] == true}
  end

  defp reading("reminder", text, _no_time, map), do: reading("todo", text, nil, map)

  defp reading(kind, text, _at, map) do
    ids = for id <- List.wrap(map["ids"]), is_integer(id), do: id
    %{kind: kind, text: text, due_at: nil, every: nil, ids: ids, amends: map["amends"] == true}
  end

  defp at(text) when is_binary(text) do
    case NaiveDateTime.from_iso8601(if String.length(text) == 16, do: text <> ":00", else: text) do
      {:ok, local} -> Server.Home.Clock.utc(local)
      _ -> nil
    end
  end

  defp at(_none), do: nil

  defp prompt(body, context, now) do
    """
    You are the helper a person texts so that nothing is forgotten. Read one message from them.
    Where they are it is now #{Calendar.strftime(now, "%A %Y-%m-%d %H:%M")}.

    Answer with one line of JSON and nothing else:
    {"kind": "...", "text": "...", "at": "YYYY-MM-DDTHH:MM" or null, "every": "day" or "week" or "month" or null, "ids": [], "amends": true or false}

    "kind" is one of:
    - "reminder": a thing to keep that names or implies a time they should be told. "at" is that
      time, local and in the future. A day with no hour is 09:00; "tonight" is 19:00; "later" is in
      three hours. When it repeats ("every thursday"), "every" says how and "at" is the first time.
    - "todo": a thing to do, with no time.
    - "note": a thing to remember, and anything else worth keeping.
    - "done": they say one or more of the OPEN things are done or no longer needed. "ids" are the
      numbers of those things.
    - "list": they ask what is open, due, or on their list.
    - "answer": they ask a question. "text" is the answer, short, from the NOTES and the OPEN
      things alone; when those do not hold it, "text" is only "I have nothing on that."
    For a thing to keep, "text" is what to do or remember, short, in their own words, without the time.
    "amends" is true only when the message plainly corrects the PREVIOUS MESSAGE ("no, saturday").
    Then answer that one's reading, corrected, in full.

    OPEN:
    #{open(context.open)}
    NOTES:
    #{notes(context.notes)}
    #{previous(context.previous)}
    MESSAGE: #{body}
    """
  end

  defp open([]), do: "(nothing)"
  defp open(jots), do: Enum.map_join(jots, "\n", &"#{&1.id}: #{say(&1)}")

  defp notes([]), do: "(none)"
  defp notes(notes), do: Enum.map_join(notes, "\n", &"- #{&1}")

  defp previous(nil), do: ""
  defp previous(jot), do: "\nPREVIOUS MESSAGE: #{jot.body}\nIT WAS FILED AS: #{say(jot)}\n"

  defp text(kind, text) when is_binary(text) do
    case String.trim(text) do
      "" when kind in @kept or kind == "answer" -> :error
      text -> {:ok, text}
    end
  end

  defp text(kind, _none) when kind in ["done", "list"], do: {:ok, ""}
  defp text(_kind, _none), do: :error
end
