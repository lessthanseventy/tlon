defmodule Server.Ticket do
  @moduledoc """
  A ticket (2026-08-30): a first-class, workspace-scoped issue — the lightweight terminal
  tracker (GitHub-Issues-light, no epics/sprints/ceremony). 2-second capture that does NOT
  spin up a thread; it **promotes** into one (`promoted_thread_id`) when work starts. Distinct
  from `Server.Issue` (a blocker raised *on* a thread).

  `status` (backlog|todo|doing|done) and `priority` (low|med|high) are DB-CHECK'd closed sets,
  re-validated app-side because tickets arrive from MCP callers (a bad value should fail as a
  changeset, not raise). `labels` is a JSON list. `backend` is `local` by default; an
  adapter-backed workspace stamps `external_key`/`external_url` (the Jira/GitHub follow-on).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(backlog todo doing done)
  @priorities ~w(low med high)

  schema "ticket" do
    field :title, :string
    field :body, :string, default: ""
    field :status, :string, default: "backlog"
    field :priority, :string, default: "med"
    field :labels, Server.JSONColumn
    field :assignee, :string
    field :backend, :string, default: "local"
    field :external_key, :string
    field :external_url, :string
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime
    belongs_to :workspace, Server.Workspace
    belongs_to :project, Server.Project
    belongs_to :promoted_thread, Server.Thread
  end

  @mutable [:title, :body, :status, :priority, :labels, :assignee, :project_id]

  @doc "File a ticket. `workspace_id` + `title` required; status defaults to `backlog`. Stamps both times."
  def file_changeset(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %__MODULE__{}
    |> cast(attrs, [:workspace_id, :backend, :external_key, :external_url | @mutable])
    |> validate_required([:workspace_id, :title])
    |> validate_sets()
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:project_id)
    |> put_change(:created_at, now)
    |> put_change(:updated_at, now)
  end

  @doc "Update a ticket's mutable fields (status/priority/title/body/labels/assignee/project). Re-stamps `updated_at`."
  def update_changeset(%__MODULE__{} = ticket, attrs) do
    ticket
    |> cast(attrs, @mutable)
    |> validate_required([:title])
    |> validate_sets()
    |> put_change(:updated_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "Link a ticket to the thread it became, and move it to `doing`."
  def promote_changeset(%__MODULE__{} = ticket, thread_id) do
    ticket
    |> change(promoted_thread_id: thread_id, status: "doing")
    |> put_change(:updated_at, DateTime.truncate(DateTime.utc_now(), :second))
    |> foreign_key_constraint(:promoted_thread_id)
  end

  defp validate_sets(changeset) do
    changeset
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
  end
end
