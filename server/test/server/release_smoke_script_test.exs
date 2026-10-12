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

  describe "smoke-sweep.sh: what a SIGKILLed smoke left behind" do
    @sweep Path.expand("../../../scripts/smoke-sweep.sh", __DIR__)

    setup do
      tmp = Path.join(System.tmp_dir!(), "smoke-sweep-#{System.unique_integer([:positive])}")
      root = Path.join(tmp, "repo")
      File.mkdir_p!(root)
      {_, 0} = System.cmd("git", ["-C", root, "init", "-q"])
      on_exit(fn -> File.rm_rf!(tmp) end)
      %{tmp: tmp, root: root}
    end

    defp build(tmp, name) do
      dir = Path.join(tmp, "tlon-smoke-#{name}")
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
      live = build(tmp, "live")
      hold(live <> ".lock")
      dead = build(tmp, "dead")
      File.write!(dead <> ".lock", "")

      {_, 0} = System.cmd("bash", [@sweep, root], env: [{"TMPDIR", tmp}], stderr_to_stdout: true)

      assert File.dir?(live)
      refute File.exists?(dead)
      refute File.exists?(dead <> ".lock")
    end

    test "with no lock (a run from before it), only a build older than any build takes goes", %{tmp: tmp, root: root} do
      fresh = build(tmp, "fresh")
      old = build(tmp, "old")
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
