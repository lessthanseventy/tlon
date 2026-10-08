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
end
