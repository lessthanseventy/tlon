defmodule Server.WorkspacesRetargetTest do
  # `Server.Workspaces.retarget/3` — a coworker's knobs (model, effort, ask) from the operator's
  # door: a value sets it, :inherit puts it back to the archetype's, nil leaves it.
  use ExUnit.Case, async: false

  alias Server.Profiles
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Machine"})
    {:ok, c} = Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})
    {:ok, ws: ws, agent: c.agent_id}
  end

  test "a model by its key sets the model, the choice's own effort with it", %{ws: ws, agent: a} do
    m = hd(Profiles.model_choices())
    assert {:ok, p} = Workspaces.retarget(ws.id, a, %{model: "#{m.provider}/#{m.model}"})
    assert p.model["provider"] == m.provider and p.model["model"] == m.model
  end

  test "effort alone keeps the archetype's model at that effort", %{ws: ws, agent: a} do
    assert {:ok, p} = Workspaces.retarget(ws.id, a, %{effort: "high"})
    assert p.model["thinking"] == "high"
    assert is_binary(p.model["model"])
  end

  test "ask sets the default; :inherit takes every knob back, and the empty policy goes", %{ws: ws, agent: a} do
    assert {:ok, %{ask_default: "allow"}} = Workspaces.retarget(ws.id, a, %{ask: "allow"})
    assert {:ok, nil} = Workspaces.retarget(ws.id, a, %{ask: :inherit, model: :inherit})
    assert Workspaces.policy(ws.id, a) == nil
  end

  test "an unknown model is refused; nothing asked changes nothing", %{ws: ws, agent: a} do
    assert {:error, :unknown_model} = Workspaces.retarget(ws.id, a, %{model: "nope/nada"})
    assert {:ok, nil} = Workspaces.retarget(ws.id, a, %{})
  end
end
