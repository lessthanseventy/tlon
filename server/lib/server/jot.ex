defmodule Server.Jot do
  @moduledoc """
  Something the operator sent the home's inbox from away from the machine, kept exactly as it came:
  `via` the messenger it arrived through, `external_id` that messenger's own id for it, so one
  delivered twice is one jot. `body` is the raw capture and never changes. Beside it is the reading
  `Server.Home.Reader` made of it, absent until one is made: `kind` (`"reminder"`, `"note"`, or
  `"todo"`, `"amend"` for a message that only corrected the jot before it, `"talk"` for one that
  asked or told the helper something and is nothing to keep), `text`, a reminder's `due_at` and the
  `every` it repeats by, when
  and how often the operator has been told (`nudged_at`, `nudges`), and `done_at` once they say it is
  done.
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
  end

  @doc """
  Put a reading on `jot`, in place of any it had: a reminder so changed is open again and told
  again. `every` (`"day"`, `"week"`, `"month"`) is a reminder that repeats.
  """
  @spec file(%__MODULE__{}, %{kind: String.t(), text: String.t() | nil, due_at: DateTime.t() | nil}) :: %__MODULE__{}
  def file(%__MODULE__{} = jot, %{kind: kind, text: text, due_at: due_at} = reading) do
    put(jot,
      kind: kind,
      text: text,
      due_at: due_at,
      every: Map.get(reading, :every),
      nudged_at: nil,
      nudges: 0,
      done_at: nil
    )
  end

  @doc "Everything from `via` still open, reminders and to-dos: the to-dos first, then the reminders by their time."
  @spec opens(String.t()) :: [%__MODULE__{}]
  def opens(via) do
    Repo.all(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind in ["reminder", "todo"] and is_nil(j.done_at),
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

  @doc "The newest jot from `via` read as a reminder, a to-do or a note, nil when none is."
  @spec last_filed(String.t()) :: %__MODULE__{} | nil
  def last_filed(via) do
    Repo.one(
      from(j in __MODULE__,
        where: j.via == ^via and j.kind in ["reminder", "todo", "note"],
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
        where: j.via == ^via and j.id == ^id and j.kind in ["reminder", "todo"] and is_nil(j.done_at)
      )
    )
  end

  @doc "Record that the operator was told `jot` at `now`."
  @spec nudged(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def nudged(%__MODULE__{} = jot, now), do: put(jot, nudged_at: DateTime.truncate(now, :second), nudges: jot.nudges + 1)

  @doc "Record that `jot` was done at `now`. A reminder that repeats stays open, put off to its next time."
  @spec done(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def done(%__MODULE__{every: nil} = jot, now), do: put(jot, done_at: DateTime.truncate(now, :second))
  def done(%__MODULE__{every: every} = jot, now), do: put_off(jot, Server.Home.Clock.next(jot.due_at, every, now))

  @doc "Put `jot` off to `due_at`: a reminder from then on (a to-do too), told afresh at that time."
  @spec put_off(%__MODULE__{}, DateTime.t()) :: %__MODULE__{}
  def put_off(%__MODULE__{} = jot, due_at),
    do: put(jot, kind: "reminder", due_at: DateTime.truncate(due_at, :second), nudged_at: nil, nudges: 0)

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

  defp put(jot, changes), do: jot |> Ecto.Changeset.change(changes) |> Repo.update!()
end
