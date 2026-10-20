defmodule Server.ReleaseSmokeScriptTest do
  # scripts/release-smoke.sh: a candidate's office API must answer, and in shape. TLON_SMOKE_URL
  # points it at a server already up (here a stub), so nothing is built or started.
  use ExUnit.Case, async: true

  @script Path.expand("../../../scripts/release-smoke.sh", __DIR__)

  defmodule Stub do
    @moduledoc false
    @behaviour Plug

    @impl true
    def init(answer), do: answer

    @impl true
    def call(conn, {code, body}), do: Plug.Conn.send_resp(conn, code, body)
  end

  defmodule FlagStub do
    @moduledoc false
    @behaviour Plug

    @office ~s({"roster": [], "threads": [], "workspaces": [{"id": 1, "name": "elsewhere"}]})

    @impl true
    def init(known), do: known
    @impl true
    def call(%{method: "PATCH", path_info: ["api", "flags", flag]} = conn, known),
      do: Plug.Conn.send_resp(conn, if(flag in known, do: 200, else: 404), "{}")

    def call(conn, _known), do: Plug.Conn.send_resp(conn, 200, @office)
  end

  defp stub(answer, plug \\ Stub) do
    pid = start_supervised!({Bandit, plug: {plug, answer}, ip: {127, 0, 0, 1}, port: 0, startup_log: false})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  # a port nothing answers on now, so overlapping suite runs never meet on one
  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  # this checkout's own copy is the one under test, behind origin/main's or not (fresh-script.sh)
  defp smoke(url),
    do:
      System.cmd("bash", [@script],
        env: [{"TLON_SMOKE_URL", url}, {"TLON_STALE_SCRIPTS_OK", "1"}],
        stderr_to_stdout: true
      )

  test "a broken /api/office fails the smoke, saying so" do
    assert {out, 1} = smoke(stub({500, "boom"}))
    assert out =~ "/api/office answered 500"
  end

  test "an /api/office without the office's shape fails it" do
    assert {out, 1} = smoke(stub({200, ~s({"roster": "nope"})}))
    assert out =~ "/api/office"
  end

  test "TLON_SMOKE_FLAGS turns each flag on through the node's own API; a flag it doesn't know fails the smoke" do
    url = stub(["build_mode"], FlagStub)

    flagged =
      &System.cmd("bash", [@script],
        env: [{"TLON_SMOKE_URL", url}, {"TLON_SMOKE_FLAGS", &1}, {"TLON_STALE_SCRIPTS_OK", "1"}],
        stderr_to_stdout: true
      )

    {out, _} = flagged.("build_mode")
    assert out =~ "smoke: flag build_mode on"

    assert {out, 1} = flagged.("nope")
    assert out =~ "flag nope: /api/flags answered 404"
  end

  test "an office with no machine workspace says the drive won't wait for it" do
    office = ~s({"roster": [], "threads": [], "workspaces": [{"id": 1, "name": "elsewhere"}]})
    assert {out, 1} = smoke(stub({200, office}))
    assert out =~ "smoke: no wait for the office (no machine workspace)"
  end

  describe "the fetch of origin" do
    # a repo whose origin can't be fetched (a local path that isn't there): a smoke of a local ref
    # needs no fetch, so it must get past the fetch; a smoke of origin/main still needs it
    setup do
      tmp = Path.join(System.tmp_dir!(), "smoke-fetch-#{System.pid()}-#{System.unique_integer([:positive])}")
      root = Path.join(tmp, "repo")
      File.mkdir_p!(Path.join(root, "scripts/lib"))

      for f <- ~w(release-smoke.sh git-fetch-origin.sh smoke-sweep.sh lib/seed-hex.sh lib/fresh-script.sh) do
        File.cp!(Path.expand("../../../scripts/#{f}", __DIR__), Path.join([root, "scripts", f]))
      end

      git = fn args -> {_, 0} = System.cmd("git", ["-C", root | args], stderr_to_stdout: true) end
      git.(["init", "-q", "-b", "main"])
      git.(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"])
      git.(["branch", "work/feature"])
      git.(["remote", "add", "origin", Path.join(tmp, "no-such-origin")])
      # the smoke's sweep drops every unlocked tlon_smoke_* database: never the machine's Postgres
      bin = Path.join(tmp, "bin")
      File.mkdir_p!(bin)
      File.write!(Path.join(bin, "psql"), "#!/bin/sh\nexit 0\n")
      File.chmod!(Path.join(bin, "psql"), 0o755)
      on_exit(fn -> File.rm_rf!(tmp) end)
      %{tmp: tmp, root: root, port: free_port()}
    end

    defp run_smoke(%{tmp: tmp, root: root, port: port}, args, extra_env \\ []) do
      env = [
        {"TMPDIR", tmp},
        {"SANDBOX_RUNTIME", nil},
        {"PATH", Path.join(tmp, "bin") <> ":" <> System.get_env("PATH")},
        {"TLON_SMOKE_PORT", "#{port}"},
        {"TLON_SMOKE_DATABASE", "tlon_smoke_fetch_#{port}"}
      ]

      env = Enum.uniq_by(extra_env ++ env, &elem(&1, 0))

      System.cmd("bash", [Path.join([root, "scripts", "release-smoke.sh"]) | args], env: env, stderr_to_stdout: true)
    end

    test "a smoke of a local work/<slug> ref goes on past a failed fetch", ctx do
      {out, _} = run_smoke(ctx, ["work/feature"])

      refute out =~ "smoke FAILED: can't fetch origin"
      assert out =~ ~r/smoke: [0-9a-f]{7} on :#{ctx.port}/
    end

    test "a smoke of origin/main still fails when origin can't be fetched", ctx do
      assert {out, 1} = run_smoke(ctx, [])
      assert out =~ "smoke FAILED: can't fetch origin"
    end

    test "a smoke that can't reach Postgres (a sandboxed Bash) says to run it unsandboxed, before any build",
         %{tmp: tmp} = ctx do
      File.write!(Path.join([tmp, "bin", "psql"]), "#!/bin/sh\necho 'psql: error: '; exit 2\n")

      assert {out, 1} = run_smoke(ctx, ["work/feature"])
      assert out =~ "smoke FAILED: can't reach Postgres"
      assert out =~ "unsandboxed"
      refute File.exists?(Path.join(tmp, "tlon-smoke"))
    end

    test "a sandboxed smoke is refused in one line, before it touches anything", %{tmp: tmp} = ctx do
      assert {out, 1} = run_smoke(ctx, ["work/feature"], [{"SANDBOX_RUNTIME", "1"}])
      assert String.trim(out) == "smoke FAILED: this is a sandboxed Bash: run release:smoke unsandboxed"
      refute File.exists?(Path.join(tmp, "tlon-smoke"))
    end

    test "a second smoke of a commit already being smoked refuses, naming the run", %{tmp: tmp, root: root} = ctx do
      {sha, 0} = System.cmd("git", ["-C", root, "rev-parse", "work/feature"])
      lock = Path.join(tmp, "tlon-smoke-commit-#{String.trim(sha)}.lock")
      File.write!(lock, "pid 123 on http://127.0.0.1:4777\n")
      hold_lock(lock)

      assert {out, 1} = run_smoke(ctx, ["work/feature"])
      assert out =~ "is already being smoked (pid 123 on http://127.0.0.1:4777)"
      refute File.exists?(Path.join(tmp, "tlon-smoke"))
    end

    # a record a holder wrote long ago: a pid from another sandbox's namespace means nothing here,
    # so only a url that answers, a pid that lives, or a record too young to be a finished build says the holder is real
    defp stale_lock(tmp, root, record) do
      {sha, 0} = System.cmd("git", ["-C", root, "rev-parse", "work/feature"])
      lock = Path.join(tmp, "tlon-smoke-commit-#{String.trim(sha)}.lock")
      File.write!(lock, record)
      File.touch!(lock, {{2020, 1, 1}, {0, 0, 0}})
      hold_lock(lock)
    end

    test "a holder that is gone (no such pid, nothing on its url, an old record) is reclaimed, not refused",
         %{tmp: tmp, root: root} = ctx do
      # above PID_MAX_LIMIT: a pid no process can hold
      stale_lock(tmp, root, "pid 9999999 on http://127.0.0.1:4777\n")

      {out, _} = run_smoke(ctx, ["work/feature"])

      refute out =~ "already being smoked"
      assert out =~ "smoke: reclaiming the lock on"
      assert out =~ ~r/smoke: [0-9a-f]{7} on :#{ctx.port}/
    end

    test "an old record whose pid lives is a live holder: refused", %{tmp: tmp, root: root} = ctx do
      stale_lock(tmp, root, "pid #{System.pid()} on http://127.0.0.1:#{free_port()}\n")

      assert {out, 1} = run_smoke(ctx, ["work/feature"])
      assert out =~ "is already being smoked (pid #{System.pid()} on"
      refute out =~ "reclaiming"
    end

    test "a record is truncated, so a shorter one leaves no tail of the last run's", %{tmp: tmp, root: root} = ctx do
      {sha, 0} = System.cmd("git", ["-C", root, "rev-parse", "work/feature"])
      lock = Path.join(tmp, "tlon-smoke-commit-#{String.trim(sha)}.lock")
      File.write!(lock, "pid 1 on http://127.0.0.1:1/" <> String.duplicate("x", 200) <> "\n")

      run_smoke(ctx, ["work/feature"])

      assert File.read!(lock) =~ ~r/\Apid \d+ on http:\/\/127\.0\.0\.1:#{ctx.port}\n\z/
    end

    test "an old record whose url still answers is a live holder: refused", %{tmp: tmp, root: root} = ctx do
      url = stub({200, "{}"})
      stale_lock(tmp, root, "pid 9999999 on #{url}\n")

      assert {out, 1} = run_smoke(ctx, ["work/feature"])
      assert out =~ "is already being smoked (pid 9999999 on #{url})"
    end
  end

  # a lock held by another process for as long as the test needs it
  defp hold_lock(lock) do
    port =
      Port.open({:spawn_executable, System.find_executable("bash")}, [
        :binary,
        args: ["-c", ~s(exec 9<"$0"; flock 9; echo held; exec sleep 60), lock]
      ])

    assert_receive {^port, {:data, "held\n"}}, 5_000
    {:os_pid, pid} = Port.info(port, :os_pid)
    on_exit(fn -> System.cmd("kill", ["#{pid}"]) end)
    pid
  end

  describe "two smokes at once" do
    # the sweep a smoke ran before the build lock (c44fc5c), still in every checkout branched before
    # it, on a host where another user's /proc/<pid>/cwd can't be read: its cwd test is always false,
    # so a build no process names in its command line goes
    @old_sweep ~S"""
    set -uo pipefail
    root="$1"
    for stale in "${TMPDIR:-/tmp}"/tlon-smoke-*/; do
      stale="${stale%/}"; [ -d "$stale/server" ] || continue
      pgrep -f "$stale/" >/dev/null && continue
      git -C "$root" worktree remove --force "$stale" >/dev/null 2>&1; rm -rf "$stale"
    done
    """

    setup do
      tmp = Path.join(System.tmp_dir!(), "smoke-race-#{System.pid()}-#{System.unique_integer([:positive])}")
      root = Path.join(tmp, "repo")
      stubs = Path.join(tmp, "bin")
      signal = Path.join(tmp, "signal")

      Enum.each(
        [Path.join(root, "scripts/lib"), Path.join(root, "server"), Path.join(root, "office"), stubs, signal],
        &File.mkdir_p!/1
      )

      for f <- ~w(release-smoke.sh git-fetch-origin.sh smoke-sweep.sh lib/seed-hex.sh lib/fresh-script.sh) do
        File.cp!(Path.expand("../../../scripts/#{f}", __DIR__), Path.join([root, "scripts", f]))
      end

      File.write!(Path.join([root, "server", "mix.exs"]), "")
      File.write!(Path.join([root, "office", "package.json"]), "{}")
      git = fn args -> {_, 0} = System.cmd("git", ["-C", root | args], stderr_to_stdout: true) end
      git.(["init", "-q", "-b", "main"])
      git.(["add", "-A"])
      git.(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"])
      git.(["branch", "work/feature"])
      git.(["remote", "add", "origin", Path.join(tmp, "no-such-origin")])

      # the build: `mix release` holds until the test says go, then says whether its build dir is still there
      stub(stubs, "mix", ~S"""
      [ "$1" = release ] || exit 0
      touch "$SMOKE_SIGNAL/building"
      until [ -e "$SMOKE_SIGNAL/go" ]; do sleep 0.1; done
      if [ -d "$PWD" ]; then echo kept; else echo swept; fi >"$SMOKE_SIGNAL/result"
      """)

      for tool <- ~w(mise bun psql), do: stub(stubs, tool, "exit 0")
      on_exit(fn -> File.rm_rf!(tmp) end)
      %{tmp: tmp, root: root, stubs: stubs, signal: signal}
    end

    defp stub(dir, name, body) do
      path = Path.join(dir, name)
      File.write!(path, "#!/usr/bin/env bash\n" <> body)
      File.chmod!(path, 0o755)
    end

    defp wait_for(path, tries \\ 200) do
      cond do
        File.exists?(path) -> :ok
        tries == 0 -> flunk("#{path} never appeared")
        true -> Process.sleep(100) && wait_for(path, tries - 1)
      end
    end

    defp race_env(ctx, port) do
      [
        {"TMPDIR", ctx.tmp},
        {"SANDBOX_RUNTIME", nil},
        {"PATH", ctx.stubs <> ":" <> System.get_env("PATH")},
        {"SMOKE_SIGNAL", ctx.signal},
        {"TLON_SMOKE_PORT", "#{port}"},
        {"TLON_SMOKE_DATABASE", "tlon_smoke_race_#{port}"}
      ]
    end

    test "a failed build stops the smoke at the build, not at a bin/server that isn't there", ctx do
      stub(ctx.stubs, "mix", ~S"""
      [ "$1" = release ] && { echo "mix release: boom"; exit 1; }
      exit 0
      """)

      script = Path.join([ctx.root, "scripts", "release-smoke.sh"])
      env = race_env(ctx, free_port())
      assert {out, 1} = System.cmd("bash", [script, "work/feature"], env: env, stderr_to_stdout: true)
      assert out =~ "mix release: boom"
      assert out =~ "the build or the migration of"
      refute out =~ "No such file"
    end

    test "a held smoke ends at TLON_SMOKE_HOLD_TTL, saying so, and tears its node down", ctx do
      port = free_port()
      office = ~s({"roster": [], "threads": [], "workspaces": [{"id": 1, "name": "machine"}], "id": 7})

      # the smoke refuses a port that already answers: the stub node comes up once the build is running
      stub(ctx.stubs, "mix", ~S"""
      [ "$1" = release ] || exit 0
      touch "$SMOKE_SIGNAL/building"
      until [ -e "$SMOKE_SIGNAL/go" ]; do sleep 0.1; done
      mkdir -p _build/prod/rel/server/bin
      printf '#!/bin/sh\n[ "$1" = start ] && exec sleep 300\nexit 0\n' >_build/prod/rel/server/bin/server
      chmod +x _build/prod/rel/server/bin/server
      """)

      drive = Path.join([ctx.root, "scripts", "office-drive.sh"])

      File.write!(drive, ~S"""
      #!/bin/sh
      t="${3#\'}"; t="${t%\'}"
      printf '=== after: .\nHOME\n=== after: Enter\n#7  %s\n=== after: c\nCREW\n=== after: R\nHOME\n' "$t"
      """)

      File.chmod!(drive, 0o755)
      # the smoke drives the office from its checkout of the commit
      for args <- [
            ["add", "-A"],
            ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "drive"],
            ["branch", "-f", "work/feature"]
          ],
          do: {_, 0} = System.cmd("git", ["-C", ctx.root | args], stderr_to_stdout: true)

      script = Path.join([ctx.root, "scripts", "release-smoke.sh"])
      env = [{"TLON_SMOKE_HOLD", "1"}, {"TLON_SMOKE_HOLD_TTL", "2"} | race_env(ctx, port)]

      # timeout: without the TTL check the hold never ends, and the test fails instead of hanging
      smoke =
        Task.async(fn ->
          System.cmd("timeout", ["20", "bash", script, "work/feature"], env: env, stderr_to_stdout: true)
        end)

      wait_for(Path.join(ctx.signal, "building"))
      start_supervised!({Bandit, plug: {Stub, {200, office}}, ip: {127, 0, 0, 1}, port: port, startup_log: false})
      File.write!(Path.join(ctx.signal, "go"), "")

      assert {out, 0} = Task.await(smoke, 30_000)
      assert out =~ "smoke: holding"
      assert out =~ "the hold of http://127.0.0.1:#{port} expired after 2s"
    end

    test "the office drive waits for the title before the find and for the thread after Enter", ctx do
      port = free_port()
      office = ~s({"roster": [], "threads": [], "workspaces": [{"id": 1, "name": "machine"}], "id": 7})

      stub(ctx.stubs, "mix", ~S"""
      [ "$1" = release ] || exit 0
      touch "$SMOKE_SIGNAL/building"
      until [ -e "$SMOKE_SIGNAL/go" ]; do sleep 0.1; done
      mkdir -p _build/prod/rel/server/bin
      printf '#!/bin/sh\n[ "$1" = start ] && exec sleep 300\nexit 0\n' >_build/prod/rel/server/bin/server
      chmod +x _build/prod/rel/server/bin/server
      """)

      # supports wait:TEXT (the smoke only waits when the candidate's drive says so)
      drive = Path.join([ctx.root, "scripts", "office-drive.sh"])

      File.write!(drive, ~S"""
      #!/bin/sh
      printf '%s\n' "$@" >"$SMOKE_SIGNAL/drive.args"
      for a in "$@"; do case "$a" in \'*) t="${a#\'}"; t="${t%\'}" ;; wait:*) ;; esac; done
      printf '=== after: .\nHOME\n=== after: Enter\n#7  %s\n=== after: c\nCREW\n=== after: R\nHOME\n' "$t"
      """)

      File.chmod!(drive, 0o755)

      for args <- [
            ["add", "-A"],
            ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "drive"],
            ["branch", "-f", "work/feature"]
          ],
          do: {_, 0} = System.cmd("git", ["-C", ctx.root | args], stderr_to_stdout: true)

      script = Path.join([ctx.root, "scripts", "release-smoke.sh"])
      env = [{"TLON_SMOKE_HOLD", "1"}, {"TLON_SMOKE_HOLD_TTL", "2"} | race_env(ctx, port)]

      smoke =
        Task.async(fn ->
          System.cmd("timeout", ["20", "bash", script, "work/feature"], env: env, stderr_to_stdout: true)
        end)

      wait_for(Path.join(ctx.signal, "building"))
      start_supervised!({Bandit, plug: {Stub, {200, office}}, ip: {127, 0, 0, 1}, port: port, startup_log: false})
      File.write!(Path.join(ctx.signal, "go"), "")
      Task.await(smoke, 30_000)

      args = ctx.signal |> Path.join("drive.args") |> File.read!() |> String.split("\n", trim: true)
      slash = Enum.find_index(args, &(&1 == "/"))
      enter = Enum.find_index(args, &(&1 == "Enter"))

      assert Enum.any?(Enum.take(args, slash), &(&1 =~ ~r/^wait:release smoke \d+$/))
      assert Enum.at(args, enter + 1) =~ ~r/^wait:#7  release smoke \d+$/
    end

    defp stale_lock_in(ctx) do
      {sha, 0} = System.cmd("git", ["-C", ctx.root, "rev-parse", "work/feature"])
      lock = Path.join(ctx.tmp, "tlon-smoke-commit-#{String.trim(sha)}.lock")
      File.write!(lock, "pid 9999999 on http://127.0.0.1:#{free_port()}\n")
      File.touch!(lock, {{2020, 1, 1}, {0, 0, 0}})
      lock
    end

    defp build_stub(ctx) do
      stub(ctx.stubs, "mix", ~S"""
      [ "$1" = release ] || exit 0
      echo build >>"$SMOKE_SIGNAL/builds"
      until [ -e "$SMOKE_SIGNAL/go" ]; do sleep 0.1; done
      """)
    end

    # the staleness check of the lock, answered and then held until `release` says go: what the run saw is
    # settled before anything else moves
    defp hold_staleness_check(ctx, release) do
      stub(ctx.stubs, "find", ~s"""
      out="$(PATH="${PATH#*:}" find "$@")"
      case "$*" in *"-mmin +20"*)
        touch "$SMOKE_SIGNAL/arrived.$$"
        #{release}
      ;; esac
      printf '%s' "$out"
      """)
    end

    defp smoke_async(ctx) do
      script = Path.join([ctx.root, "scripts", "release-smoke.sh"])
      env = race_env(ctx, free_port())
      Task.async(fn -> System.cmd("bash", [script, "work/feature"], env: env, stderr_to_stdout: true) end)
    end

    defp until_free(lock, tries \\ 100) do
      case System.cmd("flock", ["-n", lock, "true"]) do
        {_, 0} -> :ok
        _ when tries == 0 -> flunk("#{lock} stays held")
        _ -> Process.sleep(50) && until_free(lock, tries - 1)
      end
    end

    defp wait_for_count(glob, n, tries \\ 200) do
      cond do
        length(Path.wildcard(glob)) >= n -> :ok
        tries == 0 -> flunk("#{glob} never reached #{n}")
        true -> Process.sleep(50) && wait_for_count(glob, n, tries - 1)
      end
    end

    test "two smokes reclaiming one stale lock at once: exactly one builds", ctx do
      hold_lock(stale_lock_in(ctx))
      build_stub(ctx)

      # both read the stale record before either reclaims; the first to arrive goes on once the other has
      # arrived, the other goes on once the first is building
      hold_staleness_check(ctx, ~S"""
        if mkdir "$SMOKE_SIGNAL/first" 2>/dev/null; then
          for _ in $(seq 100); do [ "$(ls "$SMOKE_SIGNAL" | grep -c '^arrived\.')" -ge 2 ] && break; sleep 0.1; done
        else
          for _ in $(seq 100); do [ -e "$SMOKE_SIGNAL/builds" ] && break; sleep 0.1; done
        fi
      """)

      smokes = [smoke_async(ctx), smoke_async(ctx)]
      wait_for(Path.join(ctx.signal, "builds"))
      File.write!(Path.join(ctx.signal, "go"), "")
      Task.await_many(smokes, 30_000)

      assert File.read!(Path.join(ctx.signal, "builds")) == "build\n"
    end

    test "a smoke that takes the lock while a reclaimer weighs its holder is not built over", ctx do
      lock = stale_lock_in(ctx)
      holder = hold_lock(lock)
      build_stub(ctx)

      hold_staleness_check(ctx, ~S"""
        for _ in $(seq 100); do [ -e "$SMOKE_SIGNAL/release" ] && break; sleep 0.1; done
      """)

      reclaimer = smoke_async(ctx)
      wait_for_count(Path.join(ctx.signal, "arrived.*"), 1)

      # the holder lets go; a new smoke takes the same file and builds
      System.cmd("kill", ["#{holder}"])
      until_free(lock)
      newcomer = smoke_async(ctx)
      wait_for(Path.join(ctx.signal, "builds"))
      File.write!(Path.join(ctx.signal, "release"), "")
      # the newcomer keeps building until the reclaimer is done, or has gone on to build too
      result = Task.yield(reclaimer, 5_000)
      File.write!(Path.join(ctx.signal, "go"), "")
      {out, 1} = if result, do: elem(result, 1), else: Task.await(reclaimer, 30_000)
      Task.await(newcomer, 30_000)

      assert out =~ "is already being smoked"
      assert File.read!(Path.join(ctx.signal, "builds")) == "build\n"
    end

    test "the lock to reclaim is not held by what a reclaiming run started", ctx do
      hold_lock(stale_lock_in(ctx))
      build_stub(ctx)

      smoke = smoke_async(ctx)
      wait_for(Path.join(ctx.signal, "builds"))
      assert {_, 0} = System.cmd("flock", ["-n", Enum.at(Path.wildcard(Path.join(ctx.tmp, "*.reclaim")), 0), "true"])
      File.write!(Path.join(ctx.signal, "go"), "")
      Task.await(smoke, 30_000)
    end

    test "a smoke from a checkout older than the build lock leaves a running smoke's build alone", ctx do
      env = race_env(ctx, free_port())

      script = Path.join([ctx.root, "scripts", "release-smoke.sh"])
      smoke = Task.async(fn -> System.cmd("bash", [script, "work/feature"], env: env, stderr_to_stdout: true) end)
      wait_for(Path.join(ctx.signal, "building"))

      {_, 0} =
        System.cmd("bash", ["-c", @old_sweep, "sweep", ctx.root], env: [{"TMPDIR", ctx.tmp}], stderr_to_stdout: true)

      File.write!(Path.join(ctx.signal, "go"), "")
      Task.await(smoke, 30_000)

      assert File.read!(Path.join(ctx.signal, "result")) == "kept\n"
    end
  end

  describe "smoke-sweep.sh: what a SIGKILLed smoke left behind" do
    @sweep Path.expand("../../../scripts/smoke-sweep.sh", __DIR__)

    setup do
      tmp = Path.join(System.tmp_dir!(), "smoke-sweep-#{System.pid()}-#{System.unique_integer([:positive])}")
      root = Path.join(tmp, "repo")
      bin = Path.join(tmp, "bin")
      File.mkdir_p!(root)
      File.mkdir_p!(bin)
      {_, 0} = System.cmd("git", ["-C", root, "init", "-q"])

      # never the machine's Postgres: the listing answers $SMOKE_DBS, and every other call is logged
      File.write!(Path.join(bin, "psql"), ~S"""
      #!/usr/bin/env bash
      case "$*" in
        *"from pg_database"*) [ -n "$SMOKE_DBS" ] && printf '%s\n' $SMOKE_DBS ;;
        *) printf '%s\n' "${@: -1}" >>"$SMOKE_PSQL_LOG" ;;
      esac
      """)

      File.chmod!(Path.join(bin, "psql"), 0o755)
      on_exit(fn -> File.rm_rf!(tmp) end)
      %{tmp: tmp, root: root, bin: bin}
    end

    defp sweep(ctx, dbs \\ "") do
      log = Path.join(ctx.tmp, "psql.log")

      env = [
        {"TMPDIR", ctx.tmp},
        {"PATH", ctx.bin <> ":" <> System.get_env("PATH")},
        {"SMOKE_DBS", dbs},
        {"SMOKE_PSQL_LOG", log}
      ]

      {_, 0} = System.cmd("bash", [@sweep, ctx.root], env: env, stderr_to_stdout: true)
      if File.exists?(log), do: String.split(File.read!(log), "\n", trim: true), else: []
    end

    defp build(tmp, name) do
      dir = Path.join(tmp, name)
      File.mkdir_p!(Path.join(dir, "server"))
      dir
    end

    # a run's lock, held by another process for as long as the test needs it
    defp hold(lock) do
      port =
        Port.open({:spawn_executable, System.find_executable("bash")}, [
          :binary,
          args: ["-c", ~s(exec 9>"$0"; flock 9; echo held; exec sleep 60), lock]
        ])

      assert_receive {^port, {:data, "held\n"}}, 5_000
      {:os_pid, pid} = Port.info(port, :os_pid)
      on_exit(fn -> System.cmd("kill", ["#{pid}"]) end)
    end

    test "a build whose run holds its lock stays; one whose lock nobody holds goes", %{tmp: tmp} = ctx do
      live = build(tmp, "tlon-smoke/live")
      hold(live <> ".lock")
      dead = build(tmp, "tlon-smoke/dead")
      File.write!(dead <> ".lock", "")

      sweep(ctx)

      assert File.dir?(live)
      refute File.exists?(dead)
      refute File.exists?(dead <> ".lock")
    end

    test "with no lock (a run from before it), only a build older than any build takes goes", %{tmp: tmp} = ctx do
      fresh = build(tmp, "tlon-smoke-fresh")
      old = build(tmp, "tlon-smoke-old")
      {_, 0} = System.cmd("touch", ["-d", "3 hours ago", old])
      unbuilt = Path.join(tmp, "tlon-smoke-checking-out")
      File.mkdir_p!(unbuilt)

      sweep(ctx)

      assert File.dir?(fresh)
      refute File.exists?(old)
      assert File.dir?(unbuilt)
    end

    test "a run killed before its checkout: its dir goes once its lock is free, and a lock whose dir is gone goes",
         %{tmp: tmp} = ctx do
      early = Path.join(tmp, "tlon-smoke/early")
      File.mkdir_p!(early)
      File.write!(early <> ".lock", "")
      checking_out = Path.join(tmp, "tlon-smoke/checking-out")
      File.mkdir_p!(checking_out)
      hold(checking_out <> ".lock")
      orphan = Path.join(tmp, "tlon-smoke/gone.lock")
      File.write!(orphan, "")
      held = Path.join(tmp, "tlon-smoke/starting.lock")
      hold(held)

      sweep(ctx)

      refute File.exists?(early)
      refute File.exists?(early <> ".lock")
      assert File.dir?(checking_out)
      refute File.exists?(orphan)
      assert File.exists?(held)
    end

    test "a smoke database goes unless its run holds the database's lock; the lock goes with it", %{root: root} = ctx do
      locks = Path.join(root, ".git")
      hold(Path.join(locks, "tlon-smoke-db-tlon_smoke_live.lock"))
      File.write!(Path.join(locks, "tlon-smoke-db-tlon_smoke_killed.lock"), "")

      dropped = sweep(ctx, "tlon_smoke_live tlon_smoke_killed tlon_smoke_unrecorded")

      assert dropped == [
               ~s(DROP DATABASE IF EXISTS "tlon_smoke_killed"),
               ~s(DROP DATABASE IF EXISTS "tlon_smoke_unrecorded")
             ]

      assert File.exists?(Path.join(locks, "tlon-smoke-db-tlon_smoke_live.lock"))
      refute File.exists?(Path.join(locks, "tlon-smoke-db-tlon_smoke_killed.lock"))
      refute File.exists?(Path.join(locks, "tlon-smoke-db-tlon_smoke_unrecorded.lock"))
    end
  end
end
