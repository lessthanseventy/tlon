defmodule Server.TlonCliTest do
  # tlon-cli runs its Elixir inside the LIVE service (`bin/server rpc`): `System.halt/1` there halts
  # the service itself, so a refused command (no such thread, a bad ticket) took the server down.
  # A refusal raises instead: rpc prints it and exits non-zero, and the node lives.
  use ExUnit.Case, async: true

  @cli Path.expand("../../../scripts/tlon-cli.sh", __DIR__)

  test "no tlon-cli command halts the node it runs in" do
    halts =
      for {line, n} <- @cli |> File.read!() |> String.split("\n") |> Enum.with_index(1), line =~ "System.halt", do: n

    assert halts == [], "System.halt in scripts/tlon-cli.sh at lines #{inspect(halts)}"
  end

  test "TLON_CLI_SERVER runs the rpc through that release, not the checkout's .release" do
    dir = Path.join(System.tmp_dir!(), "tlon-cli-server-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    server = Path.join(dir, "server")
    File.write!(server, "#!/bin/sh\necho \"scratch server: $1\"\n")
    File.chmod!(server, 0o755)

    assert {out, 0} = System.cmd("bash", [@cli, "quiet"], env: [{"TLON_CLI_SERVER", server}], stderr_to_stdout: true)
    assert out == "scratch server: rpc\n"
  end
end
