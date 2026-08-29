defmodule Server.Todo do
  @moduledoc """
  A plan step, thread-scoped (pi doc §5 slice 3, the activity axis). `done_at` NULL is
  open, a timestamp is done — and the column is present FROM BIRTH, the missing
  completion time that bit `issue` must not recur. Order is insertion order (`id`); there is no
  order column — reordering is a later verb only if evidence demands it, never a field
  guessed at now.

  `complete_todo` emits no event: DONE is a merged VIEW (completed todos by their
  `done_at`, plus `work_landed` events), never a copy. `record_done` is the separate,
  evidence-bearing verb for judgement-worthy outcomes.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "todo" do
    field :text, :string
    field :done_at, :utc_datetime
    field :created_at, :utc_datetime
    belongs_to :thread, Server.Thread
  end

  @doc "Add an open todo. `text` and `thread_id` required; it opens open (`done_at` NULL)."
  def add_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:thread_id, :text])
    |> validate_required([:thread_id, :text])
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "Mark a todo done — stamp `done_at` now. Completing keeps the first stamp idempotent."
  def done_changeset(%__MODULE__{} = todo) do
    change(todo, done_at: todo.done_at || DateTime.truncate(DateTime.utc_now(), :second))
  end
end
