defmodule Server.Proposal do
  @moduledoc """
  Something a source (GitHub, later Jira, Slack, mail) suggests the operator might want on their
  list: `text` is what it would become, `why` one short line of where it came from, `kind` `"todo"`
  or `"waiting"` (`who` owes it), `url` where to look. `{source, key}` is the source's own stable id
  for it, unique: offering it again never makes a second one and never opens one the operator
  took or dismissed. Nothing a source offers is filed by itself unless its kind is one the source is
  trusted to file (`offer/5`: a waiting-on is a fact about what is owed, not an ask); a taken
  proposal is a to-do or a waiting-on (`Server.Jot`), its `jot_id` the link back.

  A source can say keys are gone (`resolve/4`): an open proposal for one is withdrawn silently; a
  to-do taken from one is left alone; a waiting-on taken from one is marked done and kept as
  `resolved_at` with `done_text` (how it is said in the next list, `settled/0`).
  """
  use Ecto.Schema

  import Ecto.Query

  alias Server.Jot
  alias Server.Repo

  @type t :: %__MODULE__{}

  schema "home_proposal" do
    field :source, :string
    field :key, :string
    field :text, :string
    field :why, :string
    field :kind, :string
    field :who, :string
    field :url, :string
    field :state, Ecto.Enum, values: [:open, :taken, :dismissed], default: :open
    field :jot_id, :integer
    field :done_text, :string
    field :resolved_at, :utc_datetime
    field :resolved_said_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @attrs [:key, :text, :why, :kind, :who, :url, :done_text]

  @doc "The open proposals, oldest first."
  @spec open() :: [t()]
  def open, do: Repo.all(from(p in __MODULE__, where: p.state == :open, order_by: p.id))

  @doc "The open proposal `id`, nil when it is none or was taken or dismissed."
  @spec open(integer()) :: t() | nil
  def open(id), do: Repo.one(from(p in __MODULE__, where: p.id == ^id and p.state == :open))

  @doc "The keys of `source` that still count: open, or a waiting-on taken and not yet resolved."
  @spec live_keys(String.t()) :: [String.t()]
  def live_keys(source) do
    Repo.all(
      from(p in __MODULE__,
        where: p.source == ^source,
        where: p.state == :open or (p.state == :taken and p.kind == "waiting" and is_nil(p.resolved_at)),
        select: p.key
      )
    )
  end

  @doc """
  Offer `proposals` (maps of `key`, `text`, `kind` and optionally `why`, `who`, `url`, `done_text`)
  from `source` at `now`, for the operator `via`. A key already known is left as it is, in whatever
  state. An open one whose kind is in `auto` is taken at once. Nothing is said to anyone.
  """
  @spec offer(String.t(), String.t(), [map()], DateTime.t(), [String.t()]) :: :ok
  def offer(via, source, proposals, now, auto) do
    for attrs <- proposals do
      attrs = attrs |> Map.take(@attrs) |> Map.put(:source, source)
      %{key: key, kind: kind} = attrs
      true = kind in ["todo", "waiting"]

      Repo.insert!(struct(__MODULE__, attrs), on_conflict: :nothing, conflict_target: [:source, :key])

      row = Repo.get_by!(__MODULE__, source: source, key: key)
      if row.state == :open and kind in auto, do: take_row(via, row, now)
    end

    :ok
  end

  @doc """
  Say `keys` of `source` are gone at `now`. Open proposals for them are withdrawn; a waiting-on taken
  from one is done (and `resolved_at` kept); anything else taken is left alone.
  """
  @spec resolve(String.t(), [String.t()], DateTime.t()) :: :ok
  def resolve(_source, [], _now), do: :ok

  def resolve(source, keys, now) do
    Repo.delete_all(from(p in __MODULE__, where: p.source == ^source and p.key in ^keys and p.state == :open))

    for %__MODULE__{} = row <-
          Repo.all(
            from(p in __MODULE__,
              where: p.source == ^source and p.key in ^keys and p.state == :taken and p.kind == "waiting",
              where: is_nil(p.resolved_at)
            )
          ) do
      with %Jot{done_at: nil, dropped_at: nil} = jot <- row.jot_id && Jot.get(row.jot_id), do: Jot.done(jot, now)
      row |> Ecto.Changeset.change(resolved_at: DateTime.truncate(now, :second)) |> Repo.update!()
    end

    :ok
  end

  @doc "Take the open proposal `id` at `now`: filed as a to-do or a waiting-on for `via`. `{:ok, proposal}`, `:not_found`."
  @spec take(String.t(), integer(), DateTime.t()) :: {:ok, t()} | :not_found
  def take(via, id, now) do
    case open(id) do
      nil -> :not_found
      row -> {:ok, take_row(via, row, now)}
    end
  end

  @doc "Dismiss the open proposal `id`: final for its key. `{:ok, proposal}`, `:not_found`."
  @spec dismiss(integer()) :: {:ok, t()} | :not_found
  def dismiss(id) do
    case open(id) do
      nil -> :not_found
      row -> {:ok, row |> Ecto.Changeset.change(state: :dismissed) |> Repo.update!()}
    end
  end

  @doc """
  The waiting-ons taken from proposals whose source has since resolved them and the operator has not
  been told, oldest first; with `since`, those told at or after it too (an alert that stays up).
  """
  @spec settled(DateTime.t() | nil) :: [t()]
  def settled(since \\ nil) do
    told = if since, do: dynamic([p], p.resolved_said_at >= ^DateTime.truncate(since, :second)), else: false

    Repo.all(
      from(p in __MODULE__,
        where: p.state == :taken and not is_nil(p.resolved_at),
        where: is_nil(p.resolved_said_at) or ^told,
        order_by: [p.resolved_at, p.id]
      )
    )
  end

  @doc "Record that the operator was told the `rows` settled, at `now`: a row told before keeps its first time."
  @spec settled_said([t()], DateTime.t()) :: :ok
  def settled_said(rows, now) do
    ids = Enum.map(rows, & &1.id)

    Repo.update_all(from(p in __MODULE__, where: p.id in ^ids and is_nil(p.resolved_said_at)),
      set: [resolved_said_at: DateTime.truncate(now, :second)]
    )

    :ok
  end

  defp take_row(via, %__MODULE__{id: id} = row, now) do
    {1, _} = Repo.update_all(from(p in __MODULE__, where: p.id == ^id and p.state == :open), set: [state: :taken])
    {:ok, jot} = Jot.take(via, -System.unique_integer([:positive, :monotonic]) - System.os_time(:second), row.text)
    Jot.file(jot, reading(row), now)
    row |> Ecto.Changeset.change(state: :taken, jot_id: jot.id) |> Repo.update!()
  end

  defp reading(%__MODULE__{kind: "todo", text: text}), do: %{kind: "todo", text: text, due_at: nil}

  defp reading(%__MODULE__{kind: "waiting", text: text, who: who}),
    do: %{kind: "waiting", text: text, due_at: nil, who: who || "someone"}
end
