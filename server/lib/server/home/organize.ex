defmodule Server.Home.Organize do
  @moduledoc """
  The home's upkeep, which the operator never does: the system files, follows and prunes.

    * **Projects.** A project (`kind: "project"`) always has one open next step or a question about
      it. Finishing a step (`advance/2`) proposes the next: one the reader planned, else one the
      model writes (`Server.Home.Helper.next_step/3`, off the caller, in a task), under Add it / Project's finished; a typed
      reply is the step instead.
    * **Waiting on.** Three days after it was said, a waiting-on is asked about (`waiting/4`): Got it,
      Chased (asked again in three days) or Tomorrow.
    * **The weekly review** (`weekly/7`): up to five open things untouched for 14 days, each with Keep,
      Later or Drop; anything untouched for 28 days is moved to someday on its own and said in a line.
      A reminder that repeats is a routine: never reviewed, never moved. One whose time went by asleep
      is said at the first waking moment.
    * **Deleting** (`delete/2`): the operator's no to a thing, which is dropped and never told again.
    * **Shrinking** (`shrink/2`): a to-do that has sat a week is offered a two-minute start, once, as
      its own message once the model has written it after the daily list (`offer_shrink/6`). Add that
      makes it a project whose next step the start is.

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
  @review_at "17:30"

  @doc """
  File a fresh `reading` of `jot` as the operator's, at `now`: a project is filed with its first
  step, a waiting-on is set to be asked about in three days, a to-do that answers a project's
  question is that project's next step.

  A fresh jot (no kind yet) whose to-do or reminder reading revives a put-off thing is about that
  thing: the thing is the one it is, brought back as the reading has it (its text, its time when the
  reading has one), and the jot is kept as the raw capture of an amend. A reading of any other kind
  files as it is, and what it revives comes back beside it. The reply the helper says.
  """
  @spec file(Jot.t(), map(), DateTime.t()) :: String.t()
  def file(%Jot{via: via, kind: kind} = jot, reading, now) do
    back = if is_nil(kind), do: revivable(via, reading), else: []

    case {back, reading} do
      {[thing | rest], %{kind: kind}} when kind in ["todo", "reminder"] ->
        Jot.file(jot, %{kind: "amend", text: nil, due_at: nil}, now)
        merge(thing, reading, now)
        Enum.join([Reader.reply(reading) | Enum.map(rest, &back(&1, now))], "\n")

      _ ->
        reply = jot |> retire(reading, now) |> place(reading, now)
        Enum.join([reply | Enum.map(back, &back(&1, now))], "\n")
    end
  end

  defp place(jot, %{kind: "project", steps: [first | _]} = reading, now) do
    project = Jot.file(jot, reading, now)
    if Jot.steps(project.id) == [], do: Jot.step(project, first, now)
    Reader.reply(reading)
  end

  defp place(jot, %{kind: "waiting"} = reading, now) do
    Jot.file(jot, %{reading | due_at: now |> DateTime.add(@wait_days, :day) |> DateTime.truncate(:second)}, now)
    Reader.reply(reading)
  end

  defp place(jot, %{kind: "todo", project: id} = reading, now) do
    case Jot.project(jot.via, id) do
      %Jot{ask: "next", text: name} = project ->
        Jot.file(jot, reading, now)
        Jot.touch(project, now)
        "next step of #{name}: #{reading.text}"

      _ ->
        place(jot, Map.delete(reading, :project), now)
    end
  end

  defp place(jot, reading, now) do
    Jot.file(jot, reading, now)
    Reader.reply(reading)
  end

  @doc """
  What follows a step of a project being done or put away: the next step proposed under its
  buttons when the reader had planned one, `nil` when it is no project's step or the project still
  has one open or is waiting on an answer already. With no plan left the next step takes a model
  call, which is made off the caller (a task under `Server.TaskSupervisor`): this answers `nil`
  at once, and the question is put on the project when the model has answered and said in the chat
  (`Server.Home.Inbox.asked_now/1`); the desktop raises it from the row.
  """
  @spec advance(Jot.t(), DateTime.t()) :: reply() | nil
  def advance(%Jot{project_id: nil}, _now), do: nil

  def advance(%Jot{via: via, project_id: id}, now) do
    with %Jot{ask: nil} = project <- Jot.project(via, id), [] <- Jot.steps(id) do
      case project.plan do
        [step | rest] -> project |> Jot.plan(rest) |> Jot.ask("next", step, now) |> prompt_reply()
        [] -> start_next(project, now)
      end
    else
      _ -> nil
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

  @doc "The question on `jot` as a reply: its text, and its choices as buttons answered through `\"a:<id>:<choice>\"`."
  @spec prompt_reply(Jot.t()) :: reply()
  def prompt_reply(%Jot{id: id} = jot) do
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
        Jot.hide(jot, Clock.utc(tomorrow), now)
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
    Jot.touch(project, now)
    {:ok, {"added: #{step}", []}}
  end

  defp resolve("next", "step", project, text, now) when is_binary(text) do
    case String.trim(text) do
      "" ->
        :error

      step ->
        Jot.step(project, step, now)
        Jot.touch(project, now)
        {:ok, {"added: #{step}", []}}
    end
  end

  defp resolve("next", "finish", project, _text, now) do
    Jot.done(project, now)
    {:ok, {"done: #{project.text}. That's the project finished.", []}}
  end

  defp resolve("review", "keep", jot, _text, now) do
    Jot.touch(jot, now)
    {:ok, {"kept: #{jot.text}", []}}
  end

  defp resolve("review", "later", jot, _text, now), do: {:ok, parted("moved to someday: ", Jot.someday(jot, now), now)}
  defp resolve("review", "drop", jot, _text, now), do: {:ok, parted("dropped: ", Jot.drop(jot, now), now)}

  defp resolve("waiting", "got", jot, _text, now) do
    Jot.done(jot, now)
    {:ok, {"got it: #{jot.text} from #{jot.waiting_on}", []}}
  end

  defp resolve("waiting", "chased", jot, _text, now) do
    Jot.ask_again(jot, DateTime.add(now, @wait_days, :day), now)
    {:ok, {"I'll ask again in #{@wait_days} days.", []}}
  end

  defp resolve("waiting", "tomorrow", jot, _text, now) do
    Jot.ask_again(jot, morning(now), now)
    {:ok, {"I'll ask again tomorrow.", []}}
  end

  defp resolve("shrink", "add", %Jot{proposed: start} = jot, _text, now) when is_binary(start) do
    Jot.shrink(jot, start, now)
    {:ok, {"#{jot.text} is a project now. First step: #{start}", []}}
  end

  defp resolve("shrink", "no", jot, _text, now) do
    Jot.touch(jot, now)
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
      for %Jot{ask: nil, due_at: %DateTime{} = due} = jot <- Jot.waiting(via),
          DateTime.compare(due, now) != :gt,
          do: put(jot, "waiting", nil, chat, say, now)
    end

    :ok
  end

  @doc """
  The weekly review: when the slot of the weekday `on` (`"sun"`; `""` is never) at `at` (`"17:30"`,
  local; `""` is 17:30) has come round and was not done (`Server.Home.Clock.due/4`), what has gone
  stale is put to the operator in `chat`, in waking hours: one missed asleep or with the node down is
  done at the first waking moment after it, whatever the day. `reviewed` is the date of the last
  slot done, `:boot` when none is kept under the present settings, which counts the newest slot as done; the date
  of the slot now done is answered.
  """
  @spec weekly(String.t(), String.t(), say() | nil, DateTime.t(), String.t(), String.t(), Date.t() | :boot) :: Date.t()
  def weekly(_via, _chat, _say, now, on, at, :boot),
    do: Clock.slot(now, review_at(at), on) || now |> Clock.local() |> NaiveDateTime.to_date() |> Date.add(-1)

  def weekly(via, chat, say, now, on, at, %Date{} = reviewed) do
    case Clock.due(reviewed, now, review_at(at), on) do
      {:say, slot} ->
        review(via, chat, say, now)
        slot

      :wait ->
        reviewed
    end
  end

  defp review(via, chat, say, now) do
    {_coming, open} = Home.board(via, now)
    {drift, rest} = open |> Enum.filter(&is_nil(&1.every)) |> Enum.split_with(&stale?(&1, now, @drift_days))
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

    :ok
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
  A smaller start for the oldest to-do from `via` that has sat a week and was never offered or tried.
  The model is asked off the caller, in a task; when it has answered, the offer is put through the
  inbox (`Server.Home.Inbox.shrink_offered/3`), as `offer_shrink/6` does. A to-do the model had no
  start for is marked tried, so the next one has its turn at the next daily list; one the model did
  not answer for is asked again then. Nothing when there is no such to-do or it is quiet hours.
  """
  @spec shrink(String.t(), DateTime.t()) :: :ok
  def shrink(via, now) do
    {_coming, open} = Home.board(via, now)

    sat =
      for %Jot{kind: "todo", project_id: nil, ask: nil, shrunk_at: nil} = jot <- open,
          DateTime.diff(now, jot.received_at) >= @sat_days * 86_400,
          do: jot

    with true <- Clock.awake?(now),
         [jot | _] <- Enum.sort_by(sat, &{DateTime.to_unix(&1.received_at), &1.id}),
         do: Task.Supervisor.start_child(Server.TaskSupervisor, fn -> write_start(jot, now) end)

    :ok
  end

  @doc """
  Offer `start` for the to-do `id` from `via` in `chat` through `say`: said first, and put on the
  to-do only when it went out (`""` for the desktop alone, which raises it from the row). Nothing
  when the to-do is no longer open or has a question already, or it is quiet hours.
  """
  @spec offer_shrink(String.t(), integer(), String.t(), String.t(), say() | nil, DateTime.t()) :: :ok
  def offer_shrink(via, id, start, chat, say, now) do
    with true <- Clock.awake?(now),
         %Jot{kind: "todo", ask: nil, shrunk_at: nil} = jot <- Jot.open(via, id),
         do: put_offer(jot, start, chat, say, now)

    :ok
  end

  defp put_offer(jot, start, chat, say, now) do
    asked = %{jot | ask: "shrink", proposed: start, asked_at: DateTime.truncate(now, :second)}
    {text, opts} = prompt_reply(asked)

    if chat == "" or say.(chat, text, opts) == :ok do
      jot |> Jot.shrunk(now) |> Jot.ask("shrink", start, now)
    end
  end

  # a project made into anything else loses its steps and its plan: nothing is left to follow
  defp retire(%Jot{kind: "project"} = jot, %{kind: kind}, now) when kind != "project", do: unplan(jot, now)
  defp retire(jot, _reading, _now), do: jot

  defp revive(jot, now) do
    due =
      if jot.every && !DateTime.after?(jot.due_at, now), do: Clock.next(jot.due_at, jot.every, now), else: jot.due_at

    reopened(Jot.file(jot, %{kind: jot.kind, text: jot.text, due_at: due, every: jot.every}, now), now)
  end

  @doc """
  Delete the open thing `jot` at `now`: dropped, so not done and never told again (a reminder that
  repeats stops for good). A project takes its open steps and its plan with it; the only open step
  of a project does what putting it away does and proposes the next (`advance/2`). The thing
  dropped, and that follow-up when there is one.
  """
  @spec delete(Jot.t(), DateTime.t()) :: {Jot.t(), reply() | nil}
  def delete(%Jot{kind: "project"} = jot, now) do
    jot |> unplan(now) |> Jot.drop(now) |> then(&{&1, nil})
  end

  def delete(jot, now) do
    gone = Jot.drop(jot, now)
    {gone, advance(gone, now)}
  end

  defp start_next(%Jot{via: via, id: id} = project, now) do
    Task.Supervisor.start_child(Server.TaskSupervisor, fn ->
      proposed =
        case Helper.next_step(project, Jot.finished(id), Jot.notes(via, 20)) do
          {:ok, step} -> step
          :error -> nil
        end

      with %Jot{ask: nil} = project <- Jot.project(via, id),
           [] <- Jot.steps(id),
           true <- Jot.ask_free(project, "next", proposed, now) do
        Server.Home.Inbox.asked_now(id)
      end
    end)

    nil
  end

  defp write_start(%Jot{via: via} = jot, now) do
    case Helper.start(jot, Jot.notes(via, 20)) do
      {:ok, start} -> Server.Home.Inbox.shrink_offered(jot.id, start, now)
      :none -> Jot.shrunk(jot, now)
      :error -> :ok
    end
  end

  defp revivable(via, reading) do
    somedays = Jot.somedays(via)
    for id <- Map.get(reading, :revive, []), thing <- Enum.filter(somedays, &(&1.id == id)), do: thing
  end

  defp back(thing, now) do
    revive(thing, now)
    "back on the list: #{thing.text}"
  end

  defp merge(thing, %{due_at: %DateTime{}} = reading, now), do: reopened(Jot.file(thing, reading, now), now)
  defp merge(thing, %{text: text}, now), do: revive(%{thing | text: text}, now)

  defp unplan(project, now) do
    for step <- Jot.steps(project.id), do: Jot.drop(step, now)
    Jot.plan(project, [])
  end

  # a project that asked for its next step has it back
  defp reopened(%Jot{project_id: id, via: via} = jot, now) when is_integer(id) do
    with %Jot{ask: "next"} = project <- Jot.project(via, id), do: Jot.touch(project, now)
    jot
  end

  defp reopened(jot, _now), do: jot

  defp review_at(""), do: @review_at
  defp review_at(at), do: at
end
