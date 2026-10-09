defmodule Server.GradeTest do
  # A seat's grade is a capability requirement; the operator's config maps it to a model. Precedence:
  # the seat's own override (its policy, then config `coworkers.<name>`), then the config's grade,
  # then the compiled grade default; a seat with no grade keeps its archetype's default.
  use ExUnit.Case, async: false

  alias Server.OperatorConfig
  alias Server.Profiles
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    path = Path.join(System.tmp_dir!(), "tlon-grade-#{System.unique_integer([:positive])}.json")
    previous = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      Application.put_env(:server, :operator_config_path, previous)
      File.rm(path)
    end)

    {:ok, ws} = Workspaces.register(%{name: "graded"})

    {:ok, junior} =
      Workspaces.seat(ws.id, %{name: "daneri", archetype: "builder", grade: "junior", specialty: "office"})

    {:ok, _} = Workspaces.seat(ws.id, %{name: "emma", archetype: "builder"})
    %{ws: ws, junior: junior, path: path}
  end

  defp model(ws, name), do: Profiles.instantiate(%{archetype: :builder, name: name}, ws.id).model.model

  test "the seat carries its grade and specialty", %{ws: ws} do
    assert %{grade: "junior", specialty: "office"} = Enum.find(Workspaces.bench(ws.id), &(&1.name == "daneri"))
  end

  test "a junior seat resolves to the junior model; an ungraded one keeps the archetype's", %{ws: ws} do
    assert model(ws, "daneri") == OperatorConfig.grade_model("junior").model
    assert model(ws, "emma") == Profiles.archetype(:builder).model.model
  end

  test "the config's grade overrides the compiled default", %{ws: ws, path: path} do
    File.write!(path, ~s({"grades": {"junior": {"provider": "ollama-cloud", "model": "glm-5.2"}}}))
    assert model(ws, "daneri") == "glm-5.2"
  end

  test "a seat override still wins: the config's coworker entry, and above it the seat's policy",
       %{ws: ws, junior: junior, path: path} do
    File.write!(path, ~s({"coworkers": {"daneri": {"provider": "anthropic", "model": "claude-opus-5-5"}}}))
    assert model(ws, "daneri") == "claude-opus-5-5"

    {:ok, _} =
      Workspaces.set_policy(ws.id, junior.agent_id, %{
        model: %{"provider" => "anthropic", "model" => "claude-fable-5-1"}
      })

    assert model(ws, "daneri") == "claude-fable-5-1"
  end

  test "a grade outside the three is refused", %{ws: ws} do
    assert {:error, _} = Workspaces.seat(ws.id, %{name: "nobody", archetype: "builder", grade: "intern"})
  end

  test "the bench's lead is its tech lead: his brief carries the duties, another builder's doesn't", %{ws: ws} do
    lead = Workspaces.lead(ws.id)
    other = ws.id |> Workspaces.bench() |> Enum.find(&(&1.archetype == "builder" and &1.name != lead.name))
    brief = fn c -> (c |> Profiles.roster_entry() |> Profiles.instantiate(ws.id)).system_prompt end

    assert brief.(lead) =~ "TECH LEAD"
    refute brief.(other) =~ "TECH LEAD"
  end
end
