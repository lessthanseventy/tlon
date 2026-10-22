# Review — #166 B: one LANDING & CHECKS list in the rack, plus pending restart shown

**Verdict: approve**

## What was asked
The rack card (`H`) had two sections — CHECKS QUEUE and MERGE QUEUE. The spec (decision fact 3138): collapse them into one LANDING & CHECKS list in this order — the running check, the waiters in `checks/0` ticket order (ticket order since #166 A), the landing, the queued, then a pending restart from `/settings` `restart_pending`. Rack-only: no top-bar edits, no new Need kinds.

## What was built (commits a92c2f2, 23bd8d2)
- `office/kit/rack.ts` — pure `queueItems(h, restartPending): QueueItem[]`, one list in the spec's order. `Queues` is a structural subset of `data.Health` (`checks?: { running, waiting }`, `merge_queue?: { thread_id, title, state }`), so passing the cached `rack` typechecks and the pure test can feed a minimal object.
- `office/tui/main.ts` — the rack `detail()` swaps the two section headers for one `LANDING & CHECKS` header and renders `queueItems(rack, settings?.restart_pending ?? false)`. `settings` is re-fetched with `data.health()` in the `health` branch of `readCard` (`Promise.all`); the `?? false` fallback keeps the rack correct when settings hasn't loaded. Marks: `▶` live for check/landing, `⧗` inactive for wait/queued, `↻` attention for restart; landing/queued rows keep their `tidSeg` + `goThread` opener.
- `office/test/rack.test.ts` — pure list: full order, `thread_id` carried, empty cases (nothing queued / a server too old to send queues), restart-alone.
- `office/test/rack-card.test.ts` — real TUI against a stub server; asserts the five items appear in strictly increasing screen position, and that `CHECKS QUEUE` / `MERGE QUEUE` are gone. Went red first (emma: the rack still showed the old sections).
- `office/AGENTS.md` — the checks-queue line now states ticket order and points at the rack's one-list behavior + `kit/rack.ts`. Updated in this change.
- `work/.../pr.md` — present.

## Spec compliance
- Order: running check → waiters (array order = `checks/0` ticket order) → landing → queued → pending restart. **Matches.**
- Restart source: `/settings` `restart_pending` (a `boolean` on `data.Settings`). **Matches.**
- Rack-only, no top-bar, no new Need kinds. **Matches** — the diff is `kit/rack.ts`, the rack branch of `tui/main.ts`, tests, `AGENTS.md`, `pr.md`. Nothing else.
- `AGENTS.md` kept in sync in the same change. **Yes.**

## Verification
- Builder: `bun test` 806 pass / 0 fail; `tsc --noEmit` clean. Tests written red-first.
- Verify: the server ran the full `mise run check` on the branch head — exit 0 (806 office tests, server + adapters green). Recorded in the brief's checks.

## Notes
- The `run_task.ex` / `run_task_test.exs` "deletions" in `git diff origin/main..HEAD` are an artifact of `origin/main` having advanced past this branch's base (2d84324) and added those files after the branch was cut — they are **not** this workline's changes and are not on the branch's two commits. The merge gate rebases onto `origin/main` before gating, so they reappear; no action.
- The `Queues` type in `kit/rack.ts` is a local structural subset rather than importing `data.Health`. Intentional and correct: it keeps the pure function decoupled from the data module and lets the pure test pass a minimal fixture. Not a nit.

## Follow-ups (non-blocking)
- Waiters lost their `1. 2.` queue-position numbering (old code: `dim(`${i+1}. `)`); they now share the `⧗` mark with queued items. List order still conveys queue position, so this is not a regression in information, but the numbers were a legibility aid (the operator has low acuity). Worth a look if the rack ever feels hard to scan.