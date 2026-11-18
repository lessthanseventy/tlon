defmodule Server.Home.Slot do
  @moduledoc """
  Where the home keeps its place in what it says on a schedule (the daily list, the weekly review):
  one row per schedule, `slot` the date of the last slot said (`Server.Home.Clock.slot/3`) and
  `setting` the schedule's settings it was kept under, so a slot counted before a setting changed is
  not trusted after (`Server.Home.Clock.resume/2`). Written when a slot is said, read when the inbox
  starts, so a restart neither loses a slot nor says it twice.
  """
  use Ecto.Schema

  alias Server.Repo

  @primary_key {:name, :string, autogenerate: false}
  schema "home_slot" do
    field :slot, :date
    field :setting, :string
  end

  @doc "The last slot said for `name` and the setting it was kept under, nil when none was kept."
  @spec get(String.t()) :: {Date.t(), String.t()} | nil
  def get(name) do
    case Repo.get(__MODULE__, name) do
      %__MODULE__{slot: slot, setting: setting} -> {slot, setting}
      nil -> nil
    end
  end

  @doc "Keep `slot` as the last said for `name`, under `setting`."
  @spec put(String.t(), Date.t(), String.t()) :: :ok
  def put(name, %Date{} = slot, setting) do
    Repo.insert!(%__MODULE__{name: name, slot: slot, setting: setting},
      on_conflict: {:replace, [:slot, :setting]},
      conflict_target: :name
    )

    :ok
  end
end
