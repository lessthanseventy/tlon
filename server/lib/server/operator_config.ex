defmodule Server.OperatorConfig do
  @moduledoc """
  The operator's **runtime settings file**, read side — knobs that change without editing Elixir
  source or re-running `home:switch`. A plain JSON map at `~/.config/tlon/config.json`
  (override with `config :server, :operator_config_path`, which the test envs point away from the
  real home). The operator edits it by hand; the one key written back is a switch the office TUI
  flips (`put/3`, the rest of the file kept). The profile registry and the staffing pass read it
  here, so every coworker the service spawns wears its overrides.

  Shape (all keys optional — absent means "the compiled default wins"):

      {
        "coworkers": {"tlon": {"provider": "anthropic", "model": "claude-opus-4-8", "thinking": "medium", "yolo": true}},
        "environment": "home",
        "max_leaves": 6,
        "banter": true,
        "warmth_seconds": {"ollama-cloud": 600},
        "calendars": [{"name": "work", "ics_secret": "calendar-work"}],
        "alarm_minutes": 5,
        "max_worklines": 4
      }

  `calendars` and `alarm_minutes` are `Server.Calendar`'s and `Server.Alerts`' (a meeting's alarm);
  `max_worklines` is `Server.Intake`'s cap on worklines in flight per workspace.

  Best-effort on read: a missing or corrupt file is just "no overrides".
  """

  @doc "The settings file path (`config :server, :operator_config_path` override, else ~/.config/tlon/config.json)."
  @spec path() :: String.t()
  def path do
    Application.get_env(:server, :operator_config_path) ||
      Path.join([xdg_config_home(), "tlon", "config.json"])
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

  @doc """
  Per-provider warmth windows in seconds (`"warmth_seconds": {"ollama-cloud": 600}`), for a provider
  whose prompt cache does not last the default hour; `%{}` when none are set.
  """
  @spec warmth_seconds(String.t()) :: %{String.t() => pos_integer()}
  def warmth_seconds(path \\ path()) do
    case read(path) do
      %{"warmth_seconds" => %{} = m} -> for {k, v} <- m, is_integer(v) and v > 0, into: %{}, do: {k, v}
      _ -> %{}
    end
  end

  @doc """
  Whether the office talks: its small talk (`Server.Office.Banter`) and its pets' lines
  (`Server.Office.Pets`) on the cheap model tier. On unless `"banter": false`; read on every poll,
  so a flip takes at once.
  """
  @spec banter?(String.t()) :: boolean()
  def banter?(path \\ path()), do: read(path)["banter"] != false

  @doc "Set one key in the settings file, keeping every other (the file and its directory made if absent)."
  @spec put(String.t(), term(), String.t()) :: :ok | {:error, term()}
  def put(key, value, path \\ path()) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, Jason.encode_to_iodata!(Map.put(read(path), key, value), pretty: true))
    end
  end

  defp xdg_config_home do
    System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")
  end
end
