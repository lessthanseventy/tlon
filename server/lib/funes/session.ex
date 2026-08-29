defmodule Server.Session do
  @moduledoc """
  The ephemeral instance of an agent (console §3): it runs in a pane, on an engine,
  on one thread, and it compacts and dies (§10). It references an `agent` and a
  `thread`. `pane_ref` is §2's one seam — an OPAQUE handle to the pane, never
  a cached copy of the pane's properties; liveness is asked of the arbiter
  live, never stored. `ended_at` is the only lifecycle stored: NULL means a
  candidate to jump into.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "session" do
    field :pane_ref, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    # When the session last ran a turn (console §3b). Drives warmth: idle past the
    # cache window (~1h) is cold, and the switchboard must not wake a cold session.
    # The switchboard bumps this as the session acts; a fresh session starts warm.
    field :last_active_at, :utc_datetime
    belongs_to :agent, Server.Agent
    belongs_to :thread, Server.Thread
  end

  @doc """
  Start a session for an agent on a thread. Both references are required; the FKs
  themselves are the DB's guard (§10) — an orphan is refused by SQLite, so it
  raises rather than returning a changeset. `pane_ref` is optional and opaque.
  """
  def start_changeset(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %__MODULE__{}
    |> cast(attrs, [:agent_id, :thread_id, :pane_ref])
    |> validate_required([:agent_id, :thread_id])
    |> put_change(:started_at, now)
    |> put_change(:last_active_at, now)
  end

  @doc "Stamp a session ended, now. Sessions die; you brief a new one (§3b)."
  def end_changeset(session) do
    change(session, ended_at: DateTime.truncate(DateTime.utc_now(), :second))
  end
end
