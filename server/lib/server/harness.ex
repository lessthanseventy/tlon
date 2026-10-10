defmodule Server.Harness.Driver do
  @moduledoc """
  The uniform per-harness contract (per-thread-agents Slice D). The lifecycle's tmux transport
  (spawn a window, kill a window) is harness-AGNOSTIC and lives in `Server.Tmux` and its callers;
  what differs per harness is captured here:

    * `launch_command/1` — the exec string a spawned window runs for a profile (the `spawn` half
      of the design contract; `Server.Tmux.boot_script/2` wraps it in identity exports).
  """
  @callback launch_command(Server.Profile.t()) :: String.t()
  @doc "The argv of a one-shot, read-only aside: print mode on `question`, `system` appended."
  @callback aside_argv(Server.Profile.t(), system :: String.t(), question :: String.t()) :: [String.t()]
end

defmodule Server.Harness do
  @moduledoc """
  How a coworker runs. A coworker is archetype × harness × model; every model runs in Claude Code
  (`Server.Harness.ClaudeCode`), a non-Anthropic one through Claude Code's gateway setting
  (`adapters/claude-code/gateway.sh`), so the provider is configuration and the harness one.
  A profile's `harness` names the driver; Codex/gemini drivers slot in as new
  `Server.Harness.Driver` impls + registry entries when first needed.
  """

  @drivers %{claude_code: Server.Harness.ClaudeCode}

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
  The Claude Code driver: launches through `adapters/claude-code/launch.sh` (funes MCP, the
  tlon-citizen mod, the citizen protocol prompt), every one-shot through
  `adapters/claude-code/gateway.sh`, which points Claude Code at the model's provider.

  A profile's persona rides as `TLON_ROLE_PROMPT_FILE` (the launcher appends it to its citizen
  prompt — a second `--append-system-prompt` flag would *replace* the citizen protocol, not add to
  it); the model as `--model` and its thinking as `--effort`; the provider as `TLON_PROVIDER`. Its
  permission floor (`Server.Profiles`) lands as deny rules (`TLON_PERMISSIONS_DENY`), which hold in
  every permission mode. A non-Anthropic seat whose workspace allows without asking runs in its
  sandbox (`TLON_SANDBOX_FILE`) with no prompts; one set to ask keeps auto mode.
  """
  @behaviour Server.Harness.Driver

  alias Server.Profile
  alias Server.Profiles

  @efforts ~w(low medium high xhigh max)

  @impl true
  def launch_command(%Profile{} = p) do
    launcher = Path.join(Profiles.tlon_root(), "adapters/claude-code/launch.sh")
    envs = role_env(p) <> deny_env(p) <> provider_env(p) <> sandbox_env(p)
    command = Enum.join([launcher | model_args(p.model)], " ")
    if envs == "", do: command, else: "env " <> envs <> command
  end

  @impl true
  def aside_argv(%Profile{} = p, system, question) do
    [gateway(), provider(p.model), "claude", "-p", question, "--tools", "Read,Grep,Glob"] ++
      ["--permission-mode", "dontAsk", "--no-session-persistence"] ++
      model_args(p.model) ++ ["--append-system-prompt", system]
  end

  @doc "The script every Claude Code invocation runs through: `gateway.sh PROVIDER CMD…`."
  @spec gateway() :: String.t()
  def gateway, do: Path.join(Profiles.tlon_root(), "adapters/claude-code/gateway.sh")

  @doc "The provider a model is reached through, `anthropic` when the profile names none."
  @spec provider(map() | nil) :: String.t()
  def provider(%{provider: p}) when is_binary(p), do: p
  def provider(_model), do: "anthropic"

  defp model_args(%{model: m, thinking: t}) when t in @efforts, do: ["--model", m, "--effort", t]
  defp model_args(%{model: m}), do: ["--model", m]
  defp model_args(_model), do: []

  defp role_env(%Profile{system_prompt: nil}), do: ""

  defp role_env(%Profile{} = profile),
    do: "TLON_ROLE_PROMPT_FILE=#{Path.join(Profiles.config_dir(profile), "system_prompt.md")} "

  defp provider_env(%Profile{model: model}) do
    case provider(model) do
      "anthropic" -> ""
      p -> "TLON_PROVIDER=#{p} "
    end
  end

  defp sandbox_env(%Profile{sandbox: sandbox, permissions: perms, model: model} = p) when is_map(sandbox) do
    if provider(model) != "anthropic" and (perms || %{})["yoloMode"] != false,
      do: "TLON_SANDBOX_FILE=#{Path.join(Profiles.config_dir(p), "sandbox.json")} ",
      else: ""
  end

  defp sandbox_env(_p), do: ""

  # A profile's fence as Claude Code deny rules: its write-deny (the reviewer), the bash and path
  # floor (`@tlon_permissions`), and its cut MCP tools. launch.sh merges the list into its
  # --settings as permissions.deny; a deny holds in dontAsk and auto mode alike.
  defp deny_env(%Profile{} = p) do
    case write_denies(p) ++ floor_denies(p) ++ mcp_denies(p) do
      [] -> ""
      rules -> "TLON_PERMISSIONS_DENY=#{Server.Tmux.sh_single_quote(Enum.join(rules, ","))} "
    end
  end

  defp write_denies(%Profile{permissions: %{"permission" => perm}}) when is_map(perm) do
    if perm["write"] == "deny" or perm["edit"] == "deny", do: ~w(Write Edit NotebookEdit), else: []
  end

  defp write_denies(_p), do: []

  defp floor_denies(%Profile{permissions: %{"permission" => perm}}) when is_map(perm) do
    bash = for {pattern, "deny"} <- perm["bash"] || %{}, do: "Bash(#{pattern})"
    paths = for {glob, "deny"} <- perm["path"] || %{}, tool <- ~w(Read Edit), do: "#{tool}(#{path_rule(glob)})"
    bash ++ paths
  end

  defp floor_denies(_p), do: []

  # A bare glob matches at any depth, as the floor meant it; a ~ path stays home-rooted.
  defp path_rule("~/" <> _ = glob), do: glob
  defp path_rule(glob), do: "**/" <> glob

  defp mcp_denies(%Profile{mcp: mcp}) when is_map(mcp) do
    # a deny would block the mod's own call too: an adapter verb is hidden by the cut alone
    for {server, %{"excludeTools" => tools}} <- mcp,
        tool <- tools,
        tool not in Server.MCP.Tool.adapter_verbs(),
        do: "mcp__#{server}__#{tool}"
  end

  defp mcp_denies(_p), do: []
end
