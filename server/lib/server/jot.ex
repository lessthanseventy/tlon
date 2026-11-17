defmodule Server.Jot do
  @moduledoc """
  Something the operator sent the home's inbox from away from the machine, kept exactly as it came:
  `via` the messenger it arrived through, `external_id` that messenger's own id for it, so one
  delivered twice is one jot. Nothing is filed or read here: a jot is the raw capture.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Server.Repo

  schema "jot" do
    field :via, :string
    field :external_id, :integer
    field :body, :string
    field :received_at, :utc_datetime
  end

  @doc "Keep `body`: `{:ok, jot}`, or `:seen` when `via` already delivered `external_id`."
  @spec take(String.t(), integer(), String.t()) :: {:ok, %__MODULE__{}} | :seen
  def take(via, external_id, body) do
    jot = %__MODULE__{
      via: via,
      external_id: external_id,
      body: body,
      received_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    case Repo.insert!(jot, on_conflict: :nothing, conflict_target: [:via, :external_id]) do
      %__MODULE__{id: nil} -> :seen
      kept -> {:ok, kept}
    end
  end

  @doc "The newest `limit` jots that came through `via`, newest first."
  @spec recent(String.t(), pos_integer()) :: [%__MODULE__{}]
  def recent(via, limit),
    do: Repo.all(from(j in __MODULE__, where: j.via == ^via, order_by: [desc: j.external_id], limit: ^limit))

  @doc "The highest `external_id` kept from `via`, nil when it has delivered nothing."
  @spec cursor(String.t()) :: integer() | nil
  def cursor(via), do: Repo.one(from(j in __MODULE__, where: j.via == ^via, select: max(j.external_id)))
end
