defmodule Console.CockpitRosterTest do
  @moduledoc """
  C2.3: `ensure_workspace_roster/2` — the ONE roster-driven spawner replacing the old hardcoded
  `ensure_machine_coworker`/`ensure_claude_coworker`/`ensure_third_coworker` trio. Exercises the
  REAL dispatch (harness-by-archetype, handle/window derivation) through two injected seams —
  `:tlon_cmd` (the tmux runner; same fake-runner pattern the C2.2 describe block in
  `Console.CockpitTest` already uses) and `:tlon_join` (the funes identity minter, mirroring
  `Console.Crew`'s `:crew_join`/`:crew_cmd` pair) — so no live tmux/pi process is ever forked.

  The tail dispatch's DEFAULT thread id (`machine_thread_id/0`) still reads the real funes Repo
  (aleph's `config/test.exs` keeps it down), so this suite boots its own temp DB + one open
  machine thread, mirroring `Console.WorkspacesTest` — and for the same reason, is the one aleph suite
  (besides that one) that isn't `async: true`.
  """
  use ExUnit.Case, async: false

  alias Console.Cockpit
  alias Console.Sessions
  alias Console.Space
  alias Ecto.Adapters.SQLite3
  alias Server.Channel
  alias Server.Repo

  # Workspace fixture: the hardcoded fallback Workspace is gone (reshape slice A); suites
  # that render or drive a Workspace push one through the Console.Workspaces cache-down seam.
  setup do
    Console.TestWorkspaces.put()
  end

  setup_all do
    db = Path.join(System.tmp_dir!(), "aleph_cockpit_roster_test_#{System.unique_integer([:positive])}.db")
    Application.put_env(:server, Repo, Keyword.merge(Application.get_env(:server, Repo, []), database: db, pool_size: 1))

    config = Repo.config()
    _ = SQLite3.storage_down(config)
    :ok = SQLite3.storage_up(config)
    {:ok, _repo} = Repo.start_link()
    Ecto.Migrator.run(Repo, :up, all: true)

    {:ok, thread} = Channel.open_thread(%{title: "Tlön", scope: "machine"})

    on_exit(fn ->
      if Process.whereis(Repo), do: Repo.stop()
      _ = SQLite3.storage_down(config)
    end)

    %{thread_id: thread.id}
  end

  setup do
    test_pid = self()

    # spawn_pi_window materialises the entry's profile config dir — point the pi root at a tmp dir
    # so the suite never writes the real ~/.pi.
    pi_root = Path.join(System.tmp_dir!(), "aleph_roster_pi_#{System.unique_integer([:positive])}")
    prior = System.get_env("PI_CODING_AGENT_DIR")
    System.put_env("PI_CODING_AGENT_DIR", Path.join(pi_root, "agent"))

    Application.put_env(:console, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})
      if Enum.member?(args, "list-windows"), do: {"1\t0\ttertius\n", 0}, else: {"", 0}
    end)

    Application.put_env(:console, :tlon_join, fn thread_id, agent, opts ->
      send(test_pid, {:join, thread_id, agent, opts})
      {:ok, %{exports: ~s(export TLON_THREAD="#{thread_id}"\nexport TLON_AUTHOR="#{agent}")}}
    end)

    # The center reads as "already up" — a harmless real /bin/cat terminal keyed :machine — so
    # `ensure_center` no-ops (never touches Sessions.spawn_harness/materialise/tmux) and
    # `ensure_windows` proceeds straight to the tail dispatch under test.
    {:ok, _pid} = Sessions.ensure(:machine, cmd: "/bin/cat", cols: 4, rows: 4)

    on_exit(fn ->
      Application.delete_env(:console, :tlon_cmd)
      Application.delete_env(:console, :tlon_join)
      if prior, do: System.put_env("PI_CODING_AGENT_DIR", prior), else: System.delete_env("PI_CODING_AGENT_DIR")
      File.rm_rf!(pi_root)
    end)

    :ok
  end

  test "the seed cast's builder tail entry spawns a claude window: handle hronir-machine, window hronir" do
    assert %{} = Cockpit.ensure_workspace_roster(%{active_key: 0})

    assert_receive {:join, _tid, "hronir-machine", opts}
    assert opts[:mandate] == "machine"

    assert_receive {:tmux, ["-L", "console-workspace-0", "new-window", "-d", "-t", "w0", "-n", "hronir", script]}
    assert script =~ "modules/manos/claude-code/launch.sh"
    refute script =~ "PI_CODING_AGENT_DIR"
  end

  test "the center (already up) is not re-spawned — no new-session call" do
    Cockpit.ensure_workspace_roster(%{active_key: 0})
    refute_received {:tmux, ["-L", "console-workspace-0", "new-session" | _]}
  end

  test "a :pi tail entry spawns a windowed pi (bare pi_command), not the claude launcher" do
    # Slice D: the harness binds from model × environment (anthropic@home → claude_code), so pin
    # the WORK environment — there every archetype (the planner here) rides pi.
    System.put_env("TLON_ENV", "work")
    on_exit(fn -> System.delete_env("TLON_ENV") end)

    workspaces = [
      %{
        id: 99,
        name: "Freedonia",
        roster: [
          %{"archetype" => "surveyor", "name" => "rufus"},
          %{"archetype" => "planner", "name" => "borges"}
        ]
      }
    ]

    Cockpit.ensure_workspace_roster(%{active_key: 99}, Space.all(workspaces))

    assert_receive {:join, _tid, "borges-machine", opts}
    assert opts[:mandate] == "machine"

    assert_receive {:tmux, ["-L", "console-workspace-99", "new-window", "-d", "-t", "w99", "-n", "borges", script]}
    assert script =~ "PI_CODING_AGENT_DIR"
    refute script =~ "modules/manos/claude-code/launch.sh"
  end
end
