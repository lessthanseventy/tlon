defmodule Server.WorklineBriefTest do
  # Worklines slice 2: the stage brief IS the wake — a funes-authored message posted on the
  # workline thread when a stage flips (or gates), riding the existing lead-wake path. The
  # brief text is pure (Server.Workline.Brief); the posting rides advance/approve.
  use ExUnit.Case, async: false

  alias Server.Message
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline
  alias Server.Workline.Brief

  defmodule AllPresent do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, _requirement), do: {:ok, "present"}
  end

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp thread(stage, extra \\ %{}) do
    struct!(Thread, Map.merge(%{id: 1, title: "fix the composer", slug: "composer-wrap", stage: stage}, extra))
  end

  test "a workspace's model_routing knob names the stage's model in the brief; no knob, no line" do
    {:ok, ws} =
      Server.Workspaces.register(%{
        name: "routed",
        type: "code",
        scope: "project",
        repos: [],
        roster: [],
        knobs: %{"model_routing" => %{"spec" => "claude/opus", "build" => "ollama/kimi-k2.7-code"}}
      })

    t = %Thread{slug: "r", stage: "spec", workspace_id: ws.id}
    assert Brief.stage_message(t) =~ "Model for this stage: claude/opus (workspace knob model_routing.spec)"
    refute Brief.stage_message(%{t | stage: "plan"}) =~ "Model for this stage"
    refute Brief.stage_message(%{t | workspace_id: nil}) =~ "Model for this stage"
  end

  test "every working stage's brief names its owed exit artifact and the advance verb" do
    owed = %{
      "spec" => "work/composer-wrap/spec.md",
      "plan" => "work/composer-wrap/plan.md",
      "build" => "work/composer-wrap",
      "review" => "work/composer-wrap/review.md"
    }

    for {stage, artifact} <- owed do
      brief = Brief.stage_message(thread(stage))
      assert brief =~ artifact, "#{stage} brief must name #{artifact}"
      assert brief =~ "advance_stage", "#{stage} brief must name the advance verb"
    end
  end

  test "briefs carry the per-stage read-list — a cold agent knows what to read" do
    assert Brief.stage_message(thread("spec")) =~ "intent.md"
    plan = Brief.stage_message(thread("plan"))
    assert plan =~ "intent.md" and plan =~ "spec.md"
    build = Brief.stage_message(thread("build"))
    assert build =~ "spec.md" and build =~ "plan.md"
  end

  test "the verify brief pins evidence to the workline's verify correlation" do
    assert Brief.stage_message(thread("verify")) =~ "workline:composer-wrap:verify"
  end

  test "the gate notice names the parked transition and the operator's approve verb" do
    notice = Brief.gate_message(thread("spec", %{id: 42, awaiting: "andrew"}))
    assert notice =~ "spec"
    assert notice =~ "approve 42"
  end

  test "a flip posts the next stage's brief as a funes message on the thread" do
    {:ok, thread} = Workline.open(%{title: "loud advance", slug: "brief-post"})
    {:ok, advanced} = Workline.advance(thread, artifacts: AllPresent)

    assert advanced.stage == "spec"
    bodies = Message |> Repo.all() |> Enum.filter(&(&1.thread_id == thread.id)) |> Enum.map(&{&1.author, &1.body})
    assert Enum.any?(bodies, fn {author, body} -> author == "tlon" and body =~ "SPEC" end)
  end

  test "a gate posts the parked notice; approval posts the next brief" do
    {:ok, thread} = Workline.open(%{title: "gated", slug: "gate-post"})
    {:ok, at_spec} = Workline.advance(thread, artifacts: AllPresent)
    {:awaiting, parked} = Workline.advance(at_spec, artifacts: AllPresent)

    bodies = fn -> Message |> Repo.all() |> Enum.filter(&(&1.thread_id == thread.id)) |> Enum.map(& &1.body) end
    assert Enum.any?(bodies.(), &(&1 =~ "approve #{thread.id}"))

    {:ok, at_plan} = Workline.approve(parked, artifacts: AllPresent)
    assert at_plan.stage == "plan"
    assert Enum.any?(bodies.(), &(&1 =~ "PLAN"))
  end

  test "reaching merged posts a completion note, not a brief" do
    note = Brief.stage_message(thread("merged"))
    assert note =~ "merged"
    refute note =~ "advance_stage"
  end
end
