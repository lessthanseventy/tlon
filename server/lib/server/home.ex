defmodule Server.Home do
  @moduledoc """
  The home, as a surface other than the chat reads it: what the operator's jots have left open, what
  is coming, and the newest notes, what to do now, and the questions the home has put to the
  operator, and what a form puts in or changes without a reader (`add/2`, `edit/3`, `plan/3`,
  `revive/2`). The jots are the home messenger's (`:home_messenger`).
  """

  alias Server.Jot

  @doc """
  The home at `now`: `open` the to-dos and the reminders whose time has passed, `coming` the
  reminders to come, soonest first, `notes` the newest twenty (`note_rows` the same as `%{id, text}`,
  for naming one to delete), `projects` the open projects with their
  `next` step and how many are `done`, `waiting` what others owe the operator, `done` what was done in
  the last seven days by name (`text`, `done_at`, the newest first), and `done_week` how many
  things were done in the last seven days, and `agendas` the standing piles (`agenda_row/1`), `people` (`person_row/2`),
  `door` the pile by the door (`%{id, notes}`, `id` nil before anything was put on it), and `proposals` what sources suggest and the
  operator has not answered (`proposal_row/1`). A row's `since` is when it was said, its `told_at` when the
  operator was last told a reminder that is due (nil before that), its `project` the project it is a step
  of (nil when none). Things put off to someday or dropped are in none of these.
  """
  @spec status(DateTime.t()) :: %{
          open: [map()],
          coming: [map()],
          notes: [String.t()],
          note_rows: [map()],
          projects: [map()],
          waiting: [map()],
          someday: [map()],
          done: [map()],
          done_week: non_neg_integer(),
          agendas: [map()],
          people: [map()],
          door: map(),
          proposals: [map()]
        }
  def status(now) do
    {coming, open} = board(via(), now)
    projects = Jot.projects(via())
    named = Map.new(projects, &{&1.id, &1})
    done = Jot.done_since(via(), DateTime.add(now, -7, :day))

    %{
      open: Enum.map(open, &row(&1, named)),
      coming: Enum.map(coming, &row(&1, named)),
      notes: Jot.notes(via(), 20),
      note_rows: Jot.note_rows(via(), 20),
      projects: Enum.map(projects, &project/1),
      waiting: Enum.map(Jot.waiting(via()), &waiting/1),
      someday: Enum.map(Jot.somedays(via()), &row(&1, named)),
      done: Enum.map(done, &%{text: &1.text, done_at: &1.done_at}),
      done_week: length(done),
      agendas: Enum.map(Server.Agenda.all(via()), &agenda_row/1),
      people: people(now),
      door: door_row(Server.Agenda.door(via())),
      proposals: Enum.map(Server.Proposal.open(), &proposal_row/1)
    }
  end

  @doc "A proposal as `status/1` shows it: `%{id, source, text, why, url}`."
  @spec proposal_row(Server.Proposal.t()) :: map()
  def proposal_row(p), do: %{id: p.id, source: p.source, text: p.text, why: p.why, url: p.url}

  @doc "Take the open proposal `id` at `now` (`Server.Proposal.take/3`): `{:ok, row}`, `:not_found` when it is not open, `{:error, :seen}` when it could not be filed."
  @spec take_proposal(integer(), DateTime.t()) :: {:ok, map()} | :not_found | {:error, :seen}
  def take_proposal(id, now) do
    with {:ok, p} <- Server.Proposal.take(via(), id, now), do: {:ok, proposal_row(p)}
  end

  @doc "Dismiss the open proposal `id`, for good: `{:ok, row}`, `:not_found` when it is not open."
  @spec dismiss_proposal(integer()) :: {:ok, map()} | :not_found
  def dismiss_proposal(id) do
    with {:ok, p} <- Server.Proposal.dismiss(id), do: {:ok, proposal_row(p)}
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
  taken: kept, read, and answered as the chat would say it. `{reply, row}`, `row` the thing the text
  made, as `status/1` shows that kind of thing
  (a to-do, reminder or waiting-on row, a project row, a note as `%{id, text}`), nil when the text
  made no single row of its own: an ask, a "done", a list, a correction of the thing before it, a
  note on an agenda's pile.
  """
  @spec say_row(String.t(), DateTime.t()) :: {String.t(), map() | nil}
  def say_row(text, now) do
    external_id = -System.unique_integer([:positive, :monotonic]) - System.os_time(:second)
    {reply, opts} = Server.Home.Inbox.keep(via(), external_id, text, now)
    answer = Enum.join([reply | for({text, _opts} <- Keyword.get(opts, :then, []), do: text)], "\n\n")

    {answer, made(Jot.by_external_id(via(), external_id))}
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
  `home_list_at` (local) on a day something is open, nil otherwise. A read records nothing.
  """
  @spec listing(DateTime.t()) :: map() | nil
  def listing(now) do
    local = Server.Home.Clock.local(now)
    {_coming, open} = board(via(), now)
    projects = projects(via())

    with {:ok, at} <- Time.from_iso8601(Server.OperatorConfig.setting("home_list_at") <> ":00"),
         since when since in 0..599 <- Time.diff(NaiveDateTime.to_time(local), at),
         from = DateTime.add(now, -since),
         settled = Server.Proposal.settled(from),
         [_ | _] = parts <-
           List.wrap(if open != [], do: "Still open: " <> Enum.map_join(open, " · ", &label(&1, projects))) ++
             List.wrap(Server.Home.Proposals.settled(settled)) ++
             List.wrap(Server.Home.Proposals.plain(Server.Proposal.open())) do
      %{
        id: Date.to_iso8601(NaiveDateTime.to_date(local)),
        created_at: from,
        thread_id: nil,
        body: Enum.join(parts, "\n\n")
      }
    else
      _ -> nil
    end
  end

  @doc """
  The morning message for a desktop: `%{id, created_at, thread_id, body}` for the ten minutes after
  `home_morning_at` (local) when `Server.Home.Morning` has something to say (plain text), nil otherwise.
  """
  @spec morning(DateTime.t()) :: map() | nil
  def morning(now) do
    local = Server.Home.Clock.local(now)

    with {:ok, at} <- Time.from_iso8601(Server.OperatorConfig.setting("home_morning_at") <> ":00"),
         since when since in 0..599 <- Time.diff(NaiveDateTime.to_time(local), at),
         from = DateTime.add(now, -since),
         {body, _settled} <- Server.Home.Morning.plain(via(), now, from) do
      %{
        id: "morning:" <> Date.to_iso8601(NaiveDateTime.to_date(local)),
        created_at: from,
        thread_id: nil,
        body: body
      }
    else
      _ -> nil
    end
  end

  @doc "What is open from `via` at `now`, as `{coming, open}`: the reminders to come, and everything else still open."
  @spec board(String.t(), DateTime.t()) :: {[Jot.t()], [Jot.t()]}
  def board(via, now), do: via |> Jot.opens() |> Enum.split_with(&coming?(&1, now))

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

  @doc """
  Put a thing in from a form (`Server.Home.Form.add/2`: `kind`, `text`, `at`, `every`, `who`, `steps`,
  `project`), at `now`, filed as a reading is (`Server.Home.Organize.file/3`) with no model call:
  `{:ok, row}` as `status/1` shows it, `{:error, reason}` for a bad body, `:not_found` when `project`
  is not an open project. A to-do for a project is its open step when it has none, else the end of
  its plan (the project's row is answered).
  """
  @spec add(map(), DateTime.t()) :: {:ok, map()} | {:error, String.t()} | :not_found
  def add(params, now) do
    with {:ok, reading} <- Server.Home.Form.add(params, now), do: reading |> started(now) |> file(now)
  end

  @doc """
  Change the thing `id` as the operator says (`Server.Home.Form.edit/3`: `text`, `at`, `every` or null,
  `kind` only to-do or reminder; `Server.Home.Organize.edit/3`): `{:ok, row}`, `{:error, reason}`, or
  `:not_found` when it is none, is done or is deleted.
  """
  @spec edit(integer(), map(), DateTime.t()) :: {:ok, map()} | {:error, String.t()} | :not_found
  def edit(id, params, now) do
    with %Jot{} = jot <- Jot.live(via(), id) || :not_found,
         {:ok, changes} <- Server.Home.Form.edit(jot, params, now) do
      {:ok, view(Server.Home.Organize.edit(jot, changes, now))}
    end
  end

  @doc """
  Replace the plan (the steps still to come) of the open project `id` with `plan`, a list of
  texts, at `now`: `{:ok, project row}`, `{:error, reason}`, `:not_found`.
  """
  @spec plan(integer(), term(), DateTime.t()) :: {:ok, map()} | {:error, String.t()} | :not_found
  def plan(id, plan, now) do
    with %Jot{} = project <- Jot.project(via(), id) || :not_found,
         {:ok, texts} <- plan |> Server.Home.Form.texts() |> plan_error() do
      {:ok, view(Jot.plan(project, texts, now))}
    end
  end

  @doc "Bring the put-off thing `id` back (`Server.Home.Organize.revive/2`): `{:ok, row}`, `:not_found` when it is not on someday."
  @spec revive(integer(), DateTime.t()) :: {:ok, map()} | :not_found
  def revive(id, now) do
    case Enum.find(Jot.somedays(via()), &(&1.id == id)) do
      nil -> :not_found
      jot -> {:ok, view(Server.Home.Organize.revive(jot, now))}
    end
  end

  @doc """
  Delete the thing `id` at `now` (`Server.Home.Organize.delete/2`): any open to-do, reminder, step,
  project, waiting-on or note. `{:ok, jot}` the thing dropped, `:error` when it is none or is done or
  deleted. The only step of a project deleted puts the project's next step to the operator (`asked/0`).
  """
  @spec drop(integer(), DateTime.t()) :: {:ok, Jot.t()} | :error
  def drop(id, now) do
    case Jot.live(via(), id) do
      nil ->
        :error

      jot ->
        {gone, _more} = Server.Home.Organize.delete(jot, now)
        {:ok, gone}
    end
  end

  defp via, do: Application.get_env(:server, :home_messenger, Server.Home.Telegram).name()

  @doc """
  Start an agenda from a form (`Server.Home.Form.agenda/3`: `name`, `every`, `at`): `{:ok, row}` as
  `status/1` shows it, `{:error, reason}`.
  """
  @spec agenda_add(map(), DateTime.t()) :: {:ok, map()} | {:error, String.t()}
  def agenda_add(params, now) do
    with {:ok, %{name: name} = changes} <- Server.Home.Form.agenda(params, now, :add),
         :ok <- no_rhythm(changes[:kind], params),
         {:ok, agenda} <- Server.Agenda.create(via(), name, changes, now) do
      {:ok, agenda_view(agenda, now)}
    end
  end

  @doc """
  Change the agenda or person `id` (`name`, `every` or null, `at` or null, a person's `birthday` or
  null): `{:ok, row}`, `{:error, reason}`, `:not_found`.
  """
  @spec agenda_edit(integer(), map(), DateTime.t()) :: {:ok, map()} | {:error, String.t()} | :not_found
  def agenda_edit(id, params, now) do
    with %Server.Agenda{} = agenda <- Server.Agenda.get(via(), id) || :not_found,
         :ok <- editable(agenda),
         :ok <- no_rhythm(agenda.kind, params),
         {:ok, changes} <- Server.Home.Form.agenda(params, now, :edit),
         {:ok, agenda} <- Server.Agenda.edit(agenda, changes, now) do
      {:ok, agenda_view(agenda, now)}
    end
  end

  @doc "Put a note `text` on the pile of the agenda `id` (a person's too): `{:ok, note row}`, `{:error, reason}`, `:not_found`."
  @spec agenda_note(integer(), term(), DateTime.t()) :: {:ok, map()} | {:error, String.t()} | :not_found
  def agenda_note(id, text, now) do
    with %Server.Agenda{} = agenda <- Server.Agenda.get(via(), id) || :not_found,
         {:ok, %{text: text}} <- Server.Home.Form.add(%{"kind" => "note", "text" => text}, now) do
      {:ok, note_on(agenda, text, now)}
    end
  end

  @doc """
  Put a note `text` on the pile by the door, which a first note makes: `{:ok, note row}`,
  `{:error, reason}`. A note comes off it by `drop/2`, deleted (the item route `POST /api/home/:id/drop`):
  `done/2` is for reminders and to-dos alone.
  """
  @spec door_add(term(), DateTime.t()) :: {:ok, map()} | {:error, String.t()}
  def door_add(text, now) do
    with {:ok, %{text: text}} <- Server.Home.Form.add(%{"kind" => "note", "text" => text}, now) do
      {:ok, via() |> Server.Agenda.ensure_door(now) |> note_on(text, now)}
    end
  end

  @doc "Archive the pile of the agenda `id` (its notes kept, done): `{:ok, row}`, `:not_found`."
  @spec agenda_clear(integer(), DateTime.t()) :: {:ok, map()} | :not_found
  def agenda_clear(id, now) do
    case Server.Agenda.get(via(), id) do
      nil ->
        :not_found

      agenda ->
        Server.Agenda.clear(agenda, now)
        {:ok, agenda_view(agenda, now)}
    end
  end

  @doc "Delete the agenda `id` and its pile: `{:ok, %{id, name}}`, `:not_found`."
  @spec agenda_drop(integer(), DateTime.t()) :: {:ok, map()} | {:error, String.t()} | :not_found
  def agenda_drop(id, now) do
    with %Server.Agenda{} = agenda <- Server.Agenda.get(via(), id) || :not_found,
         :ok <- editable(agenda) do
      :ok = Server.Agenda.delete(agenda, now)
      {:ok, %{id: agenda.id, name: agenda.name}}
    end
  end

  @doc """
  The agendas whose pile was told since `since` and still has notes, as the desktop raises them:
  `%{id, created_at, thread_id, body}`, `body` the same line the chat is told.
  """
  @spec told_agendas(DateTime.t()) :: [map()]
  def told_agendas(since) do
    for agenda <- Server.Agenda.told_since(via(), since),
        [_ | _] = notes <- [Jot.agenda_notes(agenda.id)] do
      %{
        id: "#{agenda.id}:#{DateTime.to_unix(agenda.told_for)}",
        created_at: agenda.told_at,
        thread_id: nil,
        body: Server.Agenda.say_told(agenda, notes)
      }
    end
  end

  @doc "An agenda as `status/1` shows it: `%{id, name, every, next_at, notes: [%{id, text, since}]}`."
  @spec agenda_row(Server.Agenda.t()) :: map()
  def agenda_row(agenda) do
    %{
      id: agenda.id,
      name: agenda.name,
      every: agenda.every,
      next_at: agenda.next_at,
      notes: for(note <- Jot.agenda_notes(agenda.id), do: %{id: note.id, text: note.text, since: note.received_at})
    }
  end

  @doc """
  The people from `via` at `now` as `status/1` shows them: `%{id, name, birthday, next_birthday, notes,
  todos}`. `birthday` is as kept (`MM-DD` or `YYYY-MM-DD`) or nil, `next_birthday` the local date it next
  falls (today counts), `notes` as an agenda's, `todos` the open to-dos, reminders and waiting-ons whose
  text (a waiting-on's `who` too) names the person as a whole word, in any case. Ordered by next
  birthday, those with none last by name.
  """
  @spec people(DateTime.t()) :: [map()]
  def people(now) do
    open = Jot.opens(via()) ++ Jot.waiting(via())

    via()
    |> Server.Agenda.all("person")
    |> Enum.map(&person_row(&1, now, open))
    |> Enum.sort_by(&{&1.next_birthday == nil, &1.next_birthday && Date.to_erl(&1.next_birthday), &1.name})
  end

  @doc "A person as `people/1` shows them, `open` the things to look in for their to-dos."
  @spec person_row(Server.Agenda.t(), DateTime.t(), [Jot.t()]) :: map()
  def person_row(%Server.Agenda{} = person, now, open) do
    today = now |> Server.Home.Clock.local() |> NaiveDateTime.to_date()
    name = ~r/(?<![\p{L}\p{N}_])#{Regex.escape(person.name)}(?![\p{L}\p{N}_])/iu

    %{
      id: person.id,
      name: person.name,
      birthday: person.birthday,
      next_birthday: Server.Agenda.next_birthday(person.birthday, today),
      notes: agenda_row(person).notes,
      todos: for(jot <- open, names?(jot, name), do: view(jot))
    }
  end

  defp names?(%Jot{kind: "waiting", waiting_on: who} = jot, name),
    do: Regex.match?(name, jot.text) or (is_binary(who) and Regex.match?(name, who))

  defp names?(jot, name), do: Regex.match?(name, jot.text)

  defp door_row(nil), do: %{id: nil, notes: []}
  defp door_row(door), do: %{id: door.id, notes: agenda_row(door).notes}

  defp agenda_view(%Server.Agenda{kind: "person"} = person, now),
    do: person_row(person, now, Jot.opens(via()) ++ Jot.waiting(via()))

  defp agenda_view(agenda, _now), do: agenda_row(agenda)

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
    {finished, next} = {Jot.finished(project.id), List.first(Jot.steps(project.id))}

    %{
      id: project.id,
      kind: "project",
      text: project.text,
      since: project.received_at,
      next: next && %{id: next.id, text: next.text},
      done: length(finished),
      plan: project.plan,
      steps_done: finished
    }
  end

  defp waiting(jot) do
    %{
      id: jot.id,
      kind: "waiting",
      text: jot.text,
      who: jot.waiting_on,
      since: jot.received_at,
      due_at: jot.due_at,
      every: nil,
      told_at: nil,
      project: nil
    }
  end

  defp view(%Jot{kind: "project"} = jot), do: project(jot)
  defp view(%Jot{kind: "waiting"} = jot), do: waiting(jot)
  defp view(jot), do: row(jot, projects(via()))

  defp coming?(%Jot{kind: "reminder", due_at: %DateTime{} = due}, now), do: DateTime.after?(due, now)
  defp coming?(_jot, _now), do: false

  defp file(%{kind: "todo", project: id, text: text}, now) do
    case Jot.project(via(), id) do
      nil ->
        :not_found

      project ->
        case Server.Home.Organize.add_step(project, text, now) do
          {:step, step} -> {:ok, view(step)}
          {:plan, project} -> {:ok, view(project)}
        end
    end
  end

  defp file(reading, now) do
    {:ok, jot} =
      Jot.take(via(), -System.unique_integer([:positive, :monotonic]) - System.os_time(:second), reading.text)

    Server.Home.Organize.file(jot, reading, now)
    {:ok, view(Jot.get(jot.id))}
  end

  defp plan_error(:error), do: {:error, "plan is a list of texts"}
  defp plan_error(ok), do: ok

  # a repeat started in the past starts from its next time after now, on the day it started on
  defp started(%{every: every, due_at: %DateTime{} = due} = reading, now) when is_binary(every) do
    anchor = Jot.anchor(every, due)
    Map.merge(reading, %{due_at: Server.Home.Clock.forward(due, every, now, anchor), every_day: anchor})
  end

  defp started(reading, _now), do: reading

  defp note_on(agenda, text, now) do
    {:ok, jot} = Jot.take(via(), -System.unique_integer([:positive, :monotonic]) - System.os_time(:second), text)
    agenda |> Server.Agenda.note(jot, text, now) |> view()
  end

  defp editable(%Server.Agenda{kind: "door"}),
    do: {:error, "the door pile cannot be edited or dropped; clear it or drop its notes"}

  defp editable(_agenda), do: :ok

  defp no_rhythm("person", params) when is_map_key(params, "every") or is_map_key(params, "at"),
    do: {:error, "a person has no every or at"}

  defp no_rhythm(_kind, _params), do: :ok

  defp made(%Jot{dropped_at: nil, kind: "note", agenda_id: nil} = jot), do: %{id: jot.id, text: jot.text}

  defp made(%Jot{dropped_at: nil, kind: kind} = jot) when kind in ["todo", "reminder", "waiting", "project"],
    do: view(jot)

  defp made(_jot), do: nil
end
