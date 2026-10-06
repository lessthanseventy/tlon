defmodule Server.Harness.Driver do
  @moduledoc """
  The uniform per-harness contract (per-thread-agents Slice D). The lifecycle's tmux transport
  (spawn a window, inject a turn via send-keys, kill a window) is harness-AGNOSTIC and lives in
  `Server.Tmux` and its callers; what differs per harness is captured here:

    * `launch_command/1` — the exec string a spawned window runs for a profile (the `spawn` half
      of the design contract; `Server.Tmux.boot_script/2` wraps it in identity exports).
  """
  @callback launch_command(Server.Profile.t()) :: String.t()
  @doc "The argv of a one-shot, read-only aside: print mode on `question`, `system` appended."
  @callback aside_argv(Server.Profile.t(), system :: String.t(), question :: String.t()) :: [String.t()]
end

defmodule Server.Harness do
  @moduledoc """
  Environment-resolved harness binding (per-thread-agents Slice D). A coworker is
  archetype × harness-binding × model; the archetype no longer hardcodes *how* it runs — the
  binding is resolved from the model + where the server is running (`Server.OperatorConfig.environment/0`):

    * **home** (personal Anthropic subscription): an anthropic-provider model binds to
      `:claude_code` — the official harness. Driving a personal Claude subscription through a
      third-party harness risks the account (the ToS rule); do not.
    * anything else (work / API-billed, or a non-anthropic model anywhere): `:pi`.

  A template/roster `harness:` key stays an explicit pin over this resolution (the escape hatch).
  Codex/gemini drivers slot in as new `Server.Harness.Driver` impls + registry entries when first
  needed.
  """

  @drivers %{claude_code: Server.Harness.ClaudeCode, pi: Server.Harness.Pi}

  @doc "The harness a model binds to in `environment` — see the moduledoc for the rule."
  @spec resolve(map() | nil, String.t()) :: :claude_code | :pi
  def resolve(model, environment)
  def resolve(%{provider: "anthropic"}, "home"), do: :claude_code
  def resolve(_model, _environment), do: :pi

  @doc "The driver module for a harness atom (raises on an unknown harness)."
  @spec driver(atom()) :: module()
  def driver(harness), do: Map.fetch!(@drivers, harness)

  @doc """
  The argv that asks a coworker one question aside, outside any thread: its own harness, model,
  effort and persona, in print mode, with read-only tools and no saved session — it may read the
  code to answer and can change nothing. The shell's office runs it when you talk to someone.
  """
  @spec aside(Server.Profile.t(), String.t()) :: [String.t()]
  def aside(%Server.Profile{} = p, question) do
    system =
      [
        p.system_prompt,
        "This is a quick aside from the operator, outside any thread: answer in a few plain " <>
          "sentences. You may read the code to answer; change nothing."
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    driver(p.harness).aside_argv(p, system, question)
  end
end

defmodule Server.Harness.ClaudeCode do
  @moduledoc """
  The Claude Code driver: launches through `adapters/claude-code/launch.sh` (funes MCP +
  brief/capture hooks + the citizen protocol prompt). A profile's persona rides as
  `TLON_ROLE_PROMPT_FILE` (the launcher appends it to its citizen prompt — a second
  `--append-system-prompt` flag would *replace* the citizen protocol, not add to it); an
  anthropic model as `--model`.
  """
  @behaviour Server.Harness.Driver

  alias Server.Profile
  alias Server.Profiles

  @impl true
  def launch_command(%Profile{} = p) do
    launcher = Path.join(Profiles.tlon_root(), "adapters/claude-code/launch.sh")

    envs = role_env(p) <> deny_env(p)

    model =
      case p.model do
        %{provider: "anthropic", model: m, thinking: t} when is_binary(t) -> " --model #{m} --effort #{t}"
        %{provider: "anthropic", model: m} -> " --model #{m}"
        _ -> ""
      end

    if envs == "", do: launcher <> model, else: "env " <> envs <> launcher <> model
  end

  @impl true
  def aside_argv(%Profile{} = p, system, question) do
    model =
      case p.model do
        %{provider: "anthropic", model: m, thinking: t} when is_binary(t) -> ["--model", m, "--effort", t]
        %{provider: "anthropic", model: m} -> ["--model", m]
        _ -> []
      end

    ["claude", "-p", question, "--tools", "Read,Grep,Glob", "--permission-mode", "dontAsk", "--no-session-persistence"] ++
      model ++ ["--append-system-prompt", system]
  end

  defp role_env(%Profile{system_prompt: nil}), do: ""

  defp role_env(%Profile{} = profile),
    do: "TLON_ROLE_PROMPT_FILE=#{Path.join(Profiles.config_dir(profile), "system_prompt.md")} "

  # The FENCE under the claude harness: pi-permission-system config and the pi MCP adapter's
  # `excludeTools` are invisible to Claude Code, so a profile's write-deny (the reviewer) and its
  # cut MCP tools must be structural deny rules here, or they are persona-only ("please don't").
  # launch.sh merges the list into its --settings as permissions.deny.
  defp deny_env(%Profile{} = p) do
    case write_denies(p) ++ mcp_denies(p) do
      [] -> ""
      tools -> "TLON_PERMISSIONS_DENY=#{Enum.join(tools, ",")} "
    end
  end

  defp write_denies(%Profile{permissions: %{"permission" => perm}}) when is_map(perm) do
    if perm["write"] == "deny" or perm["edit"] == "deny", do: ~w(Write Edit NotebookEdit), else: []
  end

  defp write_denies(_p), do: []

  defp mcp_denies(%Profile{mcp: mcp}) when is_map(mcp) do
    for {server, %{"excludeTools" => tools}} <- mcp, tool <- tools, do: "mcp__#{server}__#{tool}"
  end

  defp mcp_denies(_p), do: []
end

defmodule Server.Harness.Pi do
  @moduledoc """
  The pi driver: the bare `pi` invocation for a profile — config dir as `PI_CODING_AGENT_DIR`,
  persona as `--append-system-prompt`, driver as `--model`.
  """
  @behaviour Server.Harness.Driver

  alias Server.Profile
  alias Server.Profiles

  # The model MUST ride as a --model flag: pi resolves settings.json defaultModel BEFORE
  # pi-multi-account registers `anthropic`, so a claude-* default falls back to glm; the CLI flag
  # applies after extensions load, so it sticks (verified 2026-08-17).
  @impl true
  def launch_command(%Profile{} = profile) do
    base = Application.get_env(:server, :spawn_launcher_pi, "pi")
    dir = Profiles.config_dir(profile)
    prompt = if profile.system_prompt, do: " --append-system-prompt #{Path.join(dir, "system_prompt.md")}", else: ""

    model =
      case profile.model do
        %{provider: prov, model: m, thinking: think} -> " --model #{prov}/#{m} --thinking #{think}"
        _ -> ""
      end

    "env PI_CODING_AGENT_DIR=#{dir} #{base}#{prompt}#{model}"
  end

  @impl true
  def aside_argv(%Profile{} = profile, system, question) do
    base = Application.get_env(:server, :spawn_launcher_pi, "pi")

    model =
      case profile.model do
        %{provider: prov, model: m, thinking: think} -> ["--model", "#{prov}/#{m}", "--thinking", think]
        _ -> []
      end

    [base, "-p", question, "--no-extensions", "--no-session", "--tools", "read,grep,find,ls"] ++
      model ++ ["--append-system-prompt", system]
  end
end
