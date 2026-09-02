defmodule Console.CockpitThreadSessionsTest do
  @moduledoc """
  Per-thread leaf sessions (per-thread-agents Slice A): `ensure_thread_sessions/2` spawns a
  dedicated window for EVERY worker-archetype lead — claude AND pi harness — dispatched by the
  lead's roster profile, through the same `:tlon_cmd`/`:tlon_join` seams as
  `Console.CockpitRosterTest`. A meta (surveyor) lead never gets a leaf window: it is the vantage,
  not a worker. Boots its own temp DB (staffed threads are a real Repo read), so not async.
  """
  use ExUnit.Case, async: false

  alias Console.Cockpit
  alias Console.Space
  alias Server.Channel
  alias Server.Staff

  @workspaces [
    %{
      id: 99,
      name: "Freedonia",
      roster: [
        %{"archetype" => "surveyor", "name" => "rufus"},
        %{"archetype" => "builder", "name" => "hronir"},
        %{"archetype" => "planner", "name" => "borges"}
      ]
    }
  ]

  setup_all do
    Console.TestRepo.boot!("cockpit-thread-sessions")

    for handle <- ["rufus-machine", "hronir-machine", "borges-machine"] do
      {:ok, _} = Staff.register_agent(%{name: handle, mandate: "machine", engine: "test"})
    end

    :ok
  end

  setup do
    test_pid = self()

    # spawn_pi_window materialises the lead's profile config dir — point the pi root at a tmp dir
    # so the suite never writes the real ~/.pi.
    pi_root = Path.join(System.tmp_dir!(), "aleph_thread_sessions_pi_#{System.unique_integer([:positive])}")
    prior = System.get_env("PI_CODING_AGENT_DIR")
    System.put_env("PI_CODING_AGENT_DIR", Path.join(pi_root, "agent"))

    Application.put_env(:console, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})
      if Enum.member?(args, "list-windows"), do: {"1\t0\trufus\n", 0}, else: {"", 0}
    end)

    Application.put_env(:console, :tlon_join, fn thread_id, agent, opts ->
      send(test_pid, {:join, thread_id, agent, opts})
      {:ok, %{exports: ~s(export TLON_THREAD="#{thread_id}"\nexport TLON_AUTHOR="#{agent}")}}
    end)

    # Each test stages its own thread — clear the previous test's so a stale staffed thread can't
    # produce an extra spawn the refute_receive assertions would trip on.
    {:ok, _} = Channel.clear_machine_threads()

    on_exit(fn ->
      Application.delete_env(:console, :tlon_cmd)
      Application.delete_env(:console, :tlon_join)
      if prior, do: System.put_env("PI_CODING_AGENT_DIR", prior), else: System.delete_env("PI_CODING_AGENT_DIR")
      File.rm_rf!(pi_root)
    end)

    :ok
  end

  defp staffed_thread(handle) do
    {:ok, thread} = Channel.open_thread(%{title: "task for #{handle}", scope: "machine"})
    {:ok, _} = Channel.assign_lead(thread.id, handle)
    thread
  end

  defp state,
    do: %{
      active_key: 99,
      standing_thread_id: nil,
      thread_spawn_retry: %{},
      opening_injected: MapSet.new(),
      opening_text_at: %{},
      parked_noted: MapSet.new()
    }

  test "a pi-harness worker lead gets its own leaf window (the Slice A isolation fix)" do
    # Slice D: the WORK environment binds the (anthropic-model) planner to pi; at home it would
    # ride claude_code like every anthropic archetype.
    System.put_env("TLON_ENV", "work")
    on_exit(fn -> System.delete_env("TLON_ENV") end)

    thread = staffed_thread("borges-machine")

    Cockpit.ensure_thread_sessions(state(), Space.all(@workspaces))

    assert_receive {:join, tid, "borges-machine", opts}
    assert tid == thread.id
    assert opts[:mandate] == "machine"

    # Slice C: a HUMAN window name (`<archetype>-<title-slug>`), not `t<id>` …
    window = "planner-task-for-borges-machine"
    assert_receive {:tmux, ["-L", "console-workspace-99", "new-window", "-d", "-t", "w99", "-n", ^window, script]}
    assert script =~ "PI_CODING_AGENT_DIR"
    refute script =~ "modules/adapters/claude-code/launch.sh"

    # … with the thread id stamped as the `@funes_thread` routing key, so nothing parses the name.
    thread_tag = "#{thread.id}"
    target = "w99:=" <> window

    assert_receive {:tmux,
                    ["-L", "console-workspace-99", "set-option", "-w", "-t", ^target, "@funes_thread", ^thread_tag]}
  end

  test "a claude-harness worker lead still gets its claude leaf window (regression)" do
    thread = staffed_thread("hronir-machine")

    Cockpit.ensure_thread_sessions(state(), Space.all(@workspaces))

    assert_receive {:join, _tid, "hronir-machine", _opts}

    window = "builder-task-for-hronir-machine"
    assert_receive {:tmux, ["-L", "console-workspace-99", "new-window", "-d", "-t", "w99", "-n", ^window, script]}
    assert script =~ "modules/adapters/claude-code/launch.sh"
    refute script =~ "PI_CODING_AGENT_DIR"

    thread_tag = "#{thread.id}"
    target = "w99:=" <> window

    assert_receive {:tmux,
                    ["-L", "console-workspace-99", "set-option", "-w", "-t", ^target, "@funes_thread", ^thread_tag]}
  end

  test "a live `@funes_thread`-tagged window suppresses a respawn — the routing map, not the name, is the identity" do
    thread = staffed_thread("borges-machine")
    test_pid = self()

    Application.put_env(:console, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})

      if Enum.member?(args, "list-windows"),
        do: {"1\t0\trufus\t\n0\t1\tanything-at-all\t#{thread.id}\n", 0},
        else: {"", 0}
    end)

    Cockpit.ensure_thread_sessions(state(), Space.all(@workspaces))

    refute_receive {:tmux, ["-L", _, "new-window" | _]}, 50
  end

  test "a meta (surveyor) lead never gets a leaf window — the vantage is not a worker" do
    staffed_thread("rufus-machine")

    Cockpit.ensure_thread_sessions(state(), Space.all(@workspaces))

    refute_receive {:tmux, ["-L", _, "new-window" | _]}, 50
  end

  test "a restart can't replay the opening turn — the phase lives on the window (@funes_opening)" do
    thread = staffed_thread("borges-machine")
    test_pid = self()

    # A DONE-tagged live leaf + a fresh cockpit (empty opening state): nothing is typed or sent.
    Application.put_env(:console, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})

      if Enum.member?(args, "list-windows"),
        do: {"1\t0\trufus\t\t\n0\t1\tplanner-task\t#{thread.id}\tdone\n", 0},
        else: {"", 0}
    end)

    Cockpit.ensure_thread_sessions(state(), Space.all(@workspaces))
    refute_receive {:tmux, ["-L", _, "send-keys" | _]}, 50
  end

  test "a TYPED-tagged leaf after a restart submits immediately and tags done (text settled long ago)" do
    thread = staffed_thread("borges-machine")
    test_pid = self()

    Application.put_env(:console, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})

      if Enum.member?(args, "list-windows"),
        do: {"1\t0\trufus\t\t\n0\t1\tplanner-task\t#{thread.id}\ttyped\n", 0},
        else: {"", 0}
    end)

    Cockpit.ensure_thread_sessions(state(), Space.all(@workspaces))

    assert_receive {:tmux, ["-L", "console-workspace-99", "send-keys", "-t", "w99:1", "Enter"]}
    assert_receive {:tmux, ["-L", "console-workspace-99", "set-option", "-w", "-t", "w99:1", "@funes_opening", "done"]}
  end

  test "the leaf cap parks spawns past the budget — no new-window, a one-time note" do
    prior_cfg = Application.get_env(:console, :config_path)
    cfg = Path.join(System.tmp_dir!(), "aleph_cap_#{System.unique_integer([:positive])}.json")
    File.write!(cfg, ~s({"max_leaves": 1}))
    Application.put_env(:console, :config_path, cfg)

    on_exit(fn ->
      Application.put_env(:console, :config_path, prior_cfg)
      File.rm(cfg)
    end)

    thread = staffed_thread("borges-machine")
    test_pid = self()

    # One live leaf already occupies the only seat.
    Application.put_env(:console, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})

      if Enum.member?(args, "list-windows"),
        do: {"1\t0\trufus\t\t\n0\t1\tbuilder-busy\t424242\tdone\n", 0},
        else: {"", 0}
    end)

    Cockpit.ensure_thread_sessions(state(), Space.all(@workspaces))

    refute_receive {:tmux, ["-L", _, "new-window" | _]}, 50
    assert [%{body: body}] = Channel.thread_messages(Channel.thread(thread.id))
    assert body =~ "parked"
  end

  test "an orphan leaf window (thread closed/cleared while aleph was down) is swept" do
    thread = staffed_thread("borges-machine")
    test_pid = self()

    # One live tagged leaf (kept), one tagged for a vanished thread, one legacy t<id> orphan —
    # and the untagged center/tail windows, which are never sweep candidates.
    Application.put_env(:console, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})

      if Enum.member?(args, "list-windows"),
        do: {"1\t0\trufus\t\n0\t1\tplanner-live\t#{thread.id}\n0\t2\treviewer-stale\t999888\n0\t3\tt777666\t\n", 0},
        else: {"", 0}
    end)

    Cockpit.ensure_thread_sessions(state(), Space.all(@workspaces))

    assert_receive {:tmux, ["-L", "console-workspace-99", "kill-window", "-t", "w99:2"]}
    assert_receive {:tmux, ["-L", "console-workspace-99", "kill-window", "-t", "w99:3"]}
    refute_receive {:tmux, ["-L", _, "kill-window", "-t", "w99:0"]}, 20
    refute_receive {:tmux, ["-L", _, "kill-window", "-t", "w99:1"]}, 20
  end

  test "the standing thread is excluded — the center already runs it" do
    thread = staffed_thread("borges-machine")

    Cockpit.ensure_thread_sessions(%{state() | standing_thread_id: thread.id}, Space.all(@workspaces))

    refute_receive {:tmux, ["-L", _, "new-window" | _]}, 50
  end
end
