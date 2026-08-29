defmodule Server.Question do
  @moduledoc """
  A knowledge gap in the WORK — "does raxol support embedding?" (pi doc §5 slice 4).
  Knowing what you don't know is first-class: an open question is a marker the brief
  surfaces as UNKNOWNS beside FACTS, so a successor inherits the doubt, not just the
  conclusions. Thread-scoped, `state` open/resolved (the DB CHECKs it), and a
  `resolved_at` present FROM BIRTH — the missing completion time that bit `issue` must
  not recur. Resolvable into a fact: the `resolution` records the answer, which the
  agent then banks as a durable fact if it outlives the task.

  Distinct from `issue` (a defect in the STACK/tooling) and `todo` (a plan step) — a
  question is what the work needs to KNOW. Folding these axes together is the boundary
  erosion the slice split exists to prevent.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "question" do
    field :text, :string
    field :resolution, :string
    field :state, :string, default: "open"
    field :resolved_at, :utc_datetime
    field :created_at, :utc_datetime
    belongs_to :thread, Server.Thread
  end

  @doc "Raise a question. `text` and `thread_id` required; it opens open (`state` is not caller-settable)."
  def raise_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:thread_id, :text])
    |> validate_required([:thread_id, :text])
    |> put_change(:state, "open")
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc """
  Resolve a question — state resolved, `resolved_at` stamped now (idempotent on the
  first stamp), and the optional `resolution` (the answer) recorded. The closed set is
  the DB's CHECK alone (§10), never mirrored here.
  """
  def resolve_changeset(%__MODULE__{} = question, resolution) do
    question
    |> change(state: "resolved", resolution: resolution)
    |> put_change(:resolved_at, question.resolved_at || DateTime.truncate(DateTime.utc_now(), :second))
  end
end
