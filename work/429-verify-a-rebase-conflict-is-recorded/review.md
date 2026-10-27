APPROVE — verify: a rebase conflict is recorded as the branch's red (#429)

Read df070ee (scripts/workline-verify.sh, workline_verify_script_test.exs). Read review only; I did not run the suite.

- Non-gate path now calls `record-verify <tid> <slug> 1 rebase <conflicting files>` before `exit 1`. Same call and same `|| note` fallback as the existing recording at line ~181, so finish/5 sees a recorded check_failed and sends it back to build instead of Oban-retrying.
- WORKLINE_GATE (landing gate) path unchanged: echoes the finding, exits 1.
- Conflict list is captured before `rebase --abort`: right order.
- Empty `$conflicts` is accepted by tlon-cli record-verify (tail optional).
- New test asserts the `record-verify 7 pr-7-feature 1 rebase c` line, no `note`, no `advance`.

Nothing blocking. No follow-ups.