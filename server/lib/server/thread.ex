defmodule Server.Thread do
  @moduledoc """
  The atom of work (console §2). A subject promoted to a first-class row; `message`
  and, later, the dossier tables (`fact`/`event`/`issue`) hang off it. Its `state`
  is a closed set the database enforces.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "thread" do
    field :title, :string
    field :state, :string, default: "open"
    field :scope, :string, default: "project"
    field :created_at, :utc_datetime
    # A thread has 0..1 agent (console §3), staffed via Server.Staff. Nullable FK;
    # the assignment reference lives on the thread.
    belongs_to :agent, Server.Agent
    # Workline state (slice 1) — all nil on a plain thread. `stage` is the machine's position,
    # `slug` names `work/<slug>/`, `born` who authored the intent, `awaiting` the parked gate.
    field :stage, :string
    field :slug, :string
    field :born, :string
    field :awaiting, :string
    belongs_to :workspace, Server.Workspace
    # The middle tier (Workspace ▸ Project ▸ Thread, 2026-08-30). Optional/additive for now:
    # existing threads still route by `workspace_id`; new threads carry a project.
    belongs_to :project, Server.Project
    # Lead-as-manager (Slice 4D): a lead-opened CHILD thread points back at its parent, so its
    # close reports up. Nil for top-level threads. Self-referential; unlink-not-cascade (Channel).
    belongs_to :parent, Server.Thread, foreign_key: :parent_thread_id
    # the channel the thread lives in (UX slice 1b); nil in the DB means #general (see the migration)
    field :channel_id, :integer
    # the last message the memory pass extracted from (Server.Memory.TurnPass); nil = never
    field :memory_pass_last_id, :integer
  end

  @doc ~s{A new thread, opened now. Title is required; state is not caller-settable. `scope`
  defaults to `"project"`; the Tlön machine-coworker path opens with `"machine"` so the
  project surfaces (chorus / open_threads) can filter it out — see the thread_scope migration.}
  def open_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:title, :scope, :workspace_id, :project_id, :parent_thread_id, :agent_id, :channel_id])
    |> validate_required([:title])
    |> put_change(:state, "open")
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc """
  Move a thread to a new state. The closed set (open | closed) is enforced by the
  database CHECK alone — not mirrored here, the same single-source rule the FK
  follows: an invalid state is refused by SQLite (it raises), never by a second
  guard that could drift from the DB's.
  """
  def state_changeset(thread, state) do
    change(thread, state: state)
  end

  @doc ~s{A new WORKLINE thread (slice 1): opens at stage "intent", machine-scoped by default.
  `attrs` is atom-keyed (internal callers only). `born` defaults to "operator"; the Maintain
  back-edge opens with "machine" and gates. A taken slug is a UNIQUE refusal, as a changeset.}
  def workline_changeset(attrs) do
    # `stage` defaults to "intent" but is caller-settable for any-stage entry (Slice 4D); the
    # openable set is enforced upstream in `Server.Workline.open` (single source: it owns the ring).
    %__MODULE__{}
    |> cast(Map.merge(%{born: "operator", scope: "machine", stage: "intent"}, attrs), [
      :title,
      :scope,
      :slug,
      :born,
      :workspace_id,
      :stage
    ])
    |> validate_required([:title, :slug, :stage])
    |> validate_inclusion(:born, ["operator", "machine"])
    # The slug names filesystem paths (work/<slug>/, branch, lock files) — a separator or
    # dot-segment would traverse out of them. Closed charset, no exceptions.
    |> validate_format(:slug, ~r/\A[a-z0-9][a-z0-9-]*\z/)
    |> unique_constraint(:slug)
    |> put_change(:state, "open")
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "Flip workline machinery — `stage` and/or `awaiting` — on an existing thread."
  def workline_stage_changeset(thread, changes) do
    change(thread, Map.take(changes, [:stage, :awaiting]))
  end

  @doc ~s{Promote a plain thread INTO the stage machine (reshape slice B): stage + slug land
  together. Same slug charset rule as workline_changeset — it names work/<slug>/ paths.}
  def promote_changeset(thread, stage, slug) do
    thread
    |> change(stage: stage, slug: slug)
    |> validate_format(:slug, ~r/\A[a-z0-9][a-z0-9-]*\z/)
    |> unique_constraint(:slug)
  end
end
