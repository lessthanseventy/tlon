defmodule Console.StaffingTest do
  @moduledoc """
  The pure seams of the cockpit's centre attach; the spawn passes themselves are the server's
  (`Server.StaffingTest`).
  """
  use ExUnit.Case, async: true

  alias Console.Staffing

  setup do
    Console.TestWorkspaces.put()
  end

  describe "boot_script/2 — the one builder every harness window rides" do
    test "is the server's (the same script the service's pass runs)" do
      assert Staffing.boot_script("export TLON_THREAD=\"42\"", "mise exec -- pi") ==
               Server.Tmux.boot_script("export TLON_THREAD=\"42\"", "mise exec -- pi")
    end
  end

  describe "profile_launcher/3: the Workspace window-0 command runs pi from its profile's config dir" do
    @profile %Server.Profile{name: "tlon"}

    test "attaches-or-creates the workspace's w<id> session" do
      assert Staffing.profile_launcher(1, "tertius", @profile) =~ "new-session -A -s w1"
    end

    # the centre coworker's session starts in the thread's worktree too (the exports are sourced
    # by the boot script before this launcher runs, so $TLON_CWD expands); unset → the cwd
    test "the session starts in the exported worktree" do
      assert Staffing.profile_launcher(1, "tertius", @profile) =~ ~s(-c "${TLON_CWD:-$PWD}")
    end

    test "runs on the workspace's PRIVATE tmux server (id-derived), with the profile's persistence-free config" do
      cmd = Staffing.profile_launcher(1, "tertius", @profile)
      assert cmd =~ "tmux -L console-workspace-1 "
      assert cmd =~ "-f #{Server.Profiles.config_dir(@profile)}/tmux.conf"
    end

    test "points pi at the profile's config dir and carries the funes identity into the session env" do
      cmd = Staffing.profile_launcher(1, "tertius", @profile)
      assert cmd =~ "PI_CODING_AGENT_DIR=#{Server.Profiles.config_dir(@profile)}"
      # The tlon coworker is a funes citizen (machine scope, @tlon_funes_mcp reads ${TLON_MCP_URL}),
      # so the identity is `-e`'d into the tmux SESSION env — durable across a pi respawn, not just
      # pi's one-shot process env. (Supersedes the old "self-contained, no funes env" design.)
      assert cmd =~ ~s(-e TLON_MCP_URL="$TLON_MCP_URL")
      assert cmd =~ ~s(-e TLON_AUTHOR="$TLON_AUTHOR")
      assert cmd =~ "ADAPTERS_RELOAD_CMD="
    end

    test "ADAPTERS_RELOAD_CMD carries the config dir so a adapters/reload respawn stays on-profile" do
      cmd = Staffing.profile_launcher(1, "tertius", @profile)

      assert cmd =~
               "ADAPTERS_RELOAD_CMD=env PI_CODING_AGENT_DIR=#{Server.Profiles.config_dir(@profile)} mise exec -- pi --continue"
    end

    test "a profile with a persona adds --append-system-prompt; without one, none" do
      refute Staffing.profile_launcher(1, "tertius", @profile) =~ "--append-system-prompt"
      withp = Staffing.profile_launcher(1, "tertius", %Server.Profile{name: "tlon", system_prompt: "be terse"})
      assert withp =~ "--append-system-prompt #{Server.Profiles.config_dir(@profile)}/system_prompt.md"
    end

    test "still launches pi as window 0's command" do
      assert Staffing.profile_launcher(1, "tertius", @profile) =~ "mise exec -- pi"
    end

    test "window 0's name is the LEAD roster entry's name, not a hardcoded constant" do
      cmd = Staffing.profile_launcher(1, "borges", @profile)
      assert cmd =~ "new-session -A -s w1 -n borges"
    end

    test "chrome-off + copy-mode style live in the profile tmux.conf now, not chained set-options" do
      cmd = Staffing.profile_launcher(1, "tertius", @profile)
      assert cmd =~ "new-session -A -s w1 -n tertius"
      refute cmd =~ "set-option"

      conf = Server.Profiles.tmux_conf()
      assert conf =~ "set -g status off"
      assert conf =~ "set -g 'status-format[0]' ''"
      assert conf =~ "set -g pane-border-status off"
      assert conf =~ "set -g mode-style 'bg=#3b4261,fg=#c0caf5'"
    end
  end

  describe "spawn_due?/2: the coworker backoff gate" do
    test "a fresh cockpit (no prior failure) is due — even though BEAM monotonic time is NEGATIVE" do
      # The bug: machine_retry_at started at 0 and the guard was `now < retry_at`. BEAM monotonic
      # time starts as a large NEGATIVE number, so `now < 0` was ALWAYS true and the spawn line was
      # never reached — Tlön could never start its coworker. The "no backoff pending" sentinel must
      # be honoured regardless of the sign of `now`.
      now = System.monotonic_time(:millisecond)
      assert now < 0, "precondition: this box's monotonic clock is negative (#{now})"
      assert Staffing.spawn_due?(nil, now)
    end

    test "a pending backoff still in the future is NOT due" do
      now = System.monotonic_time(:millisecond)
      refute Staffing.spawn_due?(now + 5_000, now)
    end

    test "an elapsed backoff is due again" do
      now = System.monotonic_time(:millisecond)
      assert Staffing.spawn_due?(now - 1, now)
    end
  end

  # The Tlön pi identity must reach the tmux SESSION env, not just pi's one-shot process env, or a
  # continuum/--continue respawn comes up with ${TLON_MCP_URL} empty and the funes MCP never wires
  # ("Tool not found"). These -e flags put it in the session env, durable across respawns.
  describe "funes_identity_flags/0 — durable TLON_* wiring for the tlon session" do
    test "emits -e VAR=\"$VAR\" for each funes identity var so bash expands current values" do
      flags = Staffing.funes_identity_flags()
      assert flags =~ ~s(-e TLON_MCP_URL="$TLON_MCP_URL")
      assert flags =~ ~s(-e TLON_THREAD="$TLON_THREAD")
      assert flags =~ ~s(-e TLON_AUTHOR="$TLON_AUTHOR")
    end
  end
end
