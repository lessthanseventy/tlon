defmodule Server.SheriffTest do
  # The coworker who owns red: every red signal lands on the sheriff's beat (one standing thread per
  # workspace, the sheriff its lead), and a red verify leaves the operator's list for it.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Message
  alias Server.Repo
  alias Server.Sheriff
  alias Server.Workspaces

  defmodule Conflicts do
    @moduledoc false
    def merge(_repo, _slug, _opts), do: {:error, "a conflict in wide.ts"}
  end

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Watched"})
    %{ws: ws}
  end

  defp beats(ws), do: Repo.all(from t in Server.Thread, where: t.workspace_id == ^ws.id and t.title == "sheriff's beat")

  defp reports(beat),
    do: Repo.all(from m in Message, where: m.thread_id == ^beat.id and like(m.body, "🚨%"), order_by: m.id)

  test "no sheriff on the bench: nothing is opened, the report says so", %{ws: ws} do
    {:ok, t} = Channel.open_thread(%{title: "red thing", workspace_id: ws.id})
    assert :no_sheriff = Sheriff.report(t, "verify is red")
    assert beats(ws) == []
  end

  test "a sheriff's reports land on one beat it leads, each naming the thread and what broke", %{ws: ws} do
    {:ok, _} = Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
    {:ok, a} = Channel.open_thread(%{title: "argos", workspace_id: ws.id})
    {:ok, b} = Channel.open_thread(%{title: "stereo", workspace_id: ws.id})

    :ok = Sheriff.report(a, "verify is red: mise run check (exit 1)")
    :ok = Sheriff.report(b, "the merge queue bounced it back to build: a conflict")

    assert [beat] = beats(ws)
    assert Channel.thread_lead(beat.id) == "scharlach"
    assert [one, two] = reports(beat)
    assert one.body =~ "##{a.id} argos" and one.body =~ "verify is red"
    assert two.body =~ "##{b.id} stereo" and two.body =~ "bounced"
  end

  test "where a sheriff owns red, a red verify is not on the operator's list", %{ws: ws} do
    {:ok, red} =
      Server.Workline.open(%{
        title: "r",
        slug: "red-#{System.unique_integer([:positive])}",
        stage: "verify",
        workspace_id: ws.id
      })

    {:ok, _} =
      Server.Dossier.record_check(%{
        thread_id: red.id,
        cmd: "mise run check",
        exit: 1,
        tail: "boom",
        correlation: "workline:#{red.slug}:verify"
      })

    kinds = fn -> Server.Office.Needs.list() |> Enum.filter(&(&1.workspace_id == ws.id)) |> Enum.map(& &1.kind) end
    assert "verify_failed" in kinds.()

    {:ok, _} = Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
    refute "verify_failed" in kinds.()
  end

  test "a landing the merge queue bounces is reported to the sheriff", %{ws: ws} do
    {:ok, _} = Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
    {:ok, t} = Server.Workline.open(%{title: "w", slug: "conflicted", stage: "review", workspace_id: ws.id})
    {:ok, queued} = t |> Server.Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()

    assert {:error, {:bounced, _}} =
             Server.Workline.land_queued(queued, merge: Conflicts, gate: fn _, _ -> {:ok, :green} end)

    assert [beat] = beats(ws)
    assert [r] = reports(beat)
    assert r.body =~ "##{t.id}" and r.body =~ "a conflict in wide.ts"
  end
end
