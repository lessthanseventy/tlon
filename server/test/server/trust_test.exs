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
  defp built(name, stage, bounces \\ 0, model \\ nil) do
    {:ok, t} = Channel.open_thread(%{title: "work #{System.unique_integer([:positive])}"})
    {:ok, _} = Channel.post(%{thread_id: t.id, author: "tlon", body: Trust.leads_line(name, "build", model)})

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

  test "a leads line carries the model it was taken on, and reads it back" do
    assert Trust.leads_line("ashe", "build") == "→ ashe leads (build stage)"
    line = Trust.leads_line("ashe", "build", "m1 (claude_code)")
    assert line == "→ ashe leads (build stage) [model: m1 (claude_code)]"
    assert Trust.model_of(line <> " — note") == "m1 (claude_code)"
    assert Trust.model_of("→ ashe leads (build stage)") == nil
  end

  test "a record counts finished builds, and as first time only a merge never sent back to build" do
    built("hronir", "landed")
    built("hronir", "landed", 1)
    built("hronir", "build")
    built("ashe", "landed")

    assert Trust.record("hronir") == %{led: 2, first_time: 1}
  end

  test "record/2 counts only builds taken on that model; unknown-model builds count in record/1 alone" do
    built("hronir", "landed", 0, "m1")
    built("hronir", "landed", 1, "m1")
    built("hronir", "landed", 0, "m2")
    built("hronir", "landed")
    assert Trust.record("hronir") == %{led: 4, first_time: 3}
    assert Trust.record("hronir", "m1") == %{led: 2, first_time: 1}
    assert Trust.record("hronir", "m2") == %{led: 1, first_time: 1}
    assert Trust.record("hronir", "nope") == %{led: 0, first_time: 0}
  end

  test "earned at eight finished builds and four in five first time; the step names who earned it, and stops at 4" do
    for _ <- 1..7, do: built("hronir", "landed")
    built("hronir", "landed", 2)
    t = built("hronir", "landed", 0, "m1")
    unknown = built("hronir", "landed")
    built("ashe", "landed")
    lone = built("ashe", "landed")

    assert Trust.record("hronir") == %{led: 10, first_time: 9}
    assert Trust.builder(t) == {"hronir", "m1"}
    assert Trust.builder(unknown) == {"hronir", nil}
    assert {3, %{name: "hronir", model: "m1", led: 10, first_time: 9}} = Trust.allowance(t, 2)
    assert {3, %{name: "hronir", model: nil}} = Trust.allowance(unknown, 2)
    assert {4, nil} = Trust.allowance(t, 4)
    assert {2, nil} = Trust.allowance(lone, 2)
  end
end
