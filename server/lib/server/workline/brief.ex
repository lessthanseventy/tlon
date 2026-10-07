defmodule Server.Workline.Brief do
  @moduledoc """
  The stage brief — the message that IS the wake (worklines slice 2). When a workline flips,
  server posts the entered stage's brief on the thread; delivery rides the lead-wake path —
  live in the node that runs the switchboard, and via the switchboard DRAIN (undelivered
  rows, oldest first) when the flip happened in another node (a CLI advance into the
  service). Pure text here: playbook + read-list + owed exit artifact + the advance verb.
  Stage playbooks are the ADVISORY half of governance (skills, not hooks) — workspace knobs can
  override later.
  """

  alias Server.Thread

  @doc "The brief for the stage the workline just ENTERED (merged → a completion note)."
  def stage_message(%Thread{stage: "merged"} = t) do
    "✅ workline #{t.slug} is merged — the chain is complete. History: work/#{t.slug}/ + this thread."
  end

  def stage_message(%Thread{} = t) do
    String.trim("""
    ▶ #{String.upcase(t.stage)} — workline #{t.slug}
    Read: #{read_list(t)}#{skipped_note(t)}
    #{playbook(t)}#{routing_note(t)}
    #{exit_line(t)}#{gate_note(t.stage)}
    """)
  end

  @doc """
  The parked-gate notice — what's waiting and the operator's completion verb, then the
  workline's proof (`Server.Workline.proof/2`) when one is given.
  """
  def gate_message(%Thread{} = t, proof \\ nil) do
    "⏸ workline #{t.slug} is parked at #{t.stage} — this transition is the operator's. " <>
      "Approve with: mise run server:cli -- approve #{t.id} (tlon-cli approve #{t.id})." <> proof_lines(proof)
  end

  defp proof_lines(nil), do: ""

  defp proof_lines(%{artifacts: artifacts, checks: checks, diff: diff}) do
    lines =
      Enum.map(artifacts, fn {stage, {status, why}} -> "#{mark(status == :ok)} #{stage}: #{why}" end) ++
        check_lines(checks) ++ ["diff: #{elem(diff, 1)}"]

    "\nProof:\n" <> Enum.map_join(lines, "\n", &("  " <> &1))
  end

  defp check_lines([]), do: ["✗ no verify checks recorded"]
  defp check_lines(checks), do: Enum.map(checks, &"#{mark(&1.exit == 0)} #{&1.cmd} (exit #{&1.exit})")

  defp mark(true), do: "✓"
  defp mark(false), do: "✗"

  # Capability-fit routing (Aider's architect/editor split, survey §4 adopt #7): the workspace's
  # `knobs["model_routing"]` names a model per stage — reasoning for spec/review, a precise cheap
  # one for plan expansion and diffs — and the brief says which, so the knob is the routing axis
  # the coworker actually sees. Absent knob, no line: the bucket axis (tasks/pi.toml) stands alone.
  defp routing_note(%Thread{workspace_id: nil}), do: ""

  defp routing_note(%Thread{workspace_id: wid, stage: stage}) do
    case Server.Workspaces.get(wid) do
      %{knobs: %{"model_routing" => %{} = routing}} ->
        case Map.get(routing, stage) do
          nil -> ""
          model -> "\nModel for this stage: #{model} (workspace knob model_routing.#{stage})."
        end

      _ ->
        ""
    end
  end

  defp playbook(%{stage: "spec"}),
    do:
      "Interview the operator IN THIS THREAD until requirements and design fit one document; draft it — do not re-ask what the workspace's knobs and floor constraints already state."

  defp playbook(%{stage: "plan"}),
    do:
      "Break the spec into bite-sized, verifiable tasks with exact files — an engineer with zero context could execute them."

  defp playbook(%{stage: "build"} = t),
    do:
      "Implement on branch work/#{t.slug}, test-first; every commit stays green. The failing tests are read-only to you."

  defp playbook(%{stage: "verify"}),
    do:
      "The server verifies, not you: it runs the full check on the branch in its own checkout and records the evidence " <>
        "itself. Nothing to run or record here — on a failure it posts what broke, and the fix goes on the branch."

  defp playbook(%{stage: "review"}),
    do:
      "You are the reviewer, not the builder: findings against spec compliance, bugs, security — verdict at the top. " <>
        "Land it with submit_review — verdict approve or request_changes, and the whole review.md, verdict " <>
        "first: the server commits it for you, since you never write files. request_changes sends it back to " <>
        "the builder; after approve, call advance_stage to hand it to the merge gate."

  defp playbook(%{stage: "intent"}), do: "Capture the originator's words near-verbatim plus a one-line restatement."

  # What to read on entry — artifacts first (git is the record), the brief for live state.
  defp read_list(%{stage: "intent"} = t), do: "the operator's opening message on this thread#{brief_tail(t)}"
  defp read_list(%{stage: "spec"} = t), do: "#{dir(t)}/intent.md#{brief_tail(t)}"
  defp read_list(%{stage: "plan"} = t), do: "#{dir(t)}/intent.md · #{dir(t)}/spec.md#{brief_tail(t)}"
  defp read_list(%{stage: "build"} = t), do: "#{dir(t)}/spec.md · #{dir(t)}/plan.md#{brief_tail(t)}"
  defp read_list(%{stage: "verify"} = t), do: "#{dir(t)}/plan.md · the branch work/#{t.slug}#{brief_tail(t)}"

  defp read_list(%{stage: "review"} = t),
    do: "#{dir(t)}/spec.md · #{dir(t)}/plan.md · the diff on branch work/#{t.slug}#{brief_tail(t)}"

  defp brief_tail(_t), do: " · get_brief for live state"

  defp owed(%{stage: "intent"} = t), do: "#{dir(t)}/intent.md"
  defp owed(%{stage: "spec"} = t), do: "#{dir(t)}/spec.md"
  defp owed(%{stage: "plan"} = t), do: "#{dir(t)}/plan.md"
  defp owed(%{stage: "build"} = t), do: "commits on branch work/#{t.slug}"
  defp owed(%{stage: "verify"} = t), do: "passing CHECKS (workline:#{t.slug}:verify)"
  defp owed(%{stage: "review"} = t), do: "#{dir(t)}/review.md"

  defp gate_note(stage) when stage in ["spec", "review"], do: " This stage's exit gates on the operator."
  defp gate_note(_stage), do: ""

  defp dir(t), do: "work/#{t.slug}"

  # how a stage is left: verify by the server alone; review through the reviewer's own door
  defp exit_line(%{stage: "verify"} = t),
    do: "Exit: none of yours — the server advances it when its check passes on branch work/#{t.slug}."

  defp exit_line(%{stage: "review"} = t),
    do: "Exit: submit_review with a verdict (the server commits #{owed(t)}); after approve, call advance_stage."

  defp exit_line(%{stage: "build"} = t), do: "Exit: commit #{owed(t)}, then call advance_stage."

  defp exit_line(t), do: "Exit: commit #{owed(t)} on your branch work/#{t.slug}, then call advance_stage."

  # a workline may open at any stage: the docs of the stages it skipped were never written
  defp skipped_note(%{stage: stage}) when stage in ["plan", "build", "verify", "review"],
    do: " (a doc from a stage this workline started after won't exist — that's expected, not owed)"

  defp skipped_note(_t), do: ""
end
