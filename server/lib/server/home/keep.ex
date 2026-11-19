defmodule Server.Home.Keep do
  @moduledoc """
  Where the home keeps a value that is more than a slot (`Server.Home.Slot`) and must outlive a
  restart: one row per name, `body` its text. The pets' batch (`Server.Home.Pets`) is kept here as
  JSON.
  """
  use Ecto.Schema

  alias Server.Repo

  @primary_key {:name, :string, autogenerate: false}
  schema "home_keep" do
    field :body, :string
  end

  @doc "The text kept under `name`, nil when none was kept."
  @spec get(String.t()) :: String.t() | nil
  def get(name) do
    case Repo.get(__MODULE__, name) do
      %__MODULE__{body: body} -> body
      nil -> nil
    end
  end

  @doc "Keep `body` under `name`, in place of what was there."
  @spec put(String.t(), String.t()) :: :ok
  def put(name, body) when is_binary(body) do
    Repo.insert!(%__MODULE__{name: name, body: body}, on_conflict: {:replace, [:body]}, conflict_target: :name)
    :ok
  end
end
