defmodule Server.Home.Organize do
  @moduledoc """
  The home's upkeep, which the operator never does: the system files, follows and prunes.

    * **Projects.** A project (`kind: "project"`) always has one open next step or a question about
      it. Finishing a step (`advance/2`) proposes the next: one the reader planned, else one the
      model writes (`Server.Home.Helper.next_step/3`), under Add it / Project's finished; a typed
      reply is the step instead.
    * **Waiting on.** Three days after it was said, a waiting-on is asked about (`waiting/4`): Got it,
      Chased (asked again in three days) or Tomorrow.
    * **The weekly review** (`weekly/7`): up to five open things untouched for 14 days, each with Keep,
      Later or Drop; anything untouched for 28 days is moved to someday on its own and said in a line.
    * **Shrinking** (`shrink/2`): a to-do that has sat a week is offered a two-minute start, once,
      with the daily list. Add that makes it a project whose next step the start is.

  Each question is put on its jot (`Server.Jot.ask/4`), so the desktop raises it (`Server.Home.asked/0`)
  whether or not a messenger said it, and is answered by `answer/5` from either. Nothing unasked
  is said between 22:00 and 08:00 (`Server.Home.Clock.awake?/1`).
  """

  alias Server.Home
  alias Server.Home.Clock
  alias Server.Home.Helper
  alias Server.Home.Reader
  alias Server.Jot

  @type reply :: {String.t(), keyword()}
  @type say :: (String.t(), String.t(), keyword() -> term())

  @wait_days 3
  @stale_days 14
  @drift_days 28
  @sat_days 7
  @review_max 5

  @doc """
  File a fresh `reading` of `jot` as the operator's, at `now`: a project is filed with its first
  step, a waiting-on is set to be asked about in three days, a to-do that answers a project's
  question is that project's next step, and any put-off thing the message mentions is brought back.
  The reply the helper says.
  """
  @spec file(Jot.t(), map(), DateTime.t()) :: String.t()
  def file(%Jot{via: via} = jot, reading, now) do
    reply = place(jot, reading, now)

    back =
      for id <- Map.get(reading, :revive, []),
          someday <- [Enum.find(Jot.somedays(via), &(&1.id == id))],
          do: revive(someday)

    Enum.join([reply | Enum.map(back, &"back on the list: #{&1.text}")], "\n")
  end

  defp place(jot, %{kind: "project", steps: [first | _]} = reading, now) do
    jot |> Jot.file(reading) |> Jot.step(first, now)
    Reader.reply(reading)
  end

  defp place(jot, %{kind: "waiting"} = reading, now) do
    Jot.file(jot, %{reading | due_at: now |> DateTime.add(@wait_days, :day) |> DateTime.truncate(:second)})
    Reader.reply(reading)
  end

  defp place(jot, %{kind: "todo", project: id} = reading, _now) do
    case Jot.project(jot.via, id) do
      %Jot{ask: "next", text: name} = project ->
        Jot.file(jot, reading)
        Jot.touch(project)
        "next step of #{name}: #{reading.text}"

      _ ->
        place(jot, Map.delete(reading, :project), nil)
    end
  end

  defp place(jot, reading, _now) do
    Jot.file(jot, reading)
    Reader.reply(reading)
  end

  defp revive(jot), do: Jot.file(jot, %{kind: jot.kind, text: jot.text, due_at: jot.due_at, every: jot.every})

  @doc """
  What follows a step of a project being done or put away: the next step proposed under its
  buttons, `nil` when it is no project's step or the project still has one open or is waiting on an
  answer already.
  """
  @spec advance(Jot.t(), DateTime.t()) :: reply() | nil
  def advance(%Jot{project_id: nil}, _now), do: nil

  def advance(%Jot{via: via, project_id: id}, now) do
    with %Jot{ask: nil} = project <- Jot.project(via, id), [] <- Jot.steps(id) do
      {proposed, plan} = next(project)
      project |> Jot.plan(plan) |> Jot.ask("next", proposed, now) |> prompt_reply()
    else
      _ -> nil
    end
  end

  defp next(%Jot{plan: [step | rest]}), do: {step, rest}

  defp next(%Jot{via: via, id: id} = project) do
    case Helper.next_step(project, Jot.finished(id), Jot.notes(via, 20)) do
      {:ok, step} -> {step, []}
      :error -> {nil, []}
    end
  end

  @doc """
  The question `jot` waits on as the operator is asked it: `%{text, choices, typed}`. `choices` are
  `{label, choice}`, answered by `answer/5`; `typed` is the choice a typed reply makes, or nil.
  """
  @spec prompt(Jot.t()) :: %{text: String.t(), choices: [{String.t(), String.t()}], typed: String.t() | nil}
  def prompt(%Jot{ask: "next", text: name, proposed: nil}),
    do: %{text: "What's the next step for #{name}?", choices: [{"Project's finished", "finish"}], typed: "step"}

  def prompt(%Jot{ask: "next", text: name, proposed: step}),
    do: %{
      text: "Next for #{name}: #{step}?",
      choices: [{"Add it", "add"}, {"Project's finished", "finish"}],
      typed: "step"
    }

  def prompt(%Jot{ask: "review", text: text}),
    do: %{
      text: "Still want this? #{text}",
      choices: [{"Keep", "keep"}, {"Later", "later"}, {"Drop", "drop"}],
      typed: nil
    }

  def prompt(%Jot{ask: "waiting", text: text, waiting_on: who}),
    do: %{
      text: "Still waiting on #{who} for #{text}?",
      choices: [{"Got it", "got"}, {"Chased", "chased"}, {"Tomorrow", "tomorrow"}],
      typed: nil
    }

  def prompt(%Jot{ask: "shrink", text: text, proposed: start} = jot),
    do: %{
      text: "'#{text}' has sat #{sat(jot)}. A two-minute start: #{start}?",
      choices: [{"Add that", "add"}, {"No thanks", "no"}],
      typed: nil
    }

  defp sat(%Jot{received_at: at, asked_at: asked}) do
    case div(DateTime.diff(asked || DateTime.add(at, @sat_days, :day), at), 86_400 * 7) do
      weeks when weeks <= 1 -> "a week"
      weeks -> "#{weeks} weeks"
    end
  end

  defp prompt_reply(%Jot{id: id} = jot) do
    %{text: text, choices: choices} = prompt(jot)
    {text, choices: [for({label, choice} <- choices, do: {label, "a:#{id}:#{choice}"})]}
  end

  @doc """
  Carry out the operator's `choice` (a button's, or `"nottoday"` for any open thing, or `"step"` with
  the `text` they typed) for `id` from `via`: `{:ok, reply}`, `:error` when the thing has no such
  question or is not open.
  """
  @spec answer(String.t(), integer(), String.t(), String.t() | nil, DateTime.t()) :: {:ok, reply()} | :error
  def answer(via, id, "nottoday", _text, now) do
    case Jot.open(via, id) do
      nil ->
        :error

      jot ->
        tomorrow = now |> Clock.local() |> NaiveDateTime.to_date() |> Date.add(1) |> NaiveDateTime.new!(~T[00:00:00])
        Jot.hide(jot, Clock.utc(tomorrow))
        {:ok, {"not today: #{jot.text}. It'll wait until tomorrow.", []}}
    end
  end

  def answer(via, id, choice, text, now) do
    with %Jot{ask: ask} = jot <- Jot.asked(via, id),
         {:ok, reply} <- resolve(ask, choice, jot, text, now) do
      {:ok, reply}
    else
      _ -> :error
    end
  end

  defp resolve("next", "add", %Jot{proposed: step} = project, _text, now) when is_binary(step) do
    Jot.step(project, step, now)
    Jot.touch(project)
    {:ok, {"added: #{step}", []}}
  end

  defp resolve("next", "step", project, text, now) when is_binary(text) do
    case String.trim(text) do
      "" ->
        :error

      step ->
        Jot.step(project, step, now)
        Jot.touch(project)
        {:ok, {"added: #{step}", []}}
    end
  end

  defp resolve("next", "finish", project, _text, now) do
    Jot.done(project, now)
    {:ok, {"done: #{project.text}. That's the project finished.", []}}
  end

  defp resolve("review", "keep", jot, _text, _now) do
    Jot.touch(jot)
    {:ok, {"kept: #{jot.text}", []}}
  end

  defp resolve("review", "later", jot, _text, now), do: {:ok, parted("moved to someday: ", Jot.someday(jot, now), now)}
  defp resolve("review", "drop", jot, _text, now), do: {:ok, parted("dropped: ", Jot.drop(jot, now), now)}

  defp resolve("waiting", "got", jot, _text, now) do
    Jot.done(jot, now)
    {:ok, {"got it: #{jot.text} from #{jot.waiting_on}", []}}
  end

  defp resolve("waiting", "chased", jot, _text, now) do
    Jot.ask_again(jot, DateTime.add(now, @wait_days, :day))
    {:ok, {"I'll ask again in #{@wait_days} days.", []}}
  end

  defp resolve("waiting", "tomorrow", jot, _text, now) do
    Jot.ask_again(jot, morning(now))
    {:ok, {"I'll ask again tomorrow.", []}}
  end

  defp resolve("shrink", "add", %Jot{proposed: start} = jot, _text, now) when is_binary(start) do
    Jot.shrink(jot, start, now)
    {:ok, {"#{jot.text} is a project now. First step: #{start}", []}}
  end

  defp resolve("shrink", "no", jot, _text, _now) do
    Jot.touch(jot)
    {:ok, {"ok, leaving it.", []}}
  end

  defp resolve(_ask, _choice, _jot, _text, _now), do: :error

  defp parted(said, %Jot{text: text} = jot, now) do
    case advance(jot, now) do
      nil -> {said <> text, []}
      {more, opts} -> {said <> text <> "\n" <> more, opts}
    end
  end

  defp morning(now) do
    now |> Clock.local() |> NaiveDateTime.to_date() |> Date.add(1) |> NaiveDateTime.new!(~T[09:00:00]) |> Clock.utc()
  end

  @doc """
  Ask about each waiting-on from `via` whose three days are up at `now`, in `chat` through `say`
  (`""` for the desktop alone), in waking hours only.
  """
  @spec waiting(String.t(), String.t(), say() | nil, DateTime.t()) :: :ok
  def waiting(via, chat, say, now) do
    if Clock.awake?(now) do
      for jot <- Jot.waiting(via),
          is_nil(jot.ask),
          DateTime.compare(jot.due_at, now) != :gt,
          do: put(jot, "waiting", nil, chat, say, now)
    end

    :ok
  end

  @doc """
  The weekly review: once `now` is past `at` (`"17:30"`, local) on the weekday `on` (`"sun"`; `""` is
  never) and the day has not been reviewed, what has gone stale is put to the operator in `chat`.
  `reviewed` is the day it was last done, `:boot` when the inbox has just started; the day it now
  stands at is answered.
  """
  @spec weekly(String.t(), String.t(), say() | nil, DateTime.t(), String.t(), String.t(), Date.t() | :boot) :: Date.t()
  def weekly(via, chat, say, now, on, at, reviewed) do
    local = Clock.local(now)
    today = NaiveDateTime.to_date(local)
    due? = on != "" and weekday(today) == on and past?(NaiveDateTime.to_time(local), Time.from_iso8601(at <> ":00"))

    cond do
      reviewed == :boot and due? -> today
      reviewed == :boot -> Date.add(today, -1)
      not due? or reviewed == today -> reviewed
      true -> review(via, chat, say, now)
    end
  end

  defp weekday(date), do: date |> Calendar.strftime("%a") |> String.downcase()

  defp past?(time, {:ok, at}), do: Time.compare(time, at) != :lt
  defp past?(_time, _never), do: false

  defp review(via, chat, say, now) do
    {_coming, open} = Home.board(via, now)
    {drift, rest} = Enum.split_with(open, &stale?(&1, now, @drift_days))
    asks = Enum.filter(drift, &(&1.project_id != nil))

    Enum.each(drift, &Jot.someday(&1, now))
    if drift != [], do: tell(chat, say, "moved to someday: " <> Enum.map_join(drift, ", ", & &1.text), [])
    for jot <- asks, {text, opts} <- List.wrap(advance(jot, now)), do: tell(chat, say, text, opts)

    for jot <-
          rest
          |> Enum.filter(&(is_nil(&1.ask) and stale?(&1, now, @stale_days)))
          |> Enum.sort_by(&{DateTime.to_unix(Jot.touched(&1)), &1.id})
          |> Enum.take(@review_max) do
      put(jot, "review", nil, chat, say, now)
    end

    now |> Clock.local() |> NaiveDateTime.to_date()
  end

  defp stale?(jot, now, days), do: DateTime.diff(now, Jot.touched(jot)) >= days * 86_400

  defp tell("", _say, _text, _opts), do: :ok
  defp tell(chat, say, text, opts), do: say.(chat, text, opts)

  # the question is said before it is kept, so one that did not go out is put at the next try
  defp put(jot, ask, proposed, chat, say, now) do
    asked = %{jot | ask: ask, proposed: proposed, asked_at: DateTime.truncate(now, :second)}
    {text, opts} = prompt_reply(asked)

    if chat == "" or say.(chat, text, opts) == :ok do
      Jot.ask(jot, ask, proposed, now)
    end
  end

  @doc """
  A smaller start offered for the oldest to-do from `via` that has sat a week and was never offered
  one: its question, put on it, as a reply for the daily list to carry. `nil` when none is, or the
  model gave no start.
  """
  @spec shrink(String.t(), DateTime.t()) :: reply() | nil
  def shrink(via, now) do
    {_coming, open} = Home.board(via, now)

    sat =
      for %Jot{kind: "todo", project_id: nil, ask: nil, shrunk_at: nil} = jot <- open,
          DateTime.diff(now, jot.received_at) >= @sat_days * 86_400,
          do: jot

    with [jot | _] <- Enum.sort_by(sat, &{DateTime.to_unix(&1.received_at), &1.id}),
         {:ok, start} <- Helper.start(jot, Jot.notes(via, 20)) do
      jot |> Jot.shrunk(now) |> Jot.ask("shrink", start, now) |> prompt_reply()
    else
      _ -> nil
    end
  end
end
