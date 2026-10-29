# Review: intake's fallback waits on a manager's open triage (#521) — round 2

**Verdict: request_changes** — one finding, a doc the landing publishes. The code is approved as it stands; nothing in `intake.ex` or the tests needs to move.

Read: `git diff 37e2351..2721f54` (80163cc, 37e42ed, 2721f54) over `server/lib/server/intake.ex` and `server/test/server/intake_test.exs`, plus `work/…/pr.md`. Spec for the change: hronir's ruling (msg #16924). Checks: verify `mise run check` exit 0 on 2721f54 (08:19:09Z); I ran `menard run test --in server test/server/intake_test.exs` on this head: 25 tests, 0 failed. No bench_contrast row in the CHECKS; the branch edits no steering text, so none is owed.

## 1. Blocking: `pr.md` describes the behaviour this branch removed

`Server.Workline.Publish` (publish.ex:265) takes `pr.md` as the PR's description at landing, so it cannot wait for a follow-up: a follow-up is held until the merge, and the merge is what reads it. Witness, pr.md line 3 and 5:

> or a resolved consult naming `#N`; an open consult naming it blocks the fallback outright.
> Left open: a consult that is never resolved blocks the fallback forever (uncapped, per the plan).

Both sentences are the finding my first review reversed (80163cc: a consult is a deferral stamp, never a gate) and neither names the gate 37e42ed added (the manager's open operator ask). The test count is also stale (22 → 25). Fix, the whole of lines 3–7:

```
`Intake.start_stalled` read nothing from the channel, so a ticket the manager was still triaging (consult/ask naming it) could be staffed twice. Now the 30 minutes run from the newest of: the ticket's `updated_at`, a manager message naming `#N` on the workspace root thread after the route, a consult naming `#N` after the route, or the resolution of the manager's operator ask naming `#N`; while that ask is open it blocks the fallback outright. `held` is unchanged. When the fallback does fire, it also posts on the root thread naming the new thread.

Checked: `menard run test --in server test/server/intake_test.exs` (25 tests, 0 failures; 7 new: deferred by manager message, deferred by a consult, a pre-route consult ignored, blocked by the manager's open ask then fires once resolved + 30 min, a just-resolved ask still defers, root-thread post, number-prefix guard), `menard run check --in server`.
```

Drop the "Left open" line: nothing is left open, no object parks the ticket forever any more.

## What holds (verified on 2721f54)

- **Consult = deferral stamp.** `naming/2` bounds every query by `m.created_at > ^ticket.updated_at`; `stamps` are `created_at`/`resolved_at` with nils rejected; no `is_nil(resolved_at)` branch on consults. Closes round-1 finding 1 and its unbounded-scan follow-up.
- **The gate.** `Enum.any?(replies, kind == "prompt" and is_nil(resolved_at))` over the manager's root-thread messages naming #N after the route. `Attention.ask/4..6` posts `kind: "prompt"` with `author` the asker (attention.ex:283–292), so pane dialogs (author "tlon", line 165) can't match; every production closer goes through `Attention.resolve/2` (line 173), so nothing parks forever. As ruled in #16924.
- **Tests.** Both asks via `Attention.ask/4`, both resolved via `Attention.resolve/2`; the `update_all` on `resolved_at` is a clock shift after the runtime path produced the state, the same move as `age/2`. The `#N0` guard, the pre-route consult, the manager-reply deferral and `held` are unchanged.
- **2721f54** is a pure extraction (`manager_messages/1`, `naming/2`) for credo's complexity gate; the `dynamic` composition is equivalent to the two inlined queries it replaces. Behaviour unchanged, 25/25.
- **Moduledoc** was updated to the shipped semantics; only pr.md was not.
