defmodule Server.Home do
  @moduledoc """
  The home, as a surface other than the chat reads it: what the operator's jots have left open, what
  is coming, and the newest notes, what to do now, and the questions the home has put to the
  operator. The jots are the home messenger's (`:home_messenger`).
  """

  alias Server.Jot

  @doc """
  The home at `now`: `open` the to-dos and the reminders whose time has passed, `coming` the
  reminders to come, soonest first, `notes` the newest twenty, `projects` the open projects with their
  `next` step and how many are `done`, `waiting` what others owe the operator, and `done_week` how many
  things were done in the last seven days. A row's `since` is when it was said, its `told_at` when the
  operator was last told a reminder that is due (nil before that), its `project` the project it is a step
  of (nil when none). Things put off to someday or dropped are in none of these.
  """
  @spec status(DateTime.t()) :: %{
          open: [map()],
          coming: [map()],
          notes: [String.t()],
          projects: [map()],
          waiting: [map()],
          done_week: non_neg_integer()
        }
  def status(now) do
    {coming, open} = board(via(), now)
    projects = Jot.projects(via())
    named = Map.new(projects, &{&1.id, &1})

    %{
      open: Enum.map(open, &row(&1, named)),
      coming: Enum.map(coming, &row(&1, named)),
      notes: Jot.notes(via(), 20),
      projects: Enum.map(projects, &project/1),
      waiting: Enum.map(Jot.waiting(via()), &waiting/1),
      done_week: Jot.done_since(via(), DateTime.add(now, -7, :day))
    }
  end

  @doc """
  What to do now at `now`: `%{pick, say}`, `pick` the one open thing (`id`, `text`, `kind`, `due_at`,
  `project`, `why`) or nil when nothing is open, `say` as the helper words it. `skip` are ids to leave
  out, `minutes` the time the operator has, nil when they did not say.
  """
  @spec now([integer()], pos_integer() | nil, DateTime.t()) :: %{pick: map() | nil, say: String.t()}
  def now(skip, minutes, now) do
    projects = Map.new(Jot.projects(via()), &{&1.id, &1})
    names = Map.new(projects, fn {id, project} -> {id, project.text} end)

    case Server.Home.Now.pick(Jot.opens(via()), now, skip: skip, minutes: minutes, projects: names) do
      {:ok, jot, why} ->
        pick = Map.put(row(jot, projects), :why, why)
        %{pick: pick, say: "#{label(jot, projects)} — #{why}"}

      :none ->
        %{pick: nil, say: "Nothing open right now. That's a good place to be."}
    end
  end

  @doc "A thing as the helper lists it: a step of a project under its project's name, anything else as it was said."
  @spec label(Jot.t(), %{integer() => Jot.t()}) :: String.t()
  def label(%Jot{project_id: id, text: text}, projects) do
    case projects do
      %{^id => project} -> "#{project.text}: #{text}"
      _ -> text
    end
  end

  @doc "The open projects from `via` by id, for `label/2`."
  @spec projects(String.t()) :: %{integer() => Jot.t()}
  def projects(via), do: Map.new(Jot.projects(via), &{&1.id, &1})

  @doc """
  The operator's `choice` for the question or the open thing `id` (`Server.Home.Organize.answer/5`;
  `text` is a typed answer): `{:ok, reply}`, `:error` when there is no such question.
  """
  @spec answer(integer(), String.t(), String.t() | nil, DateTime.t()) :: {:ok, String.t()} | :error
  def answer(id, choice, text, now) do
    with {:ok, {reply, _opts}} <- Server.Home.Organize.answer(via(), id, choice, text, now), do: {:ok, reply}
  end

  @doc """
  The questions the home has put to the operator and they have not answered: what a desktop keeps up.
  `%{id, key, at, text, choices, typed}` (`Server.Home.Organize.prompt/1`), the key new each time it
  is asked.
  """
  @spec asked() :: [map()]
  def asked do
    for jot <- Jot.asked(via()) do
      jot
      |> Server.Home.Organize.prompt()
      |> Map.merge(%{id: jot.id, key: "ask:#{jot.id}:#{jot.ask}:#{DateTime.to_unix(jot.asked_at)}", at: jot.asked_at})
    end
  end

  @doc """
  Take what the operator typed somewhere other than the chat, at `now`, as a text in the chat is
  taken: kept, read, and answered. The answer, as the chat would say it.
  """
  @spec say(String.t(), DateTime.t()) :: String.t()
  def say(text, now) do
    {reply, _opts} =
      Server.Home.Inbox.keep(
        via(),
        -System.unique_integer([:positive, :monotonic]) - System.os_time(:second),
        text,
        now
      )

    reply
  end

  @doc ~s|Put the open thing `id` off `until` (`"hour"`, `"tomorrow"`) from `now`: `{:ok, jot}`, `:error` when it is none or is done.|
  @spec later(integer(), String.t(), DateTime.t()) :: {:ok, Jot.t()} | :error
  def later(id, until, now) when until in ["hour", "tomorrow"] do
    case Jot.open(via(), id) do
      nil -> :error
      jot -> {:ok, Server.Home.Inbox.later(jot, until, now)}
    end
  end

  def later(_id, _until, _now), do: :error

  @doc "The reminders the operator has been told and has not done: what a desktop keeps up."
  @spec told() :: [Jot.t()]
  def told, do: via() |> Jot.opens() |> Enum.filter(&(&1.kind == "reminder" and &1.nudged_at != nil))

  @doc """
  The daily list for a desktop: `%{id, created_at, thread_id, body}` for the ten minutes after
  `home_list_at` (local) on a day something is open, nil otherwise.
  """
  @spec listing(DateTime.t()) :: map() | nil
  def listing(now) do
    local = Server.Home.Clock.local(now)
    {_coming, open} = board(via(), now)
    projects = projects(via())

    with {:ok, at} <- Time.from_iso8601(Server.OperatorConfig.setting("home_list_at") <> ":00"),
         since when since in 0..599 <- Time.diff(NaiveDateTime.to_time(local), at),
         [_ | _] <- open do
      %{
        id: Date.to_iso8601(NaiveDateTime.to_date(local)),
        created_at: DateTime.add(now, -since),
        thread_id: nil,
        body: "Still open: " <> Enum.map_join(open, " · ", &label(&1, projects))
      }
    else
      _ -> nil
    end
  end

  @doc "What is open from `via` at `now`, as `{coming, open}`: the reminders to come, and everything else still open."
  @spec board(String.t(), DateTime.t()) :: {[Jot.t()], [Jot.t()]}
  def board(via, now),
    do: via |> Jot.opens() |> Enum.split_with(&(&1.kind == "reminder" and DateTime.after?(&1.due_at, now)))

  @doc """
  Mark the open thing `id` done at `now`: `{:ok, jot}`, `:error` when it is none or is done. The last
  step of a project done puts the project's next step to the operator (`asked/0`).
  """
  @spec done(integer(), DateTime.t()) :: {:ok, Jot.t()} | :error
  def done(id, now) do
    case Jot.open(via(), id) do
      nil ->
        :error

      jot ->
        done = Jot.done(jot, now)
        Server.Home.Organize.advance(done, now)
        {:ok, done}
    end
  end

  defp via, do: Application.get_env(:server, :home_messenger, Server.Home.Telegram).name()

  defp row(jot, projects) do
    %{
      id: jot.id,
      kind: jot.kind,
      text: jot.text,
      due_at: jot.due_at,
      every: jot.every,
      since: jot.received_at,
      told_at: jot.nudged_at,
      project: project_of(jot, projects)
    }
  end

  defp project_of(%Jot{project_id: id}, projects) do
    case Map.fetch(projects, id) do
      {:ok, project} -> %{id: project.id, text: project.text}
      :error -> nil
    end
  end

  defp project(project) do
    {done, next} = {length(Jot.finished(project.id)), List.first(Jot.steps(project.id))}
    %{id: project.id, text: project.text, next: next && %{id: next.id, text: next.text}, done: done}
  end

  defp waiting(jot), do: %{id: jot.id, text: jot.text, who: jot.waiting_on, since: jot.received_at, due_at: jot.due_at}
end
