defmodule Console.PolicyImportTest do
  @moduledoc """
  The one-shot that moves `config.json`'s coworker knobs into `workspace_policy` rows. The file was
  keyed by profile NAME machine-wide; a policy is keyed workspace × agent, so one override lands on
  every workspace that seats that coworker.
  """
  use ExUnit.Case, async: false

  alias Console.PolicyImport
  alias Server.Repo
  alias Server.Workspace
  alias Server.Workspaces

  setup_all do
    Console.TestRepo.boot!("policy-import")
    :ok
  end

  setup do
    Repo.delete_all(Server.ChannelRow)
    Repo.delete_all(Workspace)

    path = Path.join(System.tmp_dir!(), "policy_import_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm_rf!(path) end)

    %{path: path}
  end

  defp write_config!(path, map), do: File.write!(path, Jason.encode!(map))

  test "an override lands on every workspace that seats the coworker", %{path: path} do
    {:ok, a} = Workspaces.register(%{name: "A", roster: [%{"archetype" => "surveyor", "name" => "tertius"}]})
    {:ok, b} = Workspaces.register(%{name: "B", roster: [%{"archetype" => "surveyor", "name" => "tertius"}]})
    {:ok, c} = Workspaces.register(%{name: "C"})

    write_config!(path, %{
      "coworkers" => %{"tertius" => %{"provider" => "ollama-cloud", "model" => "glm-5.2", "thinking" => "medium"}}
    })

    assert {:ok, 2} = PolicyImport.run(path)

    [seat_a] = Workspaces.bench(a.id)
    assert Workspaces.policy(a.id, seat_a.agent_id).model["model"] == "glm-5.2"
    [seat_b] = Workspaces.bench(b.id)
    assert Workspaces.policy(b.id, seat_b.agent_id).model["model"] == "glm-5.2"
    assert Workspaces.policies(c.id) == %{}
  end

  test "yolo becomes the ask-vs-allow default, both ways", %{path: path} do
    {:ok, ws} = Workspaces.register(%{name: "A", roster: [%{"name" => "amy"}, %{"name" => "bob"}]})
    write_config!(path, %{"coworkers" => %{"amy" => %{"yolo" => true}, "bob" => %{"yolo" => false}}})

    assert {:ok, 2} = PolicyImport.run(path)

    [amy, bob] = Workspaces.bench(ws.id)
    assert Workspaces.policy(ws.id, amy.agent_id).ask_default == "allow"
    assert Workspaces.policy(ws.id, bob.agent_id).ask_default == "ask"
  end

  test "it runs ONCE — the section is retired, not deleted, and a second run is a no-op", %{path: path} do
    {:ok, _} = Workspaces.register(%{name: "A", roster: [%{"name" => "amy"}]})
    write_config!(path, %{"coworkers" => %{"amy" => %{"yolo" => true}}})

    assert {:ok, 1} = PolicyImport.run(path)
    assert :noop = PolicyImport.run(path)

    kept = path |> File.read!() |> Jason.decode!()
    refute Map.has_key?(kept, "coworkers")
    assert kept["coworkers_imported"] == %{"amy" => %{"yolo" => true}}
  end

  test "a seat that already has a policy is left alone — the import never overwrites", %{path: path} do
    {:ok, ws} = Workspaces.register(%{name: "A", roster: [%{"name" => "amy"}]})
    [seat] = Workspaces.bench(ws.id)
    {:ok, _} = Workspaces.set_policy(ws.id, seat.agent_id, %{ask_default: "ask"})

    write_config!(path, %{"coworkers" => %{"amy" => %{"yolo" => true}}})

    assert {:ok, 0} = PolicyImport.run(path)
    assert Workspaces.policy(ws.id, seat.agent_id).ask_default == "ask"
  end

  test "a coworker nobody seats imports nothing, and the file is left for the operator", %{path: path} do
    {:ok, _} = Workspaces.register(%{name: "A"})
    write_config!(path, %{"coworkers" => %{"ghost" => %{"yolo" => true}}})

    assert {:ok, 0} = PolicyImport.run(path)
    assert path |> File.read!() |> Jason.decode!() |> Map.has_key?("coworkers")
  end

  test "no file, or no coworkers section, is a no-op", %{path: path} do
    assert :noop = PolicyImport.run(path)

    write_config!(path, %{"environment" => "home"})
    assert :noop = PolicyImport.run(path)
  end
end
