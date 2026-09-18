defmodule Server.OperatorConfig do
  @moduledoc """
  The operator's **runtime settings file**, read side — the knobs the cockpit exposes in-app
  (the SETTINGS panel + verbs) so changing them never means editing Elixir source or re-running
  `home:switch`. A plain JSON map at `~/.config/console/config.json` (override with
  `config :server, :operator_config_path`, which the test envs point away from the real home).
  The console writes it (`Console.Config`); the server reads it here, because the profile
  registry and the staffing pass moved to the server (one-brain piece B, slice 2) and a
  coworker the SERVICE spawns must wear the same overrides one the cockpit spawns does.

  Shape (all keys optional — absent means "the compiled default wins"):

      {
        "coworkers": {"tlon": {"provider": "anthropic", "model": "claude-opus-4-8", "thinking": "medium", "yolo": true}},
        "environment": "home",
        "max_leaves": 6
      }

  Best-effort on read: a missing or corrupt file is just "no overrides".
  """

  @doc "The settings file path (`config :server, :operator_config_path` override, else ~/.config/console/config.json)."
  @spec path() :: String.t()
  def path do
    Application.get_env(:server, :operator_config_path) ||
      Path.join([xdg_config_home(), "console", "config.json"])
  end

  @doc "The whole settings map — `%{}` when the file is absent or unreadable (defaults win)."
  @spec read(String.t()) :: map()
  def read(path \\ path()) do
    with {:ok, body} <- File.read(path), {:ok, %{} = map} <- Jason.decode(body) do
      map
    else
      _ -> %{}
    end
  end

  @doc """
  The operator's model override for a coworker profile, or nil (compiled default wins).
  Returned in the `Server.Profile.model` shape: `%{provider, model, thinking}` with atom keys.
  """
  @spec coworker_model(String.t(), String.t()) :: map() | nil
  def coworker_model(profile, path \\ path()) do
    case get_in(read(path), ["coworkers", profile]) do
      %{"provider" => prov, "model" => model} = m ->
        %{provider: prov, model: model, thinking: m["thinking"] || "medium"}

      _ ->
        nil
    end
  end

  @doc """
  The operator's permission-policy override for a coworker: `true` (yolo — auto-approve asks) or
  `false` (ask), or nil (compiled default wins). `false` is a real override, distinct from unset.
  """
  @spec coworker_yolo(String.t(), String.t()) :: boolean() | nil
  def coworker_yolo(profile, path \\ path()) do
    case get_in(read(path), ["coworkers", profile, "yolo"]) do
      b when is_boolean(b) -> b
      _ -> nil
    end
  end

  @doc """
  Where the machine is — the harness-binding signal (per-thread-agents Slice D): `"home"`
  (personal Anthropic subscription; anthropic-model coworkers must ride the official
  `claude_code` harness — the ToS rule) or `"work"` (API-billed; pi may drive any provider).
  Precedence: `TLON_ENV` env var > the config file's `"environment"` key > `"home"`.
  """
  @spec environment(String.t()) :: String.t()
  def environment(path \\ path()) do
    System.get_env("TLON_ENV") || environment_key(read(path)) || "home"
  end

  defp environment_key(%{"environment" => env}) when is_binary(env) and env != "", do: env
  defp environment_key(_map), do: nil

  @doc """
  The maximum number of CONCURRENT leaf sessions the staffing pass will spawn (the runaway-fleet
  circuit breaker — every leaf is a live harness, most of them on the Claude subscription at
  home). Config key `"max_leaves"`; default #{6}. Threads staffed past the cap stay open and
  keep their lead; they just wait ("parked") until a seat frees.
  """
  @spec max_leaves(String.t()) :: pos_integer()
  def max_leaves(path \\ path()) do
    case read(path) do
      %{"max_leaves" => n} when is_integer(n) and n > 0 -> n
      _ -> 6
    end
  end

  defp xdg_config_home do
    System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")
  end
end
