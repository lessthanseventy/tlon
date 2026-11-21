defmodule Server.Proposal do
  @moduledoc """
  Something a source (mail) suggests the operator might want on their
  list: `text` is what it would become, `why` one short line of where it came from, `kind` `"todo"`
  or `"waiting"` (`who` owes it), `url` where to look. `{source, key}` is the source's own stable id
  for it, unique: offering it again never makes a second one and never opens one the operator
  took or dismissed. Nothing a source offers is filed by itself unless its kind is one the source is
  trusted to file (`offer/5`: a waiting-on is a fact about what is owed, not an ask); a taken
  proposal is a to-do or a waiting-on (`Server.Jot`), its `jot_id` the link back.

  A source can say keys are gone (`resolve/3`): an open proposal for one is withdrawn silently; a
  to-do taken from one is left alone; a waiting-on taken from one is marked done and kept as
  `resolved_at` with `done_text` (how it is said in the next list, `settled/1`), or, when the source
  says to `:drop` it, closed as dropped and never said.
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

  @doc "The proposals of `source` that still count: open, or a waiting-on taken and not yet resolved."
  @spec live(String.t()) :: [t()]
  def live(source) do
    Repo.all(
      from(p in __MODULE__,
        where: p.source == ^source,
        where: p.state == :open or (p.state == :taken and p.kind == "waiting" and is_nil(p.resolved_at)),
        order_by: p.id
      )
    )
  end

  @doc "The keys of `source`'s proposals that were taken or dismissed."
  @spec answered_keys(String.t()) :: [String.t()]
  def answered_keys(source) do
    Repo.all(from(p in __MODULE__, where: p.source == ^source and p.state in [:taken, :dismissed], select: p.key))
  end

  @doc "The keys of `live/1`."
  @spec live_keys(String.t()) :: [String.t()]
  def live_keys(source), do: source |> live() |> Enum.map(& &1.key)

  @doc """
  Offer `proposals` (maps of `key`, `text`, `kind` and optionally `why`, `who`, `url`, `done_text`)
  from `source` at `now`, for the operator `via`. A key already known is left as it is, in whatever
  state. An open one whose kind is in `auto` is taken at once; the keys of those that could not be
  (`take/3` refused them) are answered, so a source can say so. Nothing is said to anyone.
  """
  @spec offer(String.t(), String.t(), [map()], DateTime.t(), [String.t()]) :: [String.t()]
  def offer(via, source, proposals, now, auto) do
    Enum.reverse(
      for attrs <- proposals, reduce: [] do
        refused ->
          attrs = attrs |> Map.take(@attrs) |> Map.put(:source, source)
          %{key: key, kind: kind} = attrs
          true = kind in ["todo", "waiting"]

          Repo.insert!(struct(__MODULE__, attrs), on_conflict: :nothing, conflict_target: [:source, :key])

          row = Repo.get_by!(__MODULE__, source: source, key: key)

          if row.state == :open and kind in auto and take_row(via, row.id, now) == {:error, :seen},
            do: [key | refused],
            else: refused
      end
    )
  end

  @doc """
  Say `entries` of `source` are gone at `now`: a key, or `{key, how}` with `how` the text its
  waiting-on is said by (replacing `done_text`) or `:drop` to close it without a word. Open proposals
  for them are withdrawn; a waiting-on taken from one is done (and `resolved_at` kept); anything else
  taken is left alone.
  """
  @spec resolve(String.t(), [String.t() | {String.t(), String.t() | :drop}], DateTime.t()) :: :ok
  def resolve(_source, [], _now), do: :ok

  def resolve(source, entries, now) do
    how =
      Map.new(entries, fn
        {key, how} -> {key, how}
        key -> {key, nil}
      end)

    keys = Map.keys(how)
    Repo.delete_all(from(p in __MODULE__, where: p.source == ^source and p.key in ^keys and p.state == :open))

    for %__MODULE__{} = row <-
          Repo.all(
            from(p in __MODULE__,
              where: p.source == ^source and p.key in ^keys and p.state == :taken and p.kind == "waiting",
              where: is_nil(p.resolved_at)
            )
          ) do
      close(row, how[row.key], now)
    end

    :ok
  end

  @doc """
  Take the open proposal `id` at `now`: filed as a to-do or a waiting-on for `via`, both or neither.
  `{:ok, proposal}`, `:not_found` when it is not open, `{:error, :seen}` when its jot's id is taken
  (the proposal stays open).
  """
  @spec take(String.t(), integer(), DateTime.t()) :: {:ok, t()} | :not_found | {:error, :seen}
  def take(via, id, now) do
    case take_row(via, id, now) do
      {:error, :not_found} -> :not_found
      taken -> taken
    end
  end

  @doc "The delivery id the jot of `proposal` is kept under: one per proposal, apart from a messenger's and a form's."
  @spec external_id(t()) :: integer()
  def external_id(%__MODULE__{id: id}), do: -(1_000_000_000_000 + id)

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
    unsaid = dynamic([p], is_nil(p.resolved_said_at))

    wanted =
      if since,
        do: dynamic([p], ^unsaid or p.resolved_said_at >= ^DateTime.truncate(since, :second)),
        else: unsaid

    Repo.all(
      from(p in __MODULE__,
        where: p.state == :taken and not is_nil(p.resolved_at),
        where: ^wanted,
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

  # the row is read under a lock inside the transaction, so of two takes at once the second finds it taken
  defp take_row(via, id, now) do
    Repo.transaction(fn ->
      with %__MODULE__{} = row <-
             Repo.one(from(p in __MODULE__, where: p.id == ^id and p.state == :open, lock: "FOR UPDATE")),
           {:ok, jot} <- Jot.take(via, external_id(row), row.text) do
        Jot.file(jot, reading(row), now)
        row |> Ecto.Changeset.change(state: :taken, jot_id: jot.id) |> Repo.update!()
      else
        nil -> Repo.rollback(:not_found)
        :seen -> Repo.rollback(:seen)
      end
    end)
  end

  defp reading(%__MODULE__{kind: "todo", text: text}), do: %{kind: "todo", text: text, due_at: nil}

  defp reading(%__MODULE__{kind: "waiting", text: text, who: who}),
    do: %{kind: "waiting", text: text, due_at: nil, who: who || "someone"}

  defp close(row, :drop, now) do
    with %Jot{done_at: nil, dropped_at: nil} = jot <- row.jot_id && Jot.get(row.jot_id), do: Jot.drop(jot, now)
    row |> Ecto.Changeset.change(state: :dismissed) |> Repo.update!()
  end

  defp close(row, text, now) do
    with %Jot{done_at: nil, dropped_at: nil} = jot <- row.jot_id && Jot.get(row.jot_id), do: Jot.done(jot, now)

    row
    |> Ecto.Changeset.change(resolved_at: DateTime.truncate(now, :second), done_text: text || row.done_text)
    |> Repo.update!()
  end
end
