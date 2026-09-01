defmodule Console.Config do
  @moduledoc """
  The operator's **runtime settings file** — the knobs the cockpit exposes in-app (the SETTINGS
  panel + verbs) so changing them never means editing Elixir source or re-running `home:switch`.
  A plain JSON map at `~/.config/console/config.json` (override with `config :console, :config_path`,
  which the test env points away from the real home).

  Shape (all keys optional — absent means "the compiled default wins"):

      {
        "coworkers": {
          "tlon": {"provider": "anthropic", "model": "claude-opus-4-8", "thinking": "medium"}
        }
      }

  `Console.Profiles.fetch/1` merges `coworkers.<profile>` over the profile's compiled `model`, so a
  settings change applies wherever the profile flows (materialised settings.json AND the launcher's
  `--model` flag) the next time the coworker spawns. Best-effort on read (a missing or corrupt file
  is just "no overrides"); writes are atomic (tmp + rename) so a crash mid-write can't truncate it.
  """

  @doc "The settings file path (`config :console, :config_path` override, else ~/.config/console/config.json)."
  @spec path() :: String.t()
  def path do
    Application.get_env(:console, :config_path) ||
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
  Returned in the `Console.Profile.model` shape: `%{provider, model, thinking}` with atom keys.
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

  @doc "Persist a coworker profile's model override (`%{provider, model, thinking}`)."
  @spec put_coworker_model(String.t(), map(), String.t()) :: :ok
  def put_coworker_model(profile, %{provider: prov, model: model, thinking: think}, path \\ path()) do
    merge_coworker(profile, %{"provider" => prov, "model" => model, "thinking" => think}, path)
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

  @doc "Persist a coworker profile's yolo (permission-policy) override without disturbing its model."
  @spec put_coworker_yolo(String.t(), boolean(), String.t()) :: :ok
  def put_coworker_yolo(profile, yolo, path \\ path()) when is_boolean(yolo) do
    merge_coworker(profile, %{"yolo" => yolo}, path)
  end

  @doc """
  Where console is running — the harness-binding signal (per-thread-agents Slice D): `"home"`
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
  The maximum number of CONCURRENT leaf sessions the cockpit will spawn (the runaway-fleet
  circuit breaker — every leaf is a live harness, most of them on the Claude subscription at
  home). Config key `"max_leaves"`; default #{6}. Threads staffed past the cap stay open and
  keep their lead; they just wait ("parked") until a seat frees (a leaf closes) — the next
  render pass staffs them automatically.
  """
  @spec max_leaves(String.t()) :: pos_integer()
  def max_leaves(path \\ path()) do
    case read(path) do
      %{"max_leaves" => n} when is_integer(n) and n > 0 -> n
      _ -> 6
    end
  end

  @doc """
  The operator's persisted default-coworker override for new chat threads, or `nil` when unset.
  Just the override — the roster-derived default is resolved from the LIVE workspace roster by the
  caller (server `designated_lead`), so no stale hardcoded stand-in handle can leak in as a thread lead.
  """
  @spec default_coworker_override(String.t()) :: String.t() | nil
  def default_coworker_override(path \\ path()) do
    case read(path) do
      %{"default_coworker" => h} when is_binary(h) and h != "" -> h
      _ -> nil
    end
  end

  @doc "Persist the default coworker handle."
  @spec put_default_coworker(String.t(), String.t()) :: :ok
  def put_default_coworker(handle, path \\ path()) when is_binary(handle) do
    path |> read() |> Map.put("default_coworker", handle) |> write!(path)
  end

  # Merge fields into `coworkers.<profile>` so independent knobs (model, yolo) coexist — a later
  # put on one never clobbers the other. Seeds the intermediate maps when absent.
  defp merge_coworker(profile, fields, path) do
    map = read(path)
    coworkers = Map.get(map, "coworkers", %{})
    entry = Map.merge(Map.get(coworkers, profile, %{}), fields)
    map |> Map.put("coworkers", Map.put(coworkers, profile, entry)) |> write!(path)
  end

  # Atomic: write beside the target then rename, so a crash mid-write never truncates the file.
  defp write!(map, path) do
    File.mkdir_p!(Path.dirname(path))
    tmp = path <> ".tmp"
    File.write!(tmp, Jason.encode!(map, pretty: true) <> "\n")
    File.rename!(tmp, path)
    :ok
  end

  defp xdg_config_home do
    System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")
  end
end
