defmodule Server.PresenceTest do
  # Warmth per provider: a coworker on a provider whose prompt cache is short goes cold sooner, by
  # the operator's "warmth_seconds" — and with none configured, every coworker has the one window.
  use ExUnit.Case, async: false

  alias Server.Presence
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Machine"})
    {:ok, pip} = Workspaces.seat(ws.id, %{name: "pip", archetype: "builder"})
    {:ok, _} = Workspaces.retarget(ws.id, pip.agent_id, %{model: "ollama-cloud/glm-5.2"})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})

    path = Path.join(System.tmp_dir!(), "tlon_presence_#{System.pid()}_#{System.unique_integer([:positive])}.json")
    prior = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      Application.put_env(:server, :operator_config_path, prior)
      File.rm(path)
    end)

    %{ws: ws, path: path}
  end

  test "a provider with a shorter window goes cold sooner; the rest keep the default", %{ws: ws, path: path} do
    twenty_ago = DateTime.add(DateTime.utc_now(), -20 * 60)
    assert Presence.warm_for?(twenty_ago, "pip", ws.id) and Presence.warm_for?(twenty_ago, "hronir", ws.id)

    File.write!(path, ~s({"warmth_seconds": {"ollama-cloud": 600}}))
    refute Presence.warm_for?(twenty_ago, "pip", ws.id)
    assert Presence.warm_for?(twenty_ago, "hronir", ws.id)
    assert DateTime.compare(Presence.loosest_cutoff(), DateTime.add(DateTime.utc_now(), -3_500)) == :lt
  end
end
