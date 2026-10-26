# Review — rack: merge trains, one block per gate (#615) — **approve** (the lead's own: no free reviewer was at the builder's grade (greybeard))

## What was asked
#615 (#12850): the rack's LANDING & CHECKS listed one landing twice (its check row with pid + dir, and its merge-queue row), claimed "one landing at a time" though a train lands up to 4 cars on one gate (`Server.Jobs.Land @train_cars`), showed a car riding the running gate exactly like one waiting its own turn, and never marked a PR landing. Root: the server never reported train membership — `companions/2` lived inside the job; merge-queue items were `{thread_id, title, state}`. Tech lead (#12879) split it: server first (the job records the cars it took; `merge_queue` carries them and never recomputes `companions/2`), office second, off #616's `main.ts`/`types.ts` slice. No spec — the plan's pinned contract stands in for one (`plan.md`).

## What was built (branch `work/rack-show-merge-trains-one-block-per-gat`, 6 commits + pr.md)
- `f8b94a7` `Workline.land_train/3` takes `on_cars: fn ids, split -> _ end` — the rideable ids before the gate runs (the lead alone when nothing rides), and `([lead], true)` in `train/2`'s red-twice fallback.
- `efc6f5e` `Jobs.Land.record_cars/1` writes `%{"cars", "split"}` into the job's own `meta` (JSONB `||`, so meta it doesn't own survives), wired as the `on_cars` of the non-reland branch.
- `d31e88f` `Room.merge_queue/1` selects `meta`/`attempted_at`, derives `train`/`gate` from the executing job's meta; `health/0` computes `checks()` once and hands it in.
- `1465278` office: one `MergeItem` in `kit/types.ts`; `queueItems` → check|wait|gate|car|next|restart, the gate's own check folded into its header by pid, cars carrying `pos`/`lead`, `(PR · lands solo)` / `(own turn)`; `main.ts` renders gate/cars/next and its header drops "one landing at a time".
- `b535d60` the rack-card stub's gate start taken from the TUI's real clock (the suite freezes `Date`, the child process doesn't).
- `a9e000a` `pr.md`; `office/AGENTS.md` updated in this change.

## Contract compliance
- Payload `%{thread_id, title, state, train, gate}`, order unchanged — matches `plan.md`'s pinned contract.
- `train` = `%{lead, pos, size, split}` | `"solo"` | `nil`: a map only for a car of the executing job; the executing row always gets one (`"solo"` when it carries only itself), a queued non-member `nil`, a PR or reland `"solo"` in either state.
- Membership is read, never recomputed: `running_gate/2` takes `meta["cars"] || [thread_id]`; `companions/2` is untouched by the diff.
- `gate` on the running gate's items only, `pid` from the checks holder. I traced that end to end instead of trusting the test's fabricated line: `train/2`'s default gate is `gate_train(List.last(cars), …)` → `gate_on/2` calls `scripts/workline-verify.sh` with the thread's id and slug → the script writes `CHECKS_LABEL="${CHECKS_LABEL:-#$tid $label $slug}"` (label `landing` under `WORKLINE_GATE`) → `checks-queue.sh` writes `<label> (pid $$) in $PWD since …` to the holder. So a train's holder line really does start `#<last car id> landing `, which is what `gate_pid/3` matches; solo (`#<id> landing `) and PR (`PR #n landing `) match their own paths. **Holds.**
- Office: a check the gate doesn't own stays a `check`; an older server that sends no `train`/`gate` still reads (its landing a gate of one) — the third `rack.test.ts` case.
- Deviation from the plan, deliberate and right: a *running* PR/reland carries a `gate`, where the plan's test sketch (b) said `gate nil`. The PR's check row is only foldable by that pid, and the plan's own contract line ("`gate` on the running gate's items only") says so. Noted, no action.
- Out of scope as planned: per-car red/green, queue reordering, train size.

## Verification
- The server ran the full `mise run check` on `a9e000a` (the branch head, clean tree): exit 0, server + adapters + office green (#12986, in the brief's checks). Verify froze the branch there and nothing has been committed under it since.
- I ran the pure office test myself on this branch: `bun test test/rack.test.ts` → 5 pass, 0 fail.
- I did not re-run `rack-card.test.ts` (it drives the real TUI through tmux); it is covered by the gate above.
- No blocking finding: the payload, the label→pid path, the fold, the back-compat case and the doc sync all check out.

## Follow-ups (non-blocking)
1. `ride/4`'s halt fallback leaves the stale train in the job's meta — see the filed follow-up.
2. The gate header reads "gate running" while its check waits in the machine's queue — see the filed follow-up.
