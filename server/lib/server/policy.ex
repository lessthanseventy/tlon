defmodule Server.Policy do
  @moduledoc """
  What one coworker may do in one workspace: allowed paths, network, shell, the ask-vs-allow
  default, and the driver model. Keyed workspace × agent — the same coworker is trusted
  differently in a scratch workspace than in the one that deploys.

  Every field is nullable and nil means INHERIT: the nix-owned capability (the pi-sandbox
  allowlist, the permission-system deny floor) decides, and a value here is the operator being
  more specific. Capabilities are nix, compositions are data, disjoint — so a row of nils is
  indistinguishable from no row.

  `ask_default: "allow"` is what SETTINGS called yolo. The layer that enforces it keeps deny
  terminal, so the catastrophic-command and secret-path denies hold regardless.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "workspace_policy" do
    field :workspace_id, :integer
    field :agent_id, :integer
    field :allowed_paths, Server.JSONColumn
    field :network, :string
    field :shell, :string
    field :ask_default, :string
    field :model, Server.JSONColumn
    field :created_at, :utc_datetime
  end

  @type t :: %__MODULE__{}

  @mutable [:allowed_paths, :network, :shell, :ask_default, :model]

  @doc "The knobs a policy carries — what the CONFIG pane may set."
  @spec knobs() :: [atom()]
  def knobs, do: @mutable

  @doc """
  Changeset for a (workspace, agent) policy. The closed sets on `network`/`shell`/`ask_default`
  are DB CHECKs, not mirrored here — a bad value raises at insert, same as `workspace.type`.
  """
  def changeset(%__MODULE__{} = policy, attrs) do
    policy
    |> cast(attrs, [:workspace_id, :agent_id | @mutable])
    |> validate_required([:workspace_id, :agent_id])
    |> unique_constraint([:workspace_id, :agent_id])
    |> put_new_created_at()
  end

  defp put_new_created_at(%Ecto.Changeset{data: %__MODULE__{created_at: nil}} = cs),
    do: put_change(cs, :created_at, DateTime.truncate(DateTime.utc_now(), :second))

  defp put_new_created_at(cs), do: cs

  @doc "True when nothing is set — an empty policy is the same as none, so callers can drop it."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = p), do: Enum.all?(@mutable, &is_nil(Map.get(p, &1)))
end
