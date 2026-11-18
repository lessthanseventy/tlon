defmodule Server.Jot do
  @moduledoc """
  Something the operator sent the home's inbox from away from the machine, kept exactly as it came:
  `via` the messenger it arrived through, `external_id` that messenger's own id for it, so one
  delivered twice is one jot. `body` is the raw capture and never changes. Beside it is the reading
  `Server.Home.Reader` made of it, absent until one is made: `kind` (`"reminder"`, `"note"`, or
  `"todo"`, `"project"` for an outcome of several steps, `"waiting"` for a thing someone else owes
  (`waiting_on` who), `"amend"` for a message that only corrected the jot before it, `"talk"` for one that
  asked or told the helper something and is nothing to keep), `text`, a reminder's `due_at` and the
  `every` it repeats by, when
  and how often the operator has been told (`nudged_at`, `nudges`), and `done_at` once they say it is
  done.

  What the home organizes on its own is kept on the same row. A step is a to-do whose `project_id`
  is its project's jot; a project holds the steps still `plan`ned, and the step it `proposed`
  and is waiting to be told yes. `ask` names the question the operator has not answered (`"next"`,
  `"review"`, `"waiting"`, `"shrink"`), `asked_at` when it was put. `mins` is a to-do's rough size
  (2, 10, 30, 60), `touched_at` the last time the operator did anything with it, `hidden_until` the
  moment a "not today" ends, `someday_at` and `dropped_at` when it left the open list, and
  `shrunk_at` when a smaller start was offered for it or the model had none.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Server.Repo

  @type t :: %__MODULE__{}

  schema "jot" do
    field :via, :string
    field :external_id, :integer
    field :body, :string
    field :received_at, :utc_datetime
    field :kind, :string
    field :text, :string
    field :due_at, :utc_datetime
    field :nudged_at, :utc_datetime
    field :nudges, :integer, default: 0
    field :done_at, :utc_datetime
    field :every, :string
    field :every_day, :integer
    field :project_id, :integer
    field :plan, {:array, :string}, default: []
    field :proposed, :string
    field :ask, :string
    field :asked_at, :utc_datetime
    field :waiting_on, :string
    field :mins, :integer
    field :touched_at, :utc_datetime
    field :hidden_until, :utc_datetime
    field :someday_at, :utc_datetime
    field :dropped_at, :utc_datetime
    field :shrunk_at, :utc_datetime
  end

  @doc """
  Put a reading on `jot`, in place of any it had: a reminder so changed is open again and told
  again. `every` (`"day"`, `"week"`, `"month"`, or a number then one: `"6 week"`) is a reminder that
  repeats, `every_day` the day of the month it started on so a short month does not move it. A reading may also carry
  `mins`, `project` (the project a step belongs to), `steps` (a project's: all but the first are its
  plan) and `who` (a waiting-on's); what it leaves out stays as it was. Filing is a touch at `now`,
  and makes it plainly open again: not done, put off, dropped or hidden. Only what the operator does touches a thing: filing,
  amending, putting off, keeping, hiding, done; the home's own nudges and questions do not.
  """
  @spec file(%__MODULE__{}, %{kind: String.t(), text: String.t() | nil, due_at: DateTime.t() | nil}, DateTime.t()) ::
          %__MODULE__{}
  def file(%__MODULE__{} = jot, %{kind: kind, text: text, due_at: due_at} = reading, now \\ DateTime.utc_now()) do
    optional =
      for {from, to} <- [mins: :mins, project: :project_id, who: :waiting_on, steps: :plan],
          Map.has_key?(reading, from),
          do: {to, if(from == :steps, do: Enum.drop(reading.steps, 1), else: reading[from])}

    put(
      jot,
      [
        kind: kind,
        text: text,
        due_at: due_at,
        every: Map.get(reading, :every),
        every_day: Map.get_lazy(reading, :every_day, fn -> anchor(Map.get(reading, :every), due_at) end),
        nudged_at: nil,
        nudges: 0,
        done_at: nil,
        someday_at: nil,
        dropped_at: nil,
        hidden_until: nil,
        ask: nil,
        proposed: nil
      ] ++ optional,
      now
    )
  end

  @doc "Everything from `via` still open, reminders and to-dos: the to-dos first, then the reminders by their time."
  @spec opens(String.t()) :: [%__MODULE__{}]
  def opens(via) do
    Repo.all(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind in ["reminder", "todo"],
        where: ^open_now(),
        order_by: [asc_nulls_first: j.due_at, asc: j.id]
      )
    )
  end

  @doc "The text of the newest `limit` notes from `via` not deleted, newest first."
  @spec notes(String.t(), pos_integer()) :: [String.t()]
  def notes(via, limit), do: via |> note_rows(limit) |> Enum.map(& &1.text)

  @doc "The newest `limit` notes from `via` not deleted as `%{id, text}`, newest first."
  @spec note_rows(String.t(), pos_integer()) :: [%{id: integer(), text: String.t()}]
  def note_rows(via, limit) do
    Repo.all(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind == "note" and is_nil(j.dropped_at),
        order_by: [desc: j.id],
        limit: ^limit,
        select: %{id: j.id, text: j.text}
      )
    )
  end

  @doc "The newest jot from `via` read as a reminder, a to-do, a note, a project or a waiting-on and not deleted, nil when none is."
  @spec last_filed(String.t()) :: %__MODULE__{} | nil
  def last_filed(via) do
    Repo.one(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind in ["reminder", "todo", "note", "project", "waiting"],
        where: is_nil(j.dropped_at),
        order_by: [desc: j.external_id],
        limit: 1
      )
    )
  end

  @doc "The open reminders from `via` due at `now`, oldest first: not one done, dropped or put off."
  @spec due(String.t(), DateTime.t()) :: [%__MODULE__{}]
  def due(via, now) do
    Repo.all(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind == "reminder" and j.due_at <= ^now,
        where: ^open_now(),
        order_by: j.due_at
      )
    )
  end

  @doc "The open reminder from `via` the operator was told last, nil when none is."
  @spec last_nudged(String.t()) :: %__MODULE__{} | nil
  def last_nudged(via) do
    Repo.one(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind == "reminder" and not is_nil(j.nudged_at),
        where: ^open_now(),
        order_by: [desc: j.nudged_at, desc: j.id],
        limit: 1
      )
    )
  end

  @doc "The open reminder or to-do `id` from `via`, nil when it is none or is done."
  @spec open(String.t(), integer()) :: %__MODULE__{} | nil
  def open(via, id) do
    Repo.one(
      from(j in __MODULE__,
        where: j.via == ^via and j.id == ^id and j.kind in ["reminder", "todo"],
        where: ^open_now()
      )
    )
  end

  @doc "The thing `id` from `via` that can be deleted, nil when it is none, is done or is deleted: any kind but a talk."
  @spec live(String.t(), integer()) :: %__MODULE__{} | nil
  def live(via, id) do
    Repo.one(
      from(j in __MODULE__,
        where: j.via == ^via and j.id == ^id and j.kind in ["reminder", "todo", "note", "project", "waiting"],
        where: is_nil(j.done_at) and is_nil(j.dropped_at)
      )
    )
  end

  @doc "The open projects from `via`, oldest first."
  @spec projects(String.t()) :: [%__MODULE__{}]
  def projects(via) do
    Repo.all(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind == "project" and is_nil(j.done_at) and is_nil(j.dropped_at),
        order_by: j.id
      )
    )
  end

  @doc "The open project `id` from `via`, nil when it is none or is finished."
  @spec project(String.t(), integer()) :: %__MODULE__{} | nil
  def project(via, id), do: Enum.find(projects(via), &(&1.id == id))

  @doc "The steps of project `id` still open, oldest first: a step put off to a time is a reminder and still one."
  @spec steps(integer()) :: [%__MODULE__{}]
  def steps(id) do
    Repo.all(
      from(j in __MODULE__,
        where: j.project_id == ^id and j.kind in ["todo", "reminder"],
        where: ^open_now(),
        order_by: j.id
      )
    )
  end

  @doc "The text of the steps of project `id` that were done, oldest first."
  @spec finished(integer()) :: [String.t()]
  def finished(id) do
    Repo.all(
      from(j in __MODULE__,
        where: j.project_id == ^id and j.kind in ["todo", "reminder"] and not is_nil(j.done_at),
        order_by: [j.done_at, j.id],
        select: j.text
      )
    )
  end

  @doc "What `via` is waiting on others for and has not got, oldest first."
  @spec waiting(String.t()) :: [%__MODULE__{}]
  def waiting(via) do
    Repo.all(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind == "waiting" and is_nil(j.done_at) and is_nil(j.dropped_at),
        order_by: j.id
      )
    )
  end

  @doc "The reminders and to-dos from `via` put off to someday, oldest first."
  @spec somedays(String.t()) :: [%__MODULE__{}]
  def somedays(via) do
    Repo.all(
      from(j in __MODULE__,
        where:
          j.via == ^via and j.kind in ["reminder", "todo"] and is_nil(j.done_at) and is_nil(j.dropped_at) and
            not is_nil(j.someday_at),
        order_by: j.id
      )
    )
  end

  @doc "Everything from `via` with a question the operator has not answered, oldest first."
  @spec asked(String.t()) :: [%__MODULE__{}]
  def asked(via) do
    Repo.all(
      from(j in __MODULE__,
        where: j.via == ^via and not is_nil(j.ask) and is_nil(j.done_at) and is_nil(j.dropped_at),
        order_by: [asc: j.asked_at, asc: j.id]
      )
    )
  end

  @doc "The thing `id` from `via` with an unanswered question, nil when it has none."
  @spec asked(String.t(), integer()) :: %__MODULE__{} | nil
  def asked(via, id), do: Enum.find(asked(via), &(&1.id == id))

  @doc "A step of `project`, a to-do of its own, kept at `now`; `mins` is its rough size."
  @spec step(%__MODULE__{}, String.t(), DateTime.t(), integer() | nil) :: %__MODULE__{}
  def step(%__MODULE__{} = project, text, now, mins \\ nil) do
    Repo.insert!(%__MODULE__{
      via: project.via,
      external_id: -System.unique_integer([:positive, :monotonic]) - System.os_time(:second),
      body: text,
      received_at: DateTime.truncate(now, :second),
      kind: "todo",
      text: text,
      project_id: project.id,
      mins: mins
    })
  end

  @doc "Put the question `ask` to the operator about `jot` at `now`, with the step it `proposed`, if any. Not a touch."
  @spec ask(%__MODULE__{}, String.t(), String.t() | nil, DateTime.t()) :: %__MODULE__{}
  def ask(%__MODULE__{} = jot, ask, proposed, now),
    do: put(jot, [ask: ask, proposed: proposed, asked_at: DateTime.truncate(now, :second)], false)

  @doc "Put the question `ask` on `jot` only if it has none: `true` when this call put it. Not a touch."
  @spec ask_free(%__MODULE__{}, String.t(), String.t() | nil, DateTime.t()) :: boolean()
  def ask_free(%__MODULE__{id: id}, ask, proposed, now) do
    {changed, _} =
      Repo.update_all(from(j in __MODULE__, where: j.id == ^id and is_nil(j.ask)),
        set: [ask: ask, proposed: proposed, asked_at: DateTime.truncate(now, :second)]
      )

    changed == 1
  end

  @doc "The question about `jot` was answered at `now`, and that is a touch."
  @spec touch(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def touch(%__MODULE__{} = jot, now \\ DateTime.utc_now()), do: put(jot, [ask: nil, proposed: nil], now)

  @doc "Set what is left of a project's plan to `plan`: a touch at `now` when the operator did it."
  @spec plan(%__MODULE__{}, [String.t()], DateTime.t() | false) :: %__MODULE__{}
  def plan(%__MODULE__{} = jot, plan, now \\ false), do: put(jot, [plan: plan], now)

  @doc "Move `jot` to someday at `now`."
  @spec someday(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def someday(%__MODULE__{} = jot, now),
    do: put(jot, [someday_at: DateTime.truncate(now, :second), ask: nil, proposed: nil], now)

  @doc "Close `jot` as dropped at `now`: not done, so not counted as done."
  @spec drop(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def drop(%__MODULE__{} = jot, now),
    do: put(jot, [dropped_at: DateTime.truncate(now, :second), ask: nil, proposed: nil], now)

  @doc "Hide `jot` from what-now picks until `until`, the operator having said so at `now`."
  @spec hide(%__MODULE__{}, DateTime.t(), DateTime.t()) :: %__MODULE__{}
  def hide(%__MODULE__{} = jot, until, now \\ DateTime.utc_now()),
    do: put(jot, [hidden_until: DateTime.truncate(until, :second)], now)

  @doc "Turn the to-do `jot` into a project with `start` as its first step, kept at `now`: the step."
  @spec shrink(%__MODULE__{}, String.t(), DateTime.t()) :: %__MODULE__{}
  def shrink(%__MODULE__{} = jot, start, now) do
    jot |> put([kind: "project", ask: nil, proposed: nil], now) |> step(start, now, 2)
  end

  @doc "Record that a smaller start was offered for `jot` at `now`, or that the model had none: not asked again."
  @spec shrunk(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def shrunk(%__MODULE__{} = jot, now), do: put(jot, [shrunk_at: DateTime.truncate(now, :second)], false)

  @doc "The last time the operator did anything with `jot`: its filing when nothing since."
  @spec touched(%__MODULE__{}) :: DateTime.t()
  def touched(%__MODULE__{touched_at: nil, received_at: at}), do: at
  def touched(%__MODULE__{touched_at: at}), do: at

  @doc "Record that the operator was told `jot` at `now`. Being told is not a touch."
  @spec nudged(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def nudged(%__MODULE__{} = jot, now),
    do: put(jot, [nudged_at: DateTime.truncate(now, :second), nudges: jot.nudges + 1], false)

  @doc "Record that `jot` was done at `now`. A reminder that repeats stays open, put off to its next time."
  @spec done(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def done(%__MODULE__{} = jot, now) when is_nil(jot.every) or is_nil(jot.due_at),
    do: put(jot, [done_at: DateTime.truncate(now, :second), ask: nil, proposed: nil], now)

  def done(%__MODULE__{every: every} = jot, now),
    do: put_off(jot, Server.Home.Clock.next(jot.due_at, every, now, jot.every_day), now)

  @doc "Put `jot` off to `due_at` at the operator's word at `now`: a reminder from then on (a to-do too), told afresh then."
  @spec put_off(%__MODULE__{}, DateTime.t(), DateTime.t()) :: %__MODULE__{}
  def put_off(%__MODULE__{} = jot, due_at, now \\ DateTime.utc_now()),
    do:
      put(
        jot,
        [
          kind: "reminder",
          due_at: DateTime.truncate(due_at, :second),
          nudged_at: nil,
          nudges: 0,
          ask: nil,
          proposed: nil
        ],
        now
      )

  @doc "Move the reminder `jot` that repeats on to its time `due_at` by itself: not a touch."
  @spec roll(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def roll(%__MODULE__{} = jot, due_at),
    do: put(jot, [due_at: DateTime.truncate(due_at, :second), nudged_at: nil, nudges: 0], false)

  @doc "Ask about the waiting-on `jot` again at `due_at`, the operator having said so at `now`."
  @spec ask_again(%__MODULE__{}, DateTime.t(), DateTime.t()) :: %__MODULE__{}
  def ask_again(%__MODULE__{} = jot, due_at, now \\ DateTime.utc_now()),
    do: put(jot, [due_at: DateTime.truncate(due_at, :second), ask: nil], now)

  @doc "The things from `via` done since `since`, the newest first."
  @spec done_since(String.t(), DateTime.t()) :: [%__MODULE__{}]
  def done_since(via, since),
    do:
      Repo.all(
        from(j in __MODULE__, where: j.via == ^via and j.done_at >= ^since, order_by: [desc: j.done_at, desc: j.id])
      )

  @doc "Keep `body`: `{:ok, jot}`, or `:seen` when `via` already delivered `external_id`."
  @spec take(String.t(), integer(), String.t()) :: {:ok, %__MODULE__{}} | :seen
  def take(via, external_id, body) do
    jot = %__MODULE__{
      via: via,
      external_id: external_id,
      body: body,
      received_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    case Repo.insert!(jot, on_conflict: :nothing, conflict_target: [:via, :external_id]) do
      %__MODULE__{id: nil} -> :seen
      kept -> {:ok, kept}
    end
  end

  @doc "The newest `limit` jots that came through `via`, newest first."
  @spec recent(String.t(), pos_integer()) :: [%__MODULE__{}]
  def recent(via, limit),
    do: Repo.all(from(j in __MODULE__, where: j.via == ^via, order_by: [desc: j.external_id], limit: ^limit))

  @doc "The highest `external_id` kept from `via`, nil when it has delivered nothing."
  @spec cursor(String.t()) :: integer() | nil
  def cursor(via), do: Repo.one(from(j in __MODULE__, where: j.via == ^via, select: max(j.external_id)))

  @doc "The day of the month a repeat by months is on, kept so a short month does not move it: nil for any other repeat."
  @spec anchor(String.t() | nil, DateTime.t() | nil) :: pos_integer() | nil
  def anchor(every, %DateTime{} = due) when is_binary(every) do
    if every =~ ~r/(^|\s)month$/, do: Server.Home.Clock.local(due).day
  end

  def anchor(_every, _due), do: nil

  @doc "The thing `id`, nil when there is none."
  @spec get(integer()) :: %__MODULE__{} | nil
  def get(id), do: Repo.get(__MODULE__, id)

  @doc "Change `jot` as the operator edits it: `changes` are its fields, and it is a touch at `now`."
  @spec edit(%__MODULE__{}, keyword(), DateTime.t()) :: %__MODULE__{}
  def edit(%__MODULE__{} = jot, changes, now), do: put(jot, changes, now)

  defp open_now do
    dynamic([j], is_nil(j.done_at) and is_nil(j.dropped_at) and is_nil(j.someday_at))
  end

  defp put(jot, changes, false), do: jot |> Ecto.Changeset.change(changes) |> Repo.update!()

  defp put(jot, changes, %DateTime{} = now),
    do: put(jot, [touched_at: DateTime.truncate(now, :second)] ++ changes, false)
end
