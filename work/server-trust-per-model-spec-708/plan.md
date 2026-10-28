# Plan — Server.Trust per model (#708)

Spec: `spec.md`. All paths are repo-relative. Run tests with
`~/projects/menard/bin/menard run test --in server server/test/server/trust_test.exs` (never raw mix).
Each task is one commit (trailer `Co-Authored-By: <your model> <noreply@anthropic.com>`).

Format decided: `→ ireneo leads (build stage) [model: anthropic/claude-sonnet-5-5 (claude_code)]` + any note.
Brackets, not "·": a model label has parentheses and underscores but never `]`.

## Task 1 — the line carries a model; Trust can read it back
Files: `server/lib/server/trust.ex`, `server/test/server/trust_test.exs`.

Test first (append to `trust_test.exs`):
```elixir
test "a leads line carries the model it was taken on, and reads it back" do
  assert Trust.leads_line("ashe", "build") == "→ ashe leads (build stage)"
  line = Trust.leads_line("ashe", "build", "m1 (claude_code)")
  assert line == "→ ashe leads (build stage) [model: m1 (claude_code)]"
  assert Trust.model_of(line <> " — note") == "m1 (claude_code)"
  assert Trust.model_of("→ ashe leads (build stage)") == nil
end
```
Code (`trust.ex`): replace `leads_line/2` with
```elixir
def leads_line(name, stage, model \\ nil)
def leads_line(name, stage, nil), do: "→ #{name} leads (#{stage} stage)"
def leads_line(name, stage, model), do: "→ #{name} leads (#{stage} stage) [model: #{model}]"

@doc "The model a leads line was taken on, or nil (a line from before the model was recorded)."
def model_of(body) do
  case Regex.run(~r/^→ \S+ leads \([a-z]+ stage\) \[model: ([^\]]+)\]/u, body) do
    [_, model] -> model
    _ -> nil
  end
end
```
Done: new test and the two existing ones green. Commit: "trust: a leads line can carry its model (#708)".

## Task 2 — `record/2`, the per-model read
Files: same two.

Test first (extend the `built` helper to `built(name, stage, bounces \\ 0, model \\ nil)` and post
`Trust.leads_line(name, "build", model)`):
```elixir
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
```
Code: make `record/1` call `record(name, :any)`; `record(name, model)` is today's body with the `where`
extended. Match on the line prefix as now; for a model add the SQL
`fragment("strpos(?, ?) > 0", m.body, ^"[model: #{model}]")` (not LIKE: `_` in labels is a wildcard).
Build the query with a `dynamic`/`if` so `:any` adds nothing.
Done: green. Commit: "trust: record/2 per model (#708)".

## Task 3 — builder's model on the approval card
Files: `server/lib/server/trust.ex`, `server/lib/server/workline.ex` (`auto_land_note/2`, ~line 936),
`server/test/server/trust_test.exs`.

Test first: update the existing allowance test: `built("hronir", "landed", 0, "m1")` for `t`, then
assert `Trust.builder(t) == {"hronir", "m1"}` and the evidence map includes `model: "m1"`:
`{3, %{name: "hronir", model: "m1", led: 9, first_time: 8}}`. Unknown-model builder → `model: nil`.

Code: `builder/1` selects the body of the last build line and returns `{name, model_of(body)}` (nil if no
line); `allowance/2` pattern-matches `{name, model}`, still uses `record(name)` (per coworker — the
operator's call, #16512) and puts `:model` in the evidence. In `auto_land_note/2` append
`" on #{earned.model}"` after `earned.name` when `earned.model` is set.
Grep callers first: `rg "Trust.builder" server/` — only `allowance/2` should call it; fix any other.
Done: trust tests green; `rg "Trust.builder"` clean. Commit: "trust: the builder's model rides on the earned-step evidence (#708)".

## Task 4 — staffing records the model
Files: `server/lib/server/workline.ex` (`hand_to/4`, ~line 1515), a test in the workline restaff tests
(find with `rg "hand_to|restaff" server/test`).

Test first: staff a thread so the lead changes, with the seat's workspace policy model set
(`Server.Workspaces.set_policy/3`, as `hire_for/3` does) and assert the posted `→ … leads` message ends in
`[model: <Server.Profiles.model_label(ws, name)>]`; a seat with no label (nil) posts the bare line.

Code: `Server.Trust.leads_line(name, thread.stage, Server.Profiles.model_label(thread.workspace_id, name))`.
Same-lead short-circuit stays (spec decision 2: no re-record on a model change under the same lead).
Done: test green. Commit: "workline: the leads line names the model the seat launches on (#708)".

## Task 5 — docs and gate
Files: `server/lib/server/trust.ex` moduledoc (one sentence: the record is per coworker; `record/2` splits it
by the model on the leads line; lines from before it are unknown), `server/AGENTS.md`/`server/docs/spec.md`
if either mentions the leads line (`rg "leads \(" server/AGENTS.md server/docs`).
Verify: `~/projects/menard/bin/menard run check --in server` → `ok`. Commit: "docs: trust per model (#708)".

Not in this plan: allowance per model (operator: stays per coworker), Roster use of `record/2` (#417's job
once it lands), threshold changes, grader scores.
