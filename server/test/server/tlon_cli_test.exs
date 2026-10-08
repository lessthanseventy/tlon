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
end
