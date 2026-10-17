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

  defp stub(answer) do
    pid = start_supervised!({Bandit, plug: {Stub, answer}, ip: {127, 0, 0, 1}, port: 0, startup_log: false})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  defp smoke(url), do: System.cmd("bash", [@script], env: [{"TLON_SMOKE_URL", url}], stderr_to_stdout: true)

  test "a broken /api/office fails the smoke, saying so" do
    assert {out, 1} = smoke(stub({500, "boom"}))
    assert out =~ "/api/office answered 500"
  end

  test "an /api/office without the office's shape fails it" do
    assert {out, 1} = smoke(stub({200, ~s({"roster": "nope"})}))
    assert out =~ "/api/office"
  end

  describe "the fetch of origin" do
    # a repo whose origin can't be fetched (a local path that isn't there): a smoke of a local ref
    # needs no fetch, so it must get past the fetch; a smoke of origin/main still needs it
    setup do
      tmp = Path.join(System.tmp_dir!(), "smoke-fetch-#{System.pid()}-#{System.unique_integer([:positive])}")
      root = Path.join(tmp, "repo")
      File.mkdir_p!(Path.join(root, "scripts"))

      for f <- ~w(release-smoke.sh git-fetch-origin.sh smoke-sweep.sh) do
        File.cp!(Path.expand("../../../scripts/#{f}", __DIR__), Path.join([root, "scripts", f]))
      end

      git = fn args -> {_, 0} = System.cmd("git", ["-C", root | args], stderr_to_stdout: true) end
      git.(["init", "-q", "-b", "main"])
      git.(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"])
      git.(["branch", "work/feature"])
      git.(["remote", "add", "origin", Path.join(tmp, "no-such-origin")])
      on_exit(fn -> File.rm_rf!(tmp) end)
      %{tmp: tmp, root: root}
    end

    defp run_smoke(tmp, root, args) do
      env = [{"TMPDIR", tmp}, {"TLON_SMOKE_PORT", "4599"}, {"TLON_SMOKE_DATABASE", "tlon_smoke_fetch_test"}]
      System.cmd("bash", [Path.join([root, "scripts", "release-smoke.sh"]) | args], env: env, stderr_to_stdout: true)
    end

    test "a smoke of a local work/<slug> ref goes on past a failed fetch", %{tmp: tmp, root: root} do
      {out, _} = run_smoke(tmp, root, ["work/feature"])

      refute out =~ "smoke FAILED: can't fetch origin"
      assert out =~ ~r/smoke: [0-9a-f]{7} on :4599/
    end

    test "a smoke of origin/main still fails when origin can't be fetched", %{tmp: tmp, root: root} do
      assert {out, 1} = run_smoke(tmp, root, [])
      assert out =~ "smoke FAILED: can't fetch origin"
    end

    test "a second smoke of a commit already being smoked refuses, naming the run", %{tmp: tmp, root: root} do
      {sha, 0} = System.cmd("git", ["-C", root, "rev-parse", "work/feature"])
      lock = Path.join(tmp, "tlon-smoke-commit-#{String.trim(sha)}.lock")
      File.write!(lock, "pid 123 on http://127.0.0.1:4777\n")
      hold_lock(lock)

      assert {out, 1} = run_smoke(tmp, root, ["work/feature"])
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

    test "a holder that is gone (no such pid, nothing on its url, an old record) is reclaimed, not refused", %{
      tmp: tmp,
      root: root
    } do
      stale_lock(tmp, root, "pid 999999 on http://127.0.0.1:4777\n")

      {out, _} = run_smoke(tmp, root, ["work/feature"])

      refute out =~ "already being smoked"
      assert out =~ ~r/smoke: [0-9a-f]{7} on :4599/
    end

    test "an old record whose url still answers is a live holder: refused", %{tmp: tmp, root: root} do
      url = stub({200, "{}"})
      stale_lock(tmp, root, "pid 999999 on #{url}\n")

      assert {out, 1} = run_smoke(tmp, root, ["work/feature"])
      assert out =~ "is already being smoked (pid 999999 on #{url})"
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
  end

  describe "two smokes at once" do
    # the sweep a smoke ran before the build lock (c44fc5c), still in every checkout branched before
    # it: a build no process names in its command line or cwd goes, and on a host where another user's
    # /proc/<pid>/cwd can't be read the cwd test is always false (pipefail), so every build goes
    @old_sweep ~S"""
    set -uo pipefail
    root="$1"
    for stale in "${TMPDIR:-/tmp}"/tlon-smoke-*/; do
      stale="${stale%/}"; [ -d "$stale/server" ] || continue
      pgrep -f "$stale/" >/dev/null && continue
      find /proc/[0-9]*/cwd -maxdepth 0 -lname "$stale*" 2>/dev/null | grep -q . && continue
      git -C "$root" worktree remove --force "$stale" >/dev/null 2>&1; rm -rf "$stale"
    done
    """

    setup do
      tmp = Path.join(System.tmp_dir!(), "smoke-race-#{System.pid()}-#{System.unique_integer([:positive])}")
      root = Path.join(tmp, "repo")
      stubs = Path.join(tmp, "bin")
      signal = Path.join(tmp, "signal")

      Enum.each(
        [Path.join(root, "scripts"), Path.join(root, "server"), Path.join(root, "office"), stubs, signal],
        &File.mkdir_p!/1
      )

      for f <- ~w(release-smoke.sh git-fetch-origin.sh smoke-sweep.sh) do
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

    test "a smoke from a checkout older than the build lock leaves a running smoke's build alone", ctx do
      env = [
        {"TMPDIR", ctx.tmp},
        {"PATH", ctx.stubs <> ":" <> System.get_env("PATH")},
        {"SMOKE_SIGNAL", ctx.signal},
        {"TLON_SMOKE_PORT", "4598"},
        {"TLON_SMOKE_DATABASE", "tlon_smoke_race_test"}
      ]

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
      File.mkdir_p!(root)
      {_, 0} = System.cmd("git", ["-C", root, "init", "-q"])
      on_exit(fn -> File.rm_rf!(tmp) end)
      %{tmp: tmp, root: root}
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

    test "a build whose run holds its lock stays; one whose lock nobody holds goes", %{tmp: tmp, root: root} do
      live = build(tmp, "tlon-smoke/live")
      hold(live <> ".lock")
      dead = build(tmp, "tlon-smoke/dead")
      File.write!(dead <> ".lock", "")

      {_, 0} = System.cmd("bash", [@sweep, root], env: [{"TMPDIR", tmp}], stderr_to_stdout: true)

      assert File.dir?(live)
      refute File.exists?(dead)
      refute File.exists?(dead <> ".lock")
    end

    test "with no lock (a run from before it), only a build older than any build takes goes", %{tmp: tmp, root: root} do
      fresh = build(tmp, "tlon-smoke-fresh")
      old = build(tmp, "tlon-smoke-old")
      {_, 0} = System.cmd("touch", ["-d", "3 hours ago", old])
      unbuilt = Path.join(tmp, "tlon-smoke-checking-out")
      File.mkdir_p!(unbuilt)

      {_, 0} = System.cmd("bash", [@sweep, root], env: [{"TMPDIR", tmp}], stderr_to_stdout: true)

      assert File.dir?(fresh)
      refute File.exists?(old)
      assert File.dir?(unbuilt)
    end
  end
end
