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
  `shrunk_at` when a smaller start was offered for it.
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
  again. `every` (`"day"`, `"week"`, `"month"`) is a reminder that repeats. A reading may also carry
  `mins`, `project` (the project a step belongs to), `steps` (a project's: all but the first are its
  plan) and `who` (a waiting-on's); what it leaves out stays as it was. Filing is a touch, and
  brings a thing back from someday.
  """
  @spec file(%__MODULE__{}, %{kind: String.t(), text: String.t() | nil, due_at: DateTime.t() | nil}) :: %__MODULE__{}
  def file(%__MODULE__{} = jot, %{kind: kind, text: text, due_at: due_at} = reading) do
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
        nudged_at: nil,
        nudges: 0,
        done_at: nil,
        someday_at: nil,
        ask: nil,
        proposed: nil
      ] ++ optional
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

  @doc "The text of the newest `limit` notes from `via`, newest first."
  @spec notes(String.t(), pos_integer()) :: [String.t()]
  def notes(via, limit) do
    Repo.all(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind == "note",
        order_by: [desc: j.id],
        limit: ^limit,
        select: j.text
      )
    )
  end

  @doc "The newest jot from `via` read as a reminder, a to-do, a note, a project or a waiting-on, nil when none is."
  @spec last_filed(String.t()) :: %__MODULE__{} | nil
  def last_filed(via) do
    Repo.one(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind in ["reminder", "todo", "note", "project", "waiting"],
        order_by: [desc: j.external_id],
        limit: 1
      )
    )
  end

  @doc "The reminders from `via` due at `now` and not done, oldest first."
  @spec due(String.t(), DateTime.t()) :: [%__MODULE__{}]
  def due(via, now) do
    Repo.all(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind == "reminder" and is_nil(j.done_at) and j.due_at <= ^now,
        order_by: j.due_at
      )
    )
  end

  @doc "The reminder from `via` the operator was told last and has not done, nil when none is."
  @spec last_nudged(String.t()) :: %__MODULE__{} | nil
  def last_nudged(via) do
    Repo.one(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind == "reminder" and is_nil(j.done_at) and not is_nil(j.nudged_at),
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

  @doc "The steps of project `id` still open, oldest first."
  @spec steps(integer()) :: [%__MODULE__{}]
  def steps(id) do
    Repo.all(from(j in __MODULE__, where: j.project_id == ^id and j.kind == "todo", where: ^open_now(), order_by: j.id))
  end

  @doc "The text of the steps of project `id` that were done, oldest first."
  @spec finished(integer()) :: [String.t()]
  def finished(id) do
    Repo.all(
      from(j in __MODULE__,
        where: j.project_id == ^id and j.kind == "todo" and not is_nil(j.done_at),
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

  @doc "The question about `jot` was answered, and that is a touch."
  @spec touch(%__MODULE__{}) :: %__MODULE__{}
  def touch(%__MODULE__{} = jot), do: put(jot, ask: nil, proposed: nil)

  @doc "Set what is left of a project's plan to `plan`."
  @spec plan(%__MODULE__{}, [String.t()]) :: %__MODULE__{}
  def plan(%__MODULE__{} = jot, plan), do: put(jot, [plan: plan], false)

  @doc "Move `jot` to someday at `now`."
  @spec someday(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def someday(%__MODULE__{} = jot, now),
    do: put(jot, someday_at: DateTime.truncate(now, :second), ask: nil, proposed: nil)

  @doc "Close `jot` as dropped at `now`: not done, so not counted as done."
  @spec drop(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def drop(%__MODULE__{} = jot, now), do: put(jot, dropped_at: DateTime.truncate(now, :second), ask: nil, proposed: nil)

  @doc "Hide `jot` from what-now picks until `until`."
  @spec hide(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def hide(%__MODULE__{} = jot, until), do: put(jot, hidden_until: DateTime.truncate(until, :second))

  @doc "Turn the to-do `jot` into a project with `start` as its first step, kept at `now`: the step."
  @spec shrink(%__MODULE__{}, String.t(), DateTime.t()) :: %__MODULE__{}
  def shrink(%__MODULE__{} = jot, start, now) do
    jot |> put(kind: "project", ask: nil, proposed: nil) |> step(start, now, 2)
  end

  @doc "Record that a smaller start was offered for `jot` at `now`."
  @spec shrunk(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def shrunk(%__MODULE__{} = jot, now), do: put(jot, [shrunk_at: DateTime.truncate(now, :second)], false)

  @doc "The last time the operator did anything with `jot`: its filing when nothing since."
  @spec touched(%__MODULE__{}) :: DateTime.t()
  def touched(%__MODULE__{touched_at: nil, received_at: at}), do: at
  def touched(%__MODULE__{touched_at: at}), do: at

  @doc "Record that the operator was told `jot` at `now`."
  @spec nudged(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def nudged(%__MODULE__{} = jot, now), do: put(jot, nudged_at: DateTime.truncate(now, :second), nudges: jot.nudges + 1)

  @doc "Record that `jot` was done at `now`. A reminder that repeats stays open, put off to its next time."
  @spec done(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def done(%__MODULE__{every: nil} = jot, now),
    do: put(jot, done_at: DateTime.truncate(now, :second), ask: nil, proposed: nil)

  def done(%__MODULE__{every: every} = jot, now), do: put_off(jot, Server.Home.Clock.next(jot.due_at, every, now))

  @doc "Put `jot` off to `due_at`: a reminder from then on (a to-do too), told afresh at that time."
  @spec put_off(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def put_off(%__MODULE__{} = jot, due_at),
    do: put(jot, kind: "reminder", due_at: DateTime.truncate(due_at, :second), nudged_at: nil, nudges: 0)

  @doc "Ask about the waiting-on `jot` again at `due_at`."
  @spec ask_again(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def ask_again(%__MODULE__{} = jot, due_at), do: put(jot, due_at: DateTime.truncate(due_at, :second), ask: nil)

  @doc "How many things from `via` were done since `since`."
  @spec done_since(String.t(), DateTime.t()) :: non_neg_integer()
  def done_since(via, since),
    do: Repo.aggregate(from(j in __MODULE__, where: j.via == ^via and j.done_at >= ^since), :count)

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

  defp open_now do
    dynamic([j], is_nil(j.done_at) and is_nil(j.dropped_at) and is_nil(j.someday_at))
  end

  defp put(jot, changes, touch? \\ true) do
    changes = if touch?, do: [touched_at: DateTime.truncate(DateTime.utc_now(), :second)] ++ changes, else: changes
    jot |> Ecto.Changeset.change(changes) |> Repo.update!()
  end
end
