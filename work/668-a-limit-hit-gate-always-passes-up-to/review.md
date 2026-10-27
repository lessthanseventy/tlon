VERDICT: approve

No free reviewer at the builder's grade (greybeard); reviewed by tzinacan at my own grade.

I read the full diff (workline.ex, needs.ex, tlon-cli.sh, the two test files). I did not run the suite; verify and landing gate it.

- `limit_hit?/1` and `grade_limits/1` read the newest review-scoped grade. Ungraded or failed counts as not limit-hit, which matches `Grade.allows?` and is flagged in plan.md.
- `approve/2` refuses `as: "uqbar"` on a limit-hit gate before anything else, so `--skip-qa` cannot get past it. A refused call records no QA skip, and a test covers that.
- `Needs.pass_up_rule` returns `:always` for a gate with limits. A test checks it goes to the phone, not Uqbar's group, and that settle and pass_up refuse it.
- The approval is recorded `by` the caller, not the gate's holder. Tests cover the operator and Uqbar.

Residual risk, not blocking: `as:` is the caller's `TLON_AUTHOR` env var, and the HTTP `/api/threads/:id/approve` handler (operator_api.ex:548) never passes `as:`. A deliberate bypass is still possible. This closes the accidental path only.

Heads-up for the gate: the change edits the approval path, so check the risk grade for limits before merge. A limit-hit result passes up to the operator.