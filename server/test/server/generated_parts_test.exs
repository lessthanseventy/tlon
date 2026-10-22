defmodule Server.GeneratedPartsTest do
  # One invented accessory a day, drawn by a stand-in model CLI, checked, kept, and read back without a call.
  use ExUnit.Case, async: false

  alias Server.GeneratedParts

  @good ~s({"part": {"slot": "hand", "front": {"11": "..........yy"}, "side": {"11": ".yy........."}, "back": {"11": "..........yy"}}})
  @day ~D[2026-10-22]

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})

    dir = Path.join(System.tmp_dir!(), "parts-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    cli = Path.join(dir, "model")
    calls = Path.join(dir, "calls")
    reply!(cli, calls, @good)
    Application.put_env(:server, :generator_cmd, cli)

    on_exit(fn ->
      Application.put_env(:server, :generator_cmd, "/nonexistent/tlon-test-generator")
      Application.delete_env(:server, :generator_daily_cap)
      Application.put_env(:server, :operator_config_path, "/nonexistent/tlon-test-config.json")
      File.rm_rf!(dir)
    end)

    %{ws: ws, calls: calls, cli: cli}
  end

  defp reply!(cli, calls, text) do
    File.write!(cli, "#!/bin/sh\necho x >> #{calls}\ncat <<'END'\n#{text}\nEND\n")
    File.chmod!(cli, 0o755)
  end

  defp count(calls),
    do: if(File.exists?(calls), do: calls |> File.read!() |> String.split("\n", trim: true) |> length(), else: 0)

  test "a day with no part invents one, validates it and keeps it", %{ws: ws, calls: calls} do
    assert {:ok, %{id: "gen:2026-10-22", slot: "hand"}} = GeneratedParts.refresh_due(ws.id, @day)

    assert [%{id: "gen:2026-10-22", day: "2026-10-22", slot: "hand", front: %{"11" => "..........yy"}}] =
             GeneratedParts.library(ws.id)

    assert count(calls) == 1
  end

  test "a second run the same day makes no call", %{ws: ws, calls: calls} do
    GeneratedParts.refresh_due(ws.id, @day)
    assert {:ok, :fresh} = GeneratedParts.refresh_due(ws.id, @day)
    assert count(calls) == 1
  end

  test "a part the validator rejects is not kept, the call still counts, and there is no retry", ctx do
    reply!(ctx.cli, ctx.calls, String.replace(@good, "..........yy", "..kk........"))
    assert {:error, {:rejected, {:front, {:row, "11"}}}} = GeneratedParts.refresh_due(ctx.ws.id, @day)
    assert GeneratedParts.library(ctx.ws.id) == []
    assert count(ctx.calls) == 1
  end

  test "unparseable output is {:error, :unparsed} and keeps no row", ctx do
    reply!(ctx.cli, ctx.calls, "I could not think of one today.")
    assert {:error, :unparsed} = GeneratedParts.refresh_due(ctx.ws.id, @day)
    assert GeneratedParts.library(ctx.ws.id) == []
  end

  test "banter off is {:error, :off}, with no call and no row", ctx do
    path = Path.join(System.tmp_dir!(), "tlon-config-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    File.write!(path, ~s({"banter": false}))
    Application.put_env(:server, :operator_config_path, path)
    on_exit(fn -> File.rm(path) end)

    assert {:error, :off} = GeneratedParts.refresh_due(ctx.ws.id, @day)
    assert GeneratedParts.library(ctx.ws.id) == []
    assert count(ctx.calls) == 0
  end

  test "a spent cap is {:error, :capped}, with no call and no row", ctx do
    Application.put_env(:server, :generator_daily_cap, 0)
    assert {:error, :capped} = GeneratedParts.refresh_due(ctx.ws.id, @day)
    assert GeneratedParts.library(ctx.ws.id) == []
    assert count(ctx.calls) == 0
  end

  test "library is oldest first and per workspace", %{ws: ws} do
    {:ok, other} = Server.Workspaces.register(%{name: "Other"})
    GeneratedParts.refresh_due(ws.id, ~D[2026-10-23])
    GeneratedParts.refresh_due(ws.id, @day)

    assert Enum.map(GeneratedParts.library(ws.id), & &1.id) == ["gen:2026-10-22", "gen:2026-10-23"]
    assert GeneratedParts.library(other.id) == []
  end
end
