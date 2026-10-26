defmodule Server.TrustTest do
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Repo
  alias Server.Thread
  alias Server.Trust

  setup do
    Server.TestDB.clean!()
    :ok
  end

  # a workline `name` led through build, finished as `stage`, sent back to build `bounces` times
  defp built(name, stage, bounces \\ 0) do
    {:ok, t} = Channel.open_thread(%{title: "work #{System.unique_integer([:positive])}"})
    {:ok, _} = Channel.post(%{thread_id: t.id, author: "tlon", body: Trust.leads_line(name, "build")})

    for _ <- 1..bounces//1 do
      {:ok, _} =
        Server.Dossier.record_event(%{
          thread_id: t.id,
          kind: "stage_advanced",
          correlation: "workline:x",
          detail: %{"from" => "review", "to" => "build"}
        })
    end

    {:ok, t} = t |> Thread.workline_stage_changeset(%{stage: stage}) |> Repo.update()
    t
  end

  test "a record counts finished builds, and as first time only a merge never sent back to build" do
    built("hronir", "landed")
    built("hronir", "landed", 1)
    built("hronir", "build")
    built("ashe", "landed")

    assert Trust.record("hronir") == %{led: 2, first_time: 1}
  end

  test "earned at eight finished builds and four in five first time; the step names who earned it, and stops at 4" do
    for _ <- 1..7, do: built("hronir", "landed")
    built("hronir", "landed", 2)
    t = built("hronir", "landed")
    built("ashe", "landed")
    lone = built("ashe", "landed")

    assert Trust.record("hronir") == %{led: 9, first_time: 8}
    assert Trust.builder(t) == "hronir"
    assert {3, %{name: "hronir", led: 9, first_time: 8}} = Trust.allowance(t, 2)
    assert {4, nil} = Trust.allowance(t, 4)
    assert {2, nil} = Trust.allowance(lone, 2)
  end
end
