defmodule Server.Home.Reader do
  @moduledoc """
  What a jot means: one small model call reads a message the operator texted the home's inbox and
  answers a reading, `%{kind, text, due_at, every, ids, amends}`. `kind` is `"reminder"` (a time to
  be told, `due_at` in UTC, `every` when it repeats), `"todo"`, `"note"`, `"project"` (an outcome of
  several steps: `steps`, up to five in order) or `"waiting"` (`who` owes `text`), each a thing to
  keep; or what the operator wants of the helper: `"done"` (the open things numbered `ids` are
  done), `"delete"` (the open things numbered `ids` are not wanted at all), `"list"` (what is open),
  `"now"` (what to do now, in `minutes` when they say), `"someday"`
  (what is put off) or `"answer"` (`text` answers their question from their notes and open things).
  `amends` says the message corrects the jot before it, and the reading is then that jot's, corrected.
  A reading may also carry `mins` (a to-do's size: 2, 10, 30 or 60), `project` (the project a to-do is
  the next step of), `assumed` (what the model filled in that was not said), `ask` (the one question
  it needs answered, which the next message amends the jot with) and `revive` (put-off things the
  message mentions, which come back); absent when the model gave none.
  The model is shown what it needs for that: the jot before, the open things, the newest notes, the
  open projects and what is put off. Times are read and said in the machine's own zone. The model is
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

  @type context :: %{
          required(:previous) => Server.Jot.t() | nil,
          required(:open) => [Server.Jot.t()],
          required(:notes) => [String.t()],
          optional(:projects) => [Server.Jot.t()],
          optional(:someday) => [Server.Jot.t()]
        }

  @kept ["reminder", "todo", "note", "project", "waiting"]
  @asked ["done", "delete", "list", "answer", "now", "someday"]
  @bare ["done", "delete", "list", "now", "someday"]
  @sizes [2, 10, 30, 60]
  @steps 5

  @doc """
  Read `body` beside `context`: the jot filed before it, the open reminders and to-dos, the newest
  notes, the open projects and what is put off. `{:ok, reading}`, `:error` when no reading came back.
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
  time is a to-do, a project with no steps is a to-do and a waiting-on with no one named is a to-do;
  a thing to keep, or an answer, with no text is no reading.
  """
  @spec parse(String.t()) :: {:ok, reading()} | :error
  def parse(out) do
    with [json] <- Regex.run(~r/\{.*\}/s, out),
         {:ok, %{"kind" => kind} = map} when kind in @kept or kind in @asked <- JSON.decode(json),
         {:ok, text} <- text(kind, map["text"]) do
      {:ok, kind |> reading(text, at(map["at"]), map) |> extras(map)}
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

  def say(%{kind: "reminder", text: text}), do: "to do: #{text}"
  def say(%{kind: "todo", text: text}), do: "to do: #{text}"
  def say(%{kind: "note", text: text}), do: "noted: #{text}"

  def say(%{kind: "project", text: text} = reading) do
    case Map.get(reading, :steps, []) do
      [] -> "project: #{text}"
      [first | []] -> "project: #{text}\nfirst step: #{first}"
      [first | rest] -> "project: #{text}\nfirst step: #{first}\nthen: #{Enum.join(rest, ", ")}"
    end
  end

  def say(%{kind: "waiting", text: text} = reading), do: "waiting on #{who(reading)} for #{text}. I'll ask in 3 days."

  @doc "A fresh reading as the helper says it back: `say/1`, then what it assumed and the one question it has."
  @spec reply(map()) :: String.t()
  def reply(reading) do
    [say(reading), assumed(reading), Map.get(reading, :ask)] |> Enum.reject(&is_nil/1) |> Enum.join("\n")
  end

  defp assumed(%{assumed: assumed}), do: "I took it that #{assumed}."
  defp assumed(_reading), do: nil

  defp who(%{who: who}), do: who
  defp who(%{waiting_on: who}), do: who

  defp reading("project", text, _at, map) do
    case steps(map["steps"]) do
      [] ->
        reading("todo", text, nil, map)

      steps ->
        %{kind: "project", text: text, due_at: nil, every: nil, ids: [], amends: map["amends"] == true, steps: steps}
    end
  end

  defp reading("waiting", text, _at, map) do
    case string(map["who"]) do
      nil -> reading("todo", text, nil, map)
      who -> %{kind: "waiting", text: text, due_at: nil, every: nil, ids: [], amends: map["amends"] == true, who: who}
    end
  end

  defp reading("reminder", text, %DateTime{} = due, map) do
    every = if map["every"] in ["day", "week", "month"], do: map["every"]
    %{kind: "reminder", text: text, due_at: due, every: every, ids: [], amends: map["amends"] == true}
  end

  defp reading("reminder", text, _no_time, map), do: reading("todo", text, nil, map)

  defp reading(kind, text, _at, map),
    do: %{kind: kind, text: text, due_at: nil, every: nil, ids: ids(map["ids"]), amends: map["amends"] == true}

  defp steps(steps) when is_list(steps), do: Enum.take(for(step <- steps, step = string(step), do: step), @steps)

  defp steps(_none), do: []

  defp string(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      text -> text
    end
  end

  defp string(_none), do: nil

  defp extras(%{kind: kind} = reading, map) do
    optional = [
      mins: if(kind == "todo" and map["mins"] in @sizes, do: map["mins"]),
      project: if(kind == "todo" and is_integer(map["project"]), do: map["project"]),
      assumed: string(map["assumed"]),
      ask: if(kind != "project", do: question(map["ask"])),
      revive: ids(map["revive"]),
      minutes: if(kind == "now" and is_integer(map["minutes"]) and map["minutes"] > 0, do: map["minutes"])
    ]

    Enum.reduce(optional, reading, fn
      {_key, nil}, reading -> reading
      {_key, []}, reading -> reading
      {key, value}, reading -> Map.put(reading, key, value)
    end)
  end

  defp question(text) do
    with text when is_binary(text) <- string(text),
         [question | _] <- Regex.run(~r/^[^?]*\??/, text) do
      question
    else
      _ -> nil
    end
  end

  defp ids(ids), do: for(id <- List.wrap(ids), is_integer(id), do: id)

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
    {"kind": "...", "text": "...", "at": "YYYY-MM-DDTHH:MM" or null, "every": "day" or "week" or "month" or null, "ids": [], "amends": true or false, "steps": [], "who": null, "mins": null, "minutes": null, "project": null, "assumed": null, "ask": null, "revive": []}

    "kind" is one of:
    - "reminder": a thing to keep that names or implies a time they should be told. "at" is that
      time, local and in the future. A day with no hour is 09:00; "tonight" is 19:00; "later" is in
      three hours. When it repeats ("every thursday"), "every" says how and "at" is the first time.
    - "todo": a thing to do, with no time. "mins" is its rough size in minutes: 2, 10, 30 or 60.
    - "project": an outcome that takes more than one step ("plan mom's birthday", "sort out the car
      insurance"), or a thing so vague it needs breaking down. "text" names the outcome. "steps" is
      up to five concrete steps in order, each short and starting with a verb, the first one something
      they could start today.
    - "waiting": they are waiting on someone for something ("waiting on Sam for the photos"). "who"
      is the person, "text" is what for.
    - "note": a thing to remember, and anything else worth keeping.
    - "done": they say one or more of the OPEN things are done or no longer needed. "ids" are the
      numbers of those things.
    - "delete": they want one or more of the OPEN things or PROJECTS gone for good ("delete the milk",
      "never mind the dentist", "forget the bins"). "ids" are the numbers of those things.
    - "list": they ask what is open, due, or on their list.
    - "now": they ask what to do now ("what now", "what should I do", "I have ten minutes").
      "minutes" is the time they say they have, else null.
    - "someday": they ask what is on someday, or what they have put off.
    - "answer": they ask a question. "text" is the answer, short, from the NOTES and the OPEN
      things alone; when those do not hold it, "text" is only "I have nothing on that."
    For a thing to keep, "text" is what to do or remember, short, in their own words, without the time.
    "amends" is true only when the message plainly corrects the PREVIOUS MESSAGE ("no, saturday").
    Then answer that one's reading, corrected, in full.
    Fill in what you can from the NOTES and the OPEN things: a date a note gives, a person's full
    name, what "it" or "that" points to. When you filled in something they did not say, put it in
    "assumed" in a few words ("Sam is Sam Lee"), else null.
    When ONE fact is truly needed and cannot be known from what you have (which day?), still file
    the thing with your best reading, and put that one short question in "ask". Never more than one
    question, and never refuse to file. Their next message answers it: "amends" is then true.
    PROJECTS are the open projects. When one is marked as waiting for its next step and the message
    is that step, answer "todo" with "project" set to that project's number; otherwise "project" is null.
    SOMEDAY are things they put off. Put a number in "revive" only for the thing the message is itself
    about ("do the fence tomorrow" is about the fence: "kind" is the fence's own, with the new time,
    and "revive" holds its number). A message that only passes by one of them is not a reason to revive it.

    OPEN:
    #{open(context.open)}
    NOTES:
    #{notes(context.notes)}
    PROJECTS:
    #{projects(Map.get(context, :projects, []))}
    SOMEDAY:
    #{open(Map.get(context, :someday, []))}
    #{previous(context.previous)}
    MESSAGE: #{body}
    """
  end

  defp open([]), do: "(nothing)"
  defp open(jots), do: Enum.map_join(jots, "\n", &"#{&1.id}: #{say(&1)}#{step(&1)}")

  defp step(%{project_id: nil}), do: ""
  defp step(%{project_id: id}), do: " (a step of project #{id})"

  defp projects([]), do: "(none)"

  defp projects(jots),
    do: Enum.map_join(jots, "\n", &"#{&1.id}: #{&1.text}#{if &1.ask == "next", do: " (waiting for its next step)"}")

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

  defp text(kind, _none) when kind in @bare, do: {:ok, ""}
  defp text(_kind, _none), do: :error
end
