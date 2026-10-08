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
        "max_worklines": 4,
        "max_open_worklines": 10,
        "auto_land_risk": 2
      }

  `calendars` and `alarm_minutes` are `Server.Calendar`'s and `Server.Alerts`' (a meeting's alarm);
  `max_worklines` and `max_open_worklines` are `Server.Intake`'s caps per workspace: worklines being
  worked, and open in all (those waiting on the operator included). `auto_land_risk` is the operator's
  standing approval (`Server.Workline`): a reviewed-and-approved workline whose risk grade
  (`Server.Workline.Grade`, 1–5 per axis) has no axis over it, no limit hit and no decision left to
  them joins the merge queue without waiting on them; absent, every review waits for its approval.

  Best-effort on read: a missing or corrupt file is just "no overrides".
  """

  # The runtime knobs the operator steers a running bench with — what /api/settings serves and the
  # office's settings panel edits. Every one is read live where it is used, so a change takes at the
  # next pass. A `nullable` knob's nil means "off" and removes the key.
  @knobs [
    %{key: "max_leaves", type: "int", min: 1, max: 12, default: 6, doc: "coworker windows open at once"},
    %{
      key: "max_worklines",
      type: "int",
      min: 0,
      max: 12,
      default: 4,
      doc: "worklines intake keeps in work per workspace (0 pauses intake)"
    },
    %{
      key: "max_open_worklines",
      type: "int",
      min: 1,
      max: 50,
      default: 10,
      doc: "open worklines per workspace, waiting on you included"
    },
    %{
      key: "auto_land_risk",
      type: "int",
      min: 1,
      max: 5,
      default: nil,
      nullable: true,
      doc: "an approved workline graded at most this lands without you (off: every review waits)"
    },
    %{
      key: "continuation_turns",
      type: "int",
      min: 0,
      max: 10,
      default: 3,
      doc: "nudges a stuck workline gets before it stops on you"
    },
    %{
      key: "quiet_workline_minutes",
      type: "int",
      min: 10,
      max: 1440,
      default: 60,
      doc: "a workline quiet this long gets a nudge"
    },
    %{
      key: "stalled_ticket_minutes",
      type: "int",
      min: 5,
      max: 1440,
      default: 30,
      doc: "a routed ticket nobody started is started by intake after this"
    },
    %{
      key: "alarm_minutes",
      type: "int",
      min: 0,
      max: 60,
      default: 5,
      doc: "a meeting's alarm goes up this long before it starts"
    },
    %{key: "banter", type: "bool", default: true, doc: "the model writing coworkers' small talk and the pets' lines"},
    %{key: "weather_location", type: "string", default: "", doc: "where the office's weather comes from"},
    %{
      key: "intake_every_minutes",
      type: "int",
      min: 1,
      max: 60,
      default: 15,
      boot: true,
      doc: "how often intake hands the manager the next ticket"
    },
    %{
      key: "maintain_every_minutes",
      type: "int",
      min: 5,
      max: 60,
      default: 30,
      boot: true,
      doc: "how often the sweeps nag stale gates and nudge quiet worklines"
    },
    %{
      key: "lifeline_rescue_minutes",
      type: "int",
      min: 15,
      max: 240,
      default: 30,
      boot: true,
      doc: "a job left running by a stopped server is retried after this"
    }
  ]

  @grade_defaults %{
    "junior" => %{provider: "anthropic", model: "claude-haiku-5-5", thinking: "low"},
    "senior" => %{provider: "anthropic", model: "claude-sonnet-5-5", thinking: "medium"},
    "greybeard" => %{provider: "anthropic", model: "claude-fable-5-1", thinking: "high"}
  }

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
  The model a grade maps to: the config's `grades.<grade>` (`{provider, model, thinking}`), else
  the compiled default — Claude at every grade, so a fresh install needs one subscription. nil
  for no grade. In the `Server.Profile.model` shape.
  """
  @spec grade_model(String.t() | nil, String.t()) :: map() | nil
  def grade_model(grade, path \\ path())
  def grade_model(nil, _path), do: nil

  def grade_model(grade, path) do
    case get_in(read(path), ["grades", grade]) do
      %{"provider" => prov, "model" => model} = m ->
        %{provider: prov, model: model, thinking: m["thinking"] || "medium"}

      _ ->
        @grade_defaults[grade]
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
  def max_leaves(path \\ path()), do: setting("max_leaves", path)

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
  def banter?(path \\ path()), do: setting("banter", path)

  @doc "Every runtime knob with its current `value` (the default where the file is silent); `boot` ones take on a restart."
  @spec knobs(String.t()) :: [map()]
  def knobs(path \\ path()) do
    map = read(path)
    for k <- @knobs, do: k |> Map.put_new(:boot, false) |> Map.put(:value, value(k, map))
  end

  @doc """
  Oban's compiled config with the boot knobs applied: the intake and maintain crons' intervals and
  Lifeline's rescue window. A config without those plugins (the test env's) passes through as is.
  """
  @spec boot_oban(keyword(), String.t()) :: keyword()
  def boot_oban(oban, path \\ path()) do
    case oban[:plugins] do
      nil ->
        oban

      plugins ->
        every = fn key -> "*/#{setting(key, path)} * * * *" end

        cron = %{
          Server.Jobs.Intake => every.("intake_every_minutes"),
          Server.Jobs.Maintain => every.("maintain_every_minutes")
        }

        plugins =
          Enum.map(plugins, fn
            {Oban.Plugins.Lifeline, o} ->
              {Oban.Plugins.Lifeline,
               Keyword.put(o, :rescue_after, to_timeout(minute: setting("lifeline_rescue_minutes", path)))}

            {Oban.Plugins.Cron, o} ->
              {Oban.Plugins.Cron,
               Keyword.update(o, :crontab, [], fn tab -> for {expr, w} <- tab, do: {Map.get(cron, w, expr), w} end)}

            other ->
              other
          end)

        Keyword.put(oban, :plugins, plugins)
    end
  end

  @doc "One knob's current value, the default where the file is silent or holds something invalid."
  @spec setting(String.t(), String.t()) :: term()
  def setting(key, path \\ path()), do: value(Enum.find(@knobs, &(&1.key == key)), read(path))

  @doc """
  Set several knobs at once: every key is checked against its knob first, and nothing is written
  unless all of them pass. `:ok` or `{:error, why}`.
  """
  @spec put_settings(map(), String.t()) :: :ok | {:error, String.t()}
  def put_settings(changes, path \\ path()) when is_map(changes) do
    checked =
      Enum.reduce_while(changes, {:ok, read(path)}, fn {key, v}, {:ok, acc} ->
        with %{} = knob <- Enum.find(@knobs, &(&1.key == key)) || {:error, "no setting named #{inspect(key)}"},
             {:ok, ok} <- valid(knob, v) do
          {:cont, {:ok, if(is_nil(ok), do: Map.delete(acc, key), else: Map.put(acc, key, ok))}}
        else
          {:error, why} -> {:halt, {:error, why}}
          :invalid -> {:halt, {:error, "#{key} must be #{expects(Enum.find(@knobs, &(&1.key == key)))}"}}
        end
      end)

    with {:ok, map} <- checked, :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, Jason.encode_to_iodata!(map, pretty: true))
    end
  end

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

  defp value(knob, map) do
    case valid(knob, Map.get(map, knob.key)) do
      {:ok, v} when not is_nil(v) -> v
      _ -> knob.default
    end
  end

  defp valid(%{nullable: true}, nil), do: {:ok, nil}
  defp valid(_knob, nil), do: {:ok, nil}
  defp valid(%{type: "int", min: lo, max: hi}, v) when is_integer(v) and v >= lo and v <= hi, do: {:ok, v}
  defp valid(%{type: "bool"}, v) when is_boolean(v), do: {:ok, v}
  defp valid(%{type: "string"}, v) when is_binary(v), do: {:ok, String.trim(v)}
  defp valid(_knob, _v), do: :invalid

  defp expects(%{type: "int", min: lo, max: hi} = k),
    do: "a whole number #{lo}–#{hi}#{if k[:nullable], do: " or null (off)"}"

  defp expects(%{type: "bool"}), do: "true or false"
  defp expects(%{type: "string"}), do: "text"
end
