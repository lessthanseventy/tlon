# Spec — a limit-hit gate is the operator's alone (#668)

## Problem
gate:372 hit the limit "a database migration"; Uqbar approved it from its shell and it landed with
the defect now tracked as #667. Today nothing stops this: `Needs.pass_up_rule/1` routes a gate by
kind alone (`{:when, @broad}`), `Needs.settle/3` is a blind `record/3`, and `tlon-cli approve` runs
`Workline.approve/2` over `bin/server rpc`, attributing the approval to `thread.awaiting || operator()`
— so an Uqbar approval is recorded as the operator's.

## Rule (operator, msg 14500)
A gate whose grade hits any limit is `pass_up` always: never in Uqbar's group, `settle_need`
refuses it, and `approve` refuses it from Uqbar. The guard sits where approval is recorded, so the
rule does not rest on routing alone.

## Design
1. **Caller reaches approve.** `Workline.approve/2` gains `as: handle` (default nil = the operator).
   `tlon-cli approve` passes `as: "$TLON_AUTHOR"` when that env var is set (agent shells have
   TLON_THREAD + TLON_AUTHOR; the operator's shell has neither). `approve/2` returns
   `{:error, :limit_hit}` when `as == "uqbar"` and `limit_hit?(thread)`. The `by` on the
   `workline:<slug>:approval` event (`record_approval/2`, via `queue/3`) becomes
   `as || thread.awaiting || operator()`.
   Honest limit: env is a convention, not a boundary — Uqbar could unset it. The ledger (`by`) and the
   routing/settle refusals are the other two layers; a hard boundary would need the rpc to take a
   minted token, which is out of scope.
2. **Gate item learns the limit.** Make `Workline.grade/1` public as `limit_hit?/1`
   (`match?(%{"limits" => [_ | _]}, grade(thread))`; nil/failed grade = not limit-hit, same as
   `Grade.allows?` already treats it). `Needs.wait/2` puts `limits: [...]` on the gate item when
   stage is `review`. New clause before the broad one:
   `pass_up_rule(%{kind: "gate", limits: [_ | _]}) -> :always`. `settle/3` already returns
   `{:error, :always}` for `:always` items; the MCP `settle_need` surfaces it as `:limit_hit` for gates
   (message: "hit a limit: yours to judge").
3. **No-limit gate approved from Uqbar's shell** is recorded `by: "uqbar"`, always. This changes what
   `tlon-cli approve` has meant: every earlier Uqbar approval was recorded as the operator's;
   from now the ledger says who decided. Landing still works.
4. **`--skip-qa`** goes through the same `approve/2` door, so it is refused identically for a
   limit-hit gate from Uqbar (tech lead's read; operator's confirmation pending on the thread).

## Tasks (each one commit, test first; build waits for #373 to land — both edit workline.ex)
1. `Workline.limit_hit?/1` — test: thread with a graded `limits: ["a database migration"]` → true;
   `limits: []`, no grade → false. (`server/test/server/workline_test.exs`)
2. `approve/2` `as:` — tests: `as: "uqbar"` + limit-hit → `{:error, :limit_hit}`, thread still
   awaiting; `as: "uqbar"` + no limit → ok, approval event `by == "uqbar"`; no `as:` + limit-hit → ok,
   `by` = operator; `as: "uqbar", skip_qa: "x"` + limit-hit → refused, no QA skip recorded.
3. `Needs` — tests: gate item with limits → `pass_up_rule == :always`, `grouped/1` routes it
   `pass_up`, `settle/3` → `{:error, :always}`; a no-limit gate is unchanged
   (`server/test/server/office/needs_test.exs`). Update the table in the moduledoc.
4. `scripts/tlon-cli.sh approve` — pass `as:` from `TLON_AUTHOR`; update the usage comment. Verify:
   `TLON_AUTHOR=uqbar tlon-cli approve <limit-hit-id>` prints `refused: :limit_hit`.

Done when: a migration-limit gate lands in phone, not uqbar; `settle_need` on it is refused; approve
as uqbar is refused for it and accepted for a no-limit gate — all by tests, `mix test` green.

## Open
- operator: confirm `--skip-qa` is refused the same way (default: yes).
