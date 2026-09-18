defmodule Console.Config do
  @moduledoc """
  The operator's **runtime settings file**, write side — the knobs the cockpit exposes in-app
  (the SETTINGS panel + verbs) so changing them never means editing Elixir source or re-running
  `home:switch`. The reads live in `Server.OperatorConfig` (one-brain piece B, slice 2: the
  profile registry the file overrides moved to the server); the writers stay here because only
  the cockpit has a SETTINGS panel. Writes are atomic (tmp + rename) so a crash mid-write can't
  truncate the file.
  """

  alias Server.OperatorConfig

  @doc "The operator's server author handle — what the cockpit posts as (`config :server, :operator`)."
  @spec operator() :: String.t()
  def operator, do: Application.get_env(:server, :operator, "andrew")

  defdelegate path(), to: OperatorConfig
  defdelegate read(path \\ OperatorConfig.path()), to: OperatorConfig
  defdelegate coworker_model(profile, path \\ OperatorConfig.path()), to: OperatorConfig
  defdelegate coworker_yolo(profile, path \\ OperatorConfig.path()), to: OperatorConfig
  defdelegate environment(path \\ OperatorConfig.path()), to: OperatorConfig
  defdelegate max_leaves(path \\ OperatorConfig.path()), to: OperatorConfig

  @doc "Persist a coworker profile's model override (`%{provider, model, thinking}`)."
  @spec put_coworker_model(String.t(), map(), String.t()) :: :ok
  def put_coworker_model(profile, %{provider: prov, model: model, thinking: think}, path \\ path()) do
    merge_coworker(profile, %{"provider" => prov, "model" => model, "thinking" => think}, path)
  end

  @doc "Persist a coworker profile's yolo (permission-policy) override without disturbing its model."
  @spec put_coworker_yolo(String.t(), boolean(), String.t()) :: :ok
  def put_coworker_yolo(profile, yolo, path \\ path()) when is_boolean(yolo) do
    merge_coworker(profile, %{"yolo" => yolo}, path)
  end

  defp merge_coworker(profile, fields, path) do
    map = read(path)
    coworkers = Map.get(map, "coworkers", %{})
    entry = Map.merge(Map.get(coworkers, profile, %{}), fields)
    map |> Map.put("coworkers", Map.put(coworkers, profile, entry)) |> write!(path)
  end

  @doc """
  Write the settings map atomically (tmp + rename), so a crash mid-write cannot truncate it.
  """
  def write!(map, path) do
    File.mkdir_p!(Path.dirname(path))
    tmp = path <> ".tmp"
    File.write!(tmp, Jason.encode!(map, pretty: true) <> "\n")
    File.rename!(tmp, path)
    :ok
  end
end
