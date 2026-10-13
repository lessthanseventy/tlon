defmodule Server.Office.WriterTest do
  # The office's flavour text drains the bucket the crew on is draining: Claude's while a Claude
  # coworker is on, ollama's otherwise — whatever the crews are called.
  use ExUnit.Case, async: false

  alias Server.Office.Writer

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Shifty"})
    %{ws: ws}
  end

  test "with a Claude coworker on it is mostly Haiku with some deepseek; with none, only the ollama models",
       %{ws: ws} do
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder", crew: "claude"})
    {:ok, pi} = Server.Workspaces.seat(ws.id, %{name: "dahlmann", archetype: "builder", crew: "pi"})
    {:ok, _} = Server.Workspaces.retarget(ws.id, pi.agent_id, %{model: "ollama-cloud/glm-5.2"})
    {:ok, _} = Server.Shifts.switch(ws.id, "claude")

    claude = Writer.pool(ws.id)
    assert {"claude", "haiku"} in claude and Enum.count(claude, &(&1 == {"claude", "haiku"})) > 1
    assert Enum.any?(claude, &match?({"claude", "ollama-cloud/" <> _}, &1))

    {:ok, _} = Server.Shifts.switch(ws.id, "pi")
    assert Enum.all?(Writer.pool(ws.id), &match?({"claude", "ollama-cloud/" <> _}, &1))
  end

  test "the wackiness dial's tone: business writes nothing, each level up is wilder" do
    path = Path.join(System.tmp_dir!(), "wack-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    prior = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      if prior,
        do: Application.put_env(:server, :operator_config_path, prior),
        else: Application.delete_env(:server, :operator_config_path)

      File.rm(path)
    end)

    File.write!(path, ~s({"wackiness": 0}))
    assert Writer.tone() == nil
    assert {:error, :business} = Writer.write("hi", 1)

    File.write!(path, ~s({"wackiness": 3}))
    assert Writer.tone() =~ "FERAL"
  end

  test "the wilder the office, the more often it talks" do
    assert Enum.map(0..3, &Writer.every(120, &1)) == [120, 120, 60, 30]
  end

  test "a stand-in CLI pins every call to it" do
    dir = Path.join(System.tmp_dir!(), "writer-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    cli = Path.join(dir, "model")
    File.write!(cli, "#!/bin/sh\necho stand-in\n")
    File.chmod!(cli, 0o755)
    Application.put_env(:server, :banter_cmd, cli)

    on_exit(fn ->
      Application.delete_env(:server, :banter_cmd)
      File.rm_rf!(dir)
    end)

    assert {:ok, "stand-in\n"} = Writer.write("hello", 1)
  end
end
