defmodule Server.HarnessTest do
  @moduledoc """
  Environment-resolved harness binding + the per-harness driver contract (Slice D). The ToS rule:
  an anthropic-provider model at HOME binds to claude_code (the official harness); everything else
  — work/API, or a non-anthropic model anywhere — binds to pi.
  """
  use ExUnit.Case, async: false

  alias Server.Harness
  alias Server.OperatorConfig, as: Config
  alias Server.Profile
  alias Server.Profiles

  @sonnet %{provider: "anthropic", model: "claude-sonnet-5", thinking: "medium"}
  @glm %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}

  setup do
    prior = System.get_env("TLON_ENV")

    on_exit(fn ->
      if prior, do: System.put_env("TLON_ENV", prior), else: System.delete_env("TLON_ENV")
    end)

    System.delete_env("TLON_ENV")
    :ok
  end

  describe "resolve/2 — the ToS rule" do
    test "anthropic model at home → claude_code (never a third-party harness on the personal sub)" do
      assert Harness.resolve(@sonnet, "home") == :claude_code
    end

    test "anthropic model at work (API-billed) → pi" do
      assert Harness.resolve(@sonnet, "work") == :pi
    end

    test "a non-anthropic model → pi anywhere; nil model inherits base defaults → pi" do
      assert Harness.resolve(@glm, "home") == :pi
      assert Harness.resolve(@glm, "work") == :pi
      assert Harness.resolve(nil, "home") == :pi
    end
  end

  describe "Config.environment/1" do
    test "defaults to home (test config points at a nonexistent file)" do
      assert Config.environment() == "home"
    end

    test "TLON_ENV wins" do
      System.put_env("TLON_ENV", "work")
      assert Config.environment() == "work"
    end

    test "the config file's environment key is read when no env var is set" do
      path = Path.join(System.tmp_dir!(), "aleph_env_test_#{System.unique_integer([:positive])}.json")
      File.write!(path, ~s({"environment": "work"}))
      on_exit(fn -> File.rm(path) end)

      assert Config.environment(path) == "work"
    end
  end

  describe "instantiate/1 binds the harness from model × environment" do
    test "at home, every archetype (all anthropic-model) rides claude_code" do
      assert Profiles.instantiate(%{archetype: :builder, name: "hronir"}).harness == :claude_code
      assert Profiles.instantiate(%{archetype: :reviewer, name: "vera"}).harness == :claude_code
      assert Profiles.instantiate(%{archetype: :planner, name: "borges"}).harness == :claude_code
      assert Profiles.instantiate(%{archetype: :surveyor, name: "tertius"}).harness == :claude_code
    end

    test "at work the same archetypes bind to pi — the personal sub is out of the loop" do
      System.put_env("TLON_ENV", "work")
      assert Profiles.instantiate(%{archetype: :builder, name: "hronir"}).harness == :pi
      assert Profiles.instantiate(%{archetype: :reviewer, name: "vera"}).harness == :pi
    end

    test "a roster-entry model override re-resolves the binding (ollama planner at home → pi)" do
      assert Profiles.instantiate(%{archetype: :planner, name: "borges", model: @glm}).harness == :pi
    end
  end

  describe "aside/2 — a one-shot, read-only question to a coworker, outside any thread" do
    test "claude_code: print mode, read-only tools, no session, its model, effort and persona" do
      p = %Profile{
        name: "hronir",
        harness: :claude_code,
        model: %{@sonnet | thinking: "high"},
        system_prompt: "You are hronir."
      }

      [cmd | args] = Harness.aside(p, "where is the lead rule?")

      assert cmd == "claude"
      assert ["-p", "where is the lead rule?"] == Enum.take(args, 2)
      assert_flag(args, "--tools", "Read,Grep,Glob")
      assert_flag(args, "--permission-mode", "dontAsk")
      assert "--no-session-persistence" in args
      assert_flag(args, "--model", "claude-sonnet-5")
      assert_flag(args, "--effort", "high")
      assert flag(args, "--append-system-prompt") =~ "You are hronir."
      assert flag(args, "--append-system-prompt") =~ "change nothing"
    end

    test "pi: print mode, read-only tools, no extensions or session, provider-qualified model" do
      p = %Profile{name: "borges", harness: :pi, model: @glm, system_prompt: "You are borges."}
      [_pi | args] = Harness.aside(p, "what is left?")

      assert ["-p", "what is left?"] == Enum.take(args, 2)
      assert_flag(args, "--tools", "read,grep,find,ls")
      assert "--no-extensions" in args and "--no-session" in args
      assert_flag(args, "--model", "ollama-cloud/glm-5.2")
      assert_flag(args, "--thinking", "medium")
      assert flag(args, "--append-system-prompt") =~ "You are borges."
    end
  end

  defp flag(args, name), do: args |> Enum.drop_while(&(&1 != name)) |> Enum.at(1)
  defp assert_flag(args, name, value), do: assert(flag(args, name) == value, "#{name} should be #{value}")

  describe "the driver contract" do
    test "claude_code: launch.sh with the persona file env + --model for an anthropic model" do
      p = %Profile{name: "vera", archetype: :reviewer, model: @sonnet, system_prompt: "You review."}
      cmd = Harness.driver(:claude_code).launch_command(p)

      assert cmd =~ "adapters/claude-code/launch.sh"
      assert cmd =~ "TLON_ROLE_PROMPT_FILE="
      assert cmd =~ "profiles/vera/system_prompt.md"
      assert cmd =~ "--model claude-sonnet-5"
      refute cmd =~ "PI_CODING_AGENT_DIR"
    end

    test "claude_code: a write-denying policy (the reviewer) exports the permissions fence" do
      reviewer = Profiles.instantiate(%{archetype: :reviewer, name: "vera"})
      builder = Profiles.instantiate(%{archetype: :builder, name: "hronir"})

      assert reviewer.harness == :claude_code
      assert Harness.driver(:claude_code).launch_command(reviewer) =~ "TLON_PERMISSIONS_DENY=Write,Edit,NotebookEdit,"
      refute Harness.driver(:claude_code).launch_command(builder) =~ "NotebookEdit"
    end

    test "claude_code: the model's thinking level rides as --effort" do
      p = %Profile{name: "plain", model: %{provider: "anthropic", model: "claude-opus-5-5", thinking: "xhigh"}}
      assert Harness.driver(:claude_code).launch_command(p) =~ "--model claude-opus-5-5 --effort xhigh"
    end

    test "claude_code: no persona → the bare launcher, no env prefix" do
      p = %Profile{name: "plain", model: @sonnet}
      cmd = Harness.driver(:claude_code).launch_command(p)
      refute cmd =~ "TLON_ROLE_PROMPT_FILE"
      assert String.contains?(cmd, "launch.sh --model claude-sonnet-5")
    end

    test "pi: PI_CODING_AGENT_DIR + persona + provider-qualified --model" do
      p = %Profile{name: "borges", model: @glm, system_prompt: "You plan."}
      cmd = Harness.driver(:pi).launch_command(p)

      assert cmd =~ "PI_CODING_AGENT_DIR="
      assert cmd =~ "--append-system-prompt"
      assert cmd =~ "--model ollama-cloud/glm-5.2 --thinking medium"
    end

    test "pi: the window carries its own resume — ADAPTERS_RELOAD_CMD is the same launch, --continue" do
      p = %Profile{name: "borges", model: @glm, system_prompt: "You plan."}
      cmd = Harness.driver(:pi).launch_command(p)

      {out, 0} =
        System.cmd("sh", [
          "-c",
          String.replace(cmd, ~r/(' PI_CODING_AGENT_DIR=\S+) pi .*$/, "\\1 printenv ADAPTERS_RELOAD_CMD")
        ])

      assert String.trim(out) =~ ~r/^env PI_CODING_AGENT_DIR=\S+ pi --append-system-prompt .* --continue$/
    end

    test "claude_code: the profile's MCP excludeTools become deny rules — the same surface as under pi" do
      deny = fn name, archetype ->
        cmd = Harness.driver(:claude_code).launch_command(Profiles.instantiate(%{archetype: archetype, name: name}))
        [_, list] = Regex.run(~r/TLON_PERMISSIONS_DENY=(\S+)/, cmd)
        String.split(list, ",")
      end

      reviewer = deny.("vera", :reviewer)
      assert "mcp__tlon__edit_clause" in reviewer and "mcp__tlon__rename_identifier" in reviewer
      assert "mcp__tlon__consult_peer" in deny.("hronir", :builder)

      tertius = deny.("tertius", :surveyor)
      assert "mcp__tlon__consult_peer" in tertius
      refute "mcp__tlon__open_thread" in tertius, "the orchestrator keeps the verbs it routes with"
    end

    test "claude_code launch.sh: TLON_READ_DIRS open beside the worktree and are fenced against edits" do
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
  end
end
