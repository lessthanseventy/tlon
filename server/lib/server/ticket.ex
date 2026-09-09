defmodule Server.Ticket do
  @moduledoc """
  A ticket (2026-08-30): a first-class, workspace-scoped issue — the lightweight terminal
  tracker (GitHub-Issues-light, no epics/sprints/ceremony). 2-second capture that does NOT
  spin up a thread; it **promotes** into one when work starts. Distinct from `Server.Issue`
  (a blocker raised *on* a thread).

  Since UX slice 4 a ticket is no longer an island: `Server.TicketLink` ties it to other tickets
  (`blocks`/`relates`/`duplicates`/`parent`) and `Server.TicketThread` to threads
  (`promoted`/`relates`) — the many-to-many that replaced the single `promoted_thread_id` column,
  so promotion is one KIND of tie rather than a second mechanism. `sort` orders it within its
  status column (the board's order, persisted); `closed_at` stamps when it reached `done`.

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
    field :sort, :integer, default: 0
    field :closed_at, :utc_datetime
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime
    belongs_to :workspace, Server.Workspace
    belongs_to :project, Server.Project
    has_many :ticket_links, Server.TicketLink, foreign_key: :from_id
    has_many :ticket_threads, Server.TicketThread
  end

  @mutable [:title, :body, :status, :priority, :labels, :assignee, :project_id, :sort]

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
    |> stamp_closed()
    |> put_change(:updated_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc """
  Move a ticket to `doing` because work started on it. The TIE to the thread is a
  `Server.TicketThread` row written alongside this by `Server.Tickets.promote/2` — a ticket can be
  tied to several threads, so it is not a field here.
  """
  def start_changeset(%__MODULE__{} = ticket) do
    ticket
    |> change(status: "doing")
    |> stamp_closed()
    |> put_change(:updated_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  defp validate_sets(changeset) do
    changeset
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
  end

  # `closed_at` follows `status` rather than being set by hand: reaching `done` stamps it, leaving
  # `done` clears it. One field, one source, no way for "closed" and "when" to disagree.
  defp stamp_closed(changeset) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    case {get_field(changeset, :status), get_field(changeset, :closed_at)} do
      {"done", nil} -> put_change(changeset, :closed_at, now)
      {"done", _already} -> changeset
      {_open, nil} -> changeset
      {_open, _was} -> put_change(changeset, :closed_at, nil)
    end
  end
end
