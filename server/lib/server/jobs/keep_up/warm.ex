defmodule Server.Jobs.KeepUp.Warm do
  @moduledoc """
  What `Server.Jobs.KeepUp` remembers across restarts about each project's test build: one row per
  `keep_up:warm:<dir>`, `body` the tip's outcome (`"<sha> ok"`, `"<sha> skip"` or
  `"<sha> failed\\n<lines>"`).
  """
  use Ecto.Schema

  alias Server.Repo

  @primary_key {:name, :string, autogenerate: false}
  schema "keep_up_warm" do
    field :body, :string
  end

  @doc "The outcome kept under `name`, nil when none was kept."
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
