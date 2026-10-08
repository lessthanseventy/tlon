defmodule Server.Schedule do
  @moduledoc """
  Something the operator scheduled (`Server.Schedules`): `kind` `agent` (a coworker is given
  `body` as a prompt), `workline` (one opens with `body` as its first words) or `script` (`body`
  runs as a shell command in `dir`, else the workspace's first repo). It fires on `cron` (five
  fields, or `@daily` and kin, on the server's local clock) or once `at` — exactly one, which
  the db CHECKs. `standing`: every firing lands in one thread (`thread_id`, opened by the first)
  instead of a fresh one each time; a script's output is posted there too. `last_run_at` stamps
  the last firing; when the next one falls is computed, never stored.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "schedule" do
    field :kind, :string
    field :title, :string
    field :body, :string
    field :cron, :string
    field :at, :utc_datetime
    field :agent, :string
    field :standing, :boolean, default: false
    field :dir, :string
    field :enabled, :boolean, default: true
    field :last_run_at, :utc_datetime
    field :created_at, :utc_datetime
    belongs_to :workspace, Server.Workspace
    belongs_to :thread, Server.Thread
  end

  @kinds ~w(agent workline script)
  @mutable [:title, :body, :cron, :at, :agent, :standing, :dir, :enabled]

  @doc "A new schedule: workspace, kind, title, body, and one of cron/at."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:workspace_id, :kind | @mutable])
    |> validate_required([:workspace_id, :kind, :title, :body])
    |> validate_inclusion(:kind, @kinds)
    |> validate_when()
    |> foreign_key_constraint(:workspace_id)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "A change to what, when, who or whether it runs."
  def update_changeset(%__MODULE__{} = s, attrs) do
    s |> cast(attrs, @mutable) |> validate_required([:title, :body]) |> validate_when()
  end

  defp validate_when(cs) do
    case {get_field(cs, :cron), get_field(cs, :at)} do
      {nil, nil} ->
        add_error(cs, :cron, "a schedule needs a cron or a time")

      {c, a} when not is_nil(c) and not is_nil(a) ->
        add_error(cs, :cron, "a cron or a time, not both")

      {nil, _at} ->
        cs

      {c, nil} ->
        case Oban.Cron.Expression.parse(c) do
          {:ok, %{reboot?: true}} -> add_error(cs, :cron, "needs a next time: @reboot has none")
          {:ok, _} -> cs
          _ -> add_error(cs, :cron, "not a cron: #{c}")
        end
    end
  end
end
