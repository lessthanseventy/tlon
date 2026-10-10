defmodule Server.HarnessTest do
  @moduledoc """
  The harness and its driver contract: every coworker runs in Claude Code, a non-Anthropic model
  through Claude Code's gateway (`adapters/claude-code/gateway.sh`).
  """
  use ExUnit.Case, async: false

  alias Server.Harness
  alias Server.Profile
  alias Server.Profiles

  @sonnet %{provider: "anthropic", model: "claude-sonnet-5-5", thinking: "medium"}
  @glm %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}

  describe "instantiate/1 — every coworker on the one harness" do
    test "every archetype, on any model, rides claude_code" do
      assert Profiles.instantiate(%{archetype: :builder, name: "hronir"}).harness == :claude_code
      assert Profiles.instantiate(%{archetype: :surveyor, name: "tertius"}).harness == :claude_code
      assert Profiles.instantiate(%{archetype: :planner, name: "borges", model: @glm}).harness == :claude_code
    end
  end

  describe "aside/2 — a one-shot, read-only question to a coworker, outside any thread" do
    test "print mode, read-only tools, no session, its model, effort and persona — through the gateway" do
      p = %Profile{
        name: "hronir",
        harness: :claude_code,
        model: %{@sonnet | thinking: "high"},
        system_prompt: "You are hronir."
      }

      [gateway, provider, cmd | args] = Harness.aside(p, "where is the lead rule?")

      assert gateway =~ "adapters/claude-code/gateway.sh"
      assert provider == "anthropic"
      assert cmd == "claude"
      assert ["-p", "where is the lead rule?"] == Enum.take(args, 2)
      assert_flag(args, "--tools", "Read,Grep,Glob")
      assert_flag(args, "--permission-mode", "dontAsk")
      assert "--no-session-persistence" in args
      assert_flag(args, "--model", "claude-sonnet-5-5")
      assert_flag(args, "--effort", "high")
      assert flag(args, "--append-system-prompt") =~ "You are hronir."
      assert flag(args, "--append-system-prompt") =~ "change nothing"
    end

    test "an ollama model asks through its provider, by its own name" do
      p = %Profile{name: "borges", harness: :claude_code, model: @glm, system_prompt: "You are borges."}
      [_gateway, provider, "claude" | args] = Harness.aside(p, "what is left?")

      assert provider == "ollama-cloud"
      assert_flag(args, "--model", "glm-5.2")
    end
  end

  defp flag(args, name), do: args |> Enum.drop_while(&(&1 != name)) |> Enum.at(1)
  defp assert_flag(args, name, value), do: assert(flag(args, name) == value, "#{name} should be #{value}")

  defp denies(cmd) do
    [_, list] = Regex.run(~r/TLON_PERMISSIONS_DENY='([^']*)'/, cmd)
    String.split(list, ",")
  end

  describe "the driver contract" do
    test "launch.sh with the persona file env + --model; no provider env on the Claude plan" do
      p = %Profile{name: "vera", archetype: :reviewer, model: @sonnet, system_prompt: "You review."}
      cmd = Harness.driver(:claude_code).launch_command(p)

      assert cmd =~ "adapters/claude-code/launch.sh"
      assert cmd =~ "TLON_ROLE_PROMPT_FILE="
      assert cmd =~ "profiles/vera/system_prompt.md"
      assert cmd =~ "--model claude-sonnet-5-5"
      refute cmd =~ "TLON_PROVIDER"
    end

    test "an ollama model launches through its provider, by its own name, its thinking as effort" do
      cmd = Harness.driver(:claude_code).launch_command(%Profile{name: "borges", model: @glm})
      assert cmd =~ "TLON_PROVIDER=ollama-cloud"
      assert cmd =~ "--model glm-5.2 --effort medium"
    end

    test "a sandboxed ollama seat that runs without asking gets its sandbox; one set to ask, or on the Claude plan, doesn't" do
      sandboxed = Profiles.instantiate(%{archetype: :builder, name: "hronir", model: @glm})
      assert Harness.driver(:claude_code).launch_command(sandboxed) =~ "TLON_SANDBOX_FILE="

      asks = %{sandboxed | permissions: Map.put(sandboxed.permissions, "yoloMode", false)}
      refute Harness.driver(:claude_code).launch_command(asks) =~ "TLON_SANDBOX_FILE"

      on_plan = Profiles.instantiate(%{archetype: :builder, name: "hronir"})
      refute Harness.driver(:claude_code).launch_command(on_plan) =~ "TLON_SANDBOX_FILE"
    end

    test "a write-denying policy (the reviewer) exports the write fence" do
      reviewer = Profiles.instantiate(%{archetype: :reviewer, name: "vera"})
      builder = Profiles.instantiate(%{archetype: :builder, name: "hronir"})

      assert ~w(Write Edit NotebookEdit) -- denies(Harness.driver(:claude_code).launch_command(reviewer)) == []
      refute "NotebookEdit" in denies(Harness.driver(:claude_code).launch_command(builder))
    end

    test "the permission floor lands as deny rules: sudo and the catastrophic commands, the secret paths" do
      rules =
        denies(
          Harness.driver(:claude_code).launch_command(Profiles.instantiate(%{archetype: :builder, name: "hronir"}))
        )

      assert "Bash(sudo *)" in rules and "Bash(rm -rf /*)" in rules and "Bash(curl * | sh)" in rules
      assert "Read(**/*.env)" in rules and "Edit(**/*.env)" in rules
      assert "Read(~/.ssh/*)" in rules
    end

    test "the model's thinking level rides as --effort" do
      p = %Profile{name: "plain", model: %{provider: "anthropic", model: "claude-opus-5-5", thinking: "xhigh"}}
      assert Harness.driver(:claude_code).launch_command(p) =~ "--model claude-opus-5-5 --effort xhigh"
    end

    test "no persona and no fence → the bare launcher, no env prefix" do
      cmd = Harness.driver(:claude_code).launch_command(%Profile{name: "plain", model: @sonnet})
      refute cmd =~ "env "
      assert String.contains?(cmd, "launch.sh --model claude-sonnet-5-5")
    end

    test "the profile's MCP excludeTools become deny rules" do
      deny = fn name, archetype ->
        denies(Harness.driver(:claude_code).launch_command(Profiles.instantiate(%{archetype: archetype, name: name})))
      end

      reviewer = deny.("vera", :reviewer)
      assert "mcp__tlon__edit_clause" in reviewer and "mcp__tlon__rename_identifier" in reviewer
      assert "mcp__tlon__consult_peer" in deny.("hronir", :builder)

      tertius = deny.("tertius", :surveyor)
      assert "mcp__tlon__consult_peer" in tertius
      refute "mcp__tlon__open_thread" in tertius, "the orchestrator keeps the verbs it routes with"
    end

    test "the launch command runs: its env reaches launch.sh, quotes and all" do
      cmd = Harness.driver(:claude_code).launch_command(Profiles.instantiate(%{archetype: :builder, name: "hronir"}))
      launcher = Path.join(Profiles.tlon_root(), "adapters/claude-code/launch.sh")
      probe = String.replace(cmd, launcher, "printenv TLON_PERMISSIONS_DENY #")
      {out, 0} = System.cmd("sh", ["-c", probe])
      assert out =~ "Bash(curl * | sh)"
    end

    test "launch.sh: TLON_READ_DIRS open beside the worktree and are fenced against edits" do
      launcher = Path.join(Profiles.tlon_root(), "adapters/claude-code/launch.sh")

      env = [
        {"TLON_LAUNCH_DRYRUN", "1"},
        {"TLON_MCP_URL", "http://127.0.0.1:1/mcp"},
        {"TLON_THREAD", "7"},
        {"TLON_AUTHOR", "hronir"},
        {"TLON_PERMISSIONS_DENY", "mcp__tlon__close_thread"},
        {"TLON_READ_DIRS", "/p/b:/p/c"}
      ]

      {out, 0} = System.cmd("bash", [launcher], env: env)
      [settings] = for "settings:   " <> json <- String.split(out, "\n"), do: JSON.decode!(json)

      assert settings["permissions"]["additionalDirectories"] == ["/p/b", "/p/c"]
      assert settings["permissions"]["deny"] == ["mcp__tlon__close_thread", "Edit(//p/b/**)", "Edit(//p/c/**)"]
    end

    test "launch.sh: concurrent boots each pre-accept their folder's trust, none lost to another's write" do
      launcher = Path.join(Profiles.tlon_root(), "adapters/claude-code/launch.sh")
      home = Path.join(System.tmp_dir!(), "tlon-trust-#{System.unique_integer([:positive])}")
      bin = Path.join(home, "bin")
      File.mkdir_p!(bin)
      File.write!(Path.join(bin, "claude"), "#!/bin/sh\nexit 0\n")
      File.chmod!(Path.join(bin, "claude"), 0o755)
      on_exit(fn -> File.rm_rf!(home) end)

      dirs =
        for n <- 1..16 do
          dir = Path.join(home, "repo#{n}")
          File.mkdir_p!(dir)
          dir
        end

      env = [
        {"HOME", home},
        {"PATH", "#{bin}:#{System.get_env("PATH")}"},
        {"TLON_MCP_URL", "http://127.0.0.1:1/mcp"},
        {"TLON_THREAD", "7"},
        {"TLON_AUTHOR", "hronir"},
        {"TLON_PROVIDER", "anthropic"}
      ]

      dirs
      |> Task.async_stream(fn dir -> System.cmd("bash", [launcher], env: env, cd: dir) end, max_concurrency: 16)
      |> Enum.each(fn {:ok, {_, status}} -> assert status == 0 end)

      projects = home |> Path.join(".claude.json") |> File.read!() |> JSON.decode!() |> Map.fetch!("projects")
      assert Enum.sort(Map.keys(projects)) == Enum.sort(dirs)
      assert Enum.all?(Map.values(projects), & &1["hasTrustDialogAccepted"])

      assert Path.wildcard(Path.join(home, ".claude.json.*"), match_dot: true) == [
               Path.join(home, ".claude.json.tlon-lock")
             ]
    end

    test "launch.sh: only a seat on the Claude plan loads the plan's budget mod, the one that wraps the model's stream" do
      launcher = Path.join(Profiles.tlon_root(), "adapters/claude-code/launch.sh")

      env = [
        {"TLON_LAUNCH_DRYRUN", "1"},
        {"TLON_MCP_URL", "http://127.0.0.1:1/mcp"},
        {"TLON_THREAD", "7"},
        {"TLON_AUTHOR", "hronir"}
      ]

      exec = fn provider ->
        {out, 0} = System.cmd("bash", [launcher], env: [{"TLON_PROVIDER", provider} | env])
        out |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "exec: "))
      end

      assert exec.("anthropic") =~ "adapters/claude-code/plan"
      refute exec.("ollama-cloud") =~ "adapters/claude-code/plan"
    end
  end
end
