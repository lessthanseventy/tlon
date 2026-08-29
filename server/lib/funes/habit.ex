defmodule Server.Habit do
  @moduledoc """
  A HABIT — how the agent should WORK with the operator. The third axis beside FACTS
  (what's true — memory) and skills (how to do a task — procedures): a working preference
  ("run `mise run check` before proposing a commit", "prefer the Claude bucket"), *agent-
  proposed and human-approved*.

  Distinct from a `stated` constraint (`Server.Fact` provenance='stated'), which quotes the
  operator's OWN words: a habit is the machine's suggestion, promoted into the always-loaded
  set only by his approval. It lands `pending`; `approve_habit` flips it `approved` (stamping
  `approved_at`) and it then loads every session via `Dossier.approved_habits/0` — machine-
  wide, beside the constraints. `state` open/approved/rejected is the DB's CHECK alone (§10);
  `approved_at` is present FROM BIRTH — the missing completion time that bit `issue` must not
  recur. `source_thread_id` records WHICH thread proposed it (provenance, nullable), never scope.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "habit" do
    field :text, :string
    field :rationale, :string
    field :state, :string, default: "pending"
    field :proposed_by, :string
    field :approved_at, :utc_datetime
    field :created_at, :utc_datetime
    belongs_to :source_thread, Server.Thread, foreign_key: :source_thread_id
  end

  @doc """
  Propose a habit. `text` and `proposed_by` required; it opens `pending` (`state` is not
  caller-settable — a habit is not born approved). `rationale` and `source_thread_id`
  (the proposing thread, for provenance) are optional.
  """
  def propose_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:text, :rationale, :proposed_by, :source_thread_id])
    |> validate_required([:text, :proposed_by])
    |> put_change(:state, "pending")
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc """
  Approve a habit — state approved, `approved_at` stamped now (idempotent on the first
  stamp). The operator's act; the closed set is the DB's CHECK alone (§10).
  """
  def approve_changeset(%__MODULE__{} = habit) do
    habit
    |> change(state: "approved")
    |> put_change(:approved_at, habit.approved_at || DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "Reject a habit — the operator declines it. It never joins the always-loaded set."
  def reject_changeset(%__MODULE__{} = habit) do
    change(habit, state: "rejected")
  end
end
