A gate whose risk grade hit a limit (a database migration, a dependency, a gate or CI change, …)
is the operator's alone. Closes #668: gate:372 hit "a database migration", Uqbar approved it from
its shell, and it landed with the defect tracked as #667.

- `Workline.limit_hit?/1` and `grade_limits/1`: the newest review grade's limits, read in one place.
- `Workline.approve/2` takes `as:` (the caller's seat). `as: "uqbar"` on a limit-hit gate is refused
  `{:error, :limit_hit}` before anything else, `--skip-qa` included. The approval event's `by` is
  the caller, so the ledger says who decided: a no-limit gate approved from Uqbar's shell is now
  recorded `by: "uqbar"`, where before every Uqbar approval was recorded as the operator's.
- `Needs`: the gate item carries `limits`; one that hit any is `:always` for routing — on the phone,
  never in Uqbar's group, and `settle`/`pass_up` refuse it (`settle_need` reports `:always`, whose
  message already says it always reaches the operator).
- `tlon-cli approve` passes `as: $TLON_AUTHOR` when set (an agent's shell; the operator's has none).

Known limits, stated in the spec: the env var is a convention, not a boundary (Uqbar could unset
it; the ledger and the routing refusal are the other two layers). An ungraded or failed grade is
not limit-hit, matching `Grade.allows?`.

Checked: test-first, each red for the stated reason before green — `workline_test.exs`
(limit_hit?, four approve cases), `needs_test.exs` (a migration-limit gate routes `pass_up`, settle
refused; a clean gate still waits with Uqbar). tlon-cli's four `opts` shapes printed with echo as the
server (record_check 11203). `check` run on the service at ac3d7bd.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
