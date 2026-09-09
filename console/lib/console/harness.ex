defmodule Console.Harness.Driver do
  @moduledoc """
  The uniform per-harness contract (per-thread-agents Slice D). The lifecycle's tmux transport
  (spawn a window, inject a turn via send-keys, kill a window) is harness-AGNOSTIC and lives with
  the cockpit; what differs per harness is captured here:

    * `launch_command/1` — the exec string a spawned window runs for a profile (the `spawn` half
      of the design contract; the cockpit wraps it in identity exports + `tmux new-window`).
  """
  @callback launch_command(Console.Profile.t()) :: String.t()
end

defmodule Console.Harness do
  @moduledoc """
  Environment-resolved harness binding (per-thread-agents Slice D). A coworker is
  archetype × harness-binding × model; the archetype no longer hardcodes *how* it runs — the
  binding is resolved from the model + where console is running (`Console.Config.environment/0`):

    * **home** (personal Anthropic subscription): an anthropic-provider model binds to
      `:claude_code` — the official harness. Driving a personal Claude subscription through a
      third-party harness risks the account (the ToS rule); do not.
    * anything else (work / API-billed, or a non-anthropic model anywhere): `:pi`.

  A template/roster `harness:` key stays an explicit pin over this resolution (the escape hatch).
  Codex/gemini drivers slot in as new `Console.Harness.Driver` impls + registry entries when first
  needed.
  """

  @drivers %{claude_code: Console.Harness.ClaudeCode, pi: Console.Harness.Pi}

  @doc "The harness a model binds to in `environment` — see the moduledoc for the rule."
  @spec resolve(map() | nil, String.t()) :: :claude_code | :pi
  def resolve(model, environment)
  def resolve(%{provider: "anthropic"}, "home"), do: :claude_code
  def resolve(_model, _environment), do: :pi

  @doc "The driver module for a harness atom (raises on an unknown harness)."
  @spec driver(atom()) :: module()
  def driver(harness), do: Map.fetch!(@drivers, harness)
end

defmodule Console.Harness.ClaudeCode do
  @moduledoc """
  The Claude Code driver: launches through `modules/adapters/claude-code/launch.sh` (funes MCP +
  brief/capture hooks + the citizen protocol prompt). A profile's persona rides as
  `TLON_ROLE_PROMPT_FILE` (the launcher appends it to its citizen prompt — a second
  `--append-system-prompt` flag would *replace* the citizen protocol, not add to it); an
  anthropic model as `--model`.
  """
  @behaviour Console.Harness.Driver

  alias Console.Profile
  alias Console.Profiles

  @impl true
  def launch_command(%Profile{} = p) do
    launcher = Path.join(Profiles.repo(), "modules/adapters/claude-code/launch.sh")

    envs = role_env(p) <> deny_env(p)

    model =
      case p.model do
        %{provider: "anthropic", model: m} -> " --model #{m}"
        _ -> ""
      end

    if envs == "", do: launcher <> model, else: "env " <> envs <> launcher <> model
  end

  defp role_env(%Profile{system_prompt: nil}), do: ""

  defp role_env(%Profile{} = profile),
    do: "TLON_ROLE_PROMPT_FILE=#{Path.join(Profiles.config_dir(profile), "system_prompt.md")} "

  # The write FENCE under the claude harness: a profile whose pi-permission policy denies the
  # file writers (the reviewer) must be structurally fenced here too — pi-permission-system
  # config is invisible to Claude Code, so without this the deny was persona-only ("please don't
  # write") the moment the reviewer bound to claude_code at home. launch.sh merges the list into
  # its --settings as permissions.deny.
  defp deny_env(%Profile{permissions: %{"permission" => perm}}) when is_map(perm) do
    if perm["write"] == "deny" or perm["edit"] == "deny",
      do: "TLON_PERMISSIONS_DENY=Write,Edit,NotebookEdit ",
      else: ""
  end

  defp deny_env(_p), do: ""
end

defmodule Console.Harness.Pi do
  @moduledoc """
  The pi driver: the bare `pi` invocation for a profile — config dir as `PI_CODING_AGENT_DIR`,
  persona as `--append-system-prompt`, driver as `--model`.
  """
  @behaviour Console.Harness.Driver

  alias Console.Profile
  alias Console.Profiles

  # The model MUST ride as a --model flag: pi resolves settings.json defaultModel BEFORE
  # pi-multi-account registers `anthropic`, so a claude-* default falls back to glm; the CLI flag
  # applies after extensions load, so it sticks (verified 2026-08-17).
  @impl true
  def launch_command(%Profile{} = profile) do
    base = Application.get_env(:console, :spawn_launcher, "mise exec -- pi")
    dir = Profiles.config_dir(profile)
    prompt = if profile.system_prompt, do: " --append-system-prompt #{Path.join(dir, "system_prompt.md")}", else: ""

    model =
      case profile.model do
        %{provider: prov, model: m, thinking: think} -> " --model #{prov}/#{m} --thinking #{think}"
        _ -> ""
      end

    "env PI_CODING_AGENT_DIR=#{dir} #{base}#{prompt}#{model}"
  end
end
