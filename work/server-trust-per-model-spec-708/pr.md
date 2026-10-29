# Server.Trust per model (#708)

A builder's trust record keyed by coworker name mixed models: a seat re-pointed at another model, or a
hire launched on its peers' model, kept one name's record. The `→ name leads (stage)` line the workline
machine posts when a seat takes a stage now carries the model that seat launches on, read from
`Server.Profiles.model_label/2` at hand-over: `→ ireneo leads (build stage) [model: anthropic/claude-sonnet-5-5 (claude_code)]`.
No new column, no migration, no history rewritten: lines from before this have no suffix and read as
model unknown.

- `Server.Trust.leads_line/3` writes the suffix; `model_of/1` reads it back.
- `record/2` is the per-model read (`strpos` on `[model: …]`, not LIKE: labels hold `_`). `record/1` is
  unchanged and counts every model, unknown included; an unknown line is in no model's record.
- `builder/1` returns `{name, model}`; `allowance/2` still ranks per coworker (the operator's call,
  #16512) and the approval card's earned-step note now says which model built the workline.
- `Server.Workline.hand_to/4` passes the model; a same-lead model change still posts nothing.

Closes #708. Roster's tie-break (#417) can call `record(name, model)` once it lands; not changed here.

Checked: `menard run test --in server` on `trust_test.exs` (4 tests) and `workline_test.exs` (84 tests,
two new: the earned-step note names the model, the leads line carries the seat's policy model), each
task red before green; `server:check` via `run_task` on the branch head.
