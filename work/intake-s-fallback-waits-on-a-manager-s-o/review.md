# Review: intake's fallback waits on a manager's open triage (#521) — round 3

**Verdict: approve.** The one blocking finding of round 2 (pr.md described the removed consult block) is fixed in 6ffb934, word for word the text I prescribed. Nothing else changed.

Read: `git diff 92dc229..6ffb934 -- . ':!work/…'` is empty — no code moved since the round-2 review, which approved `intake.ex` and the tests as they stood. `git diff 92dc229..6ffb934 -- work/…/pr.md` is the whole change. Checks: verify `mise run check` exit 0 at 08:29:35Z on this head (branch artifact `work/intake-s-fallback-waits-on-a-manager-s-o @ 6ffb934`); I ran `menard run test --in server test/server/intake_test.exs` on 6ffb934: 25 tests, 0 failed. No bench_contrast row in the CHECKS; the branch edits no steering text, so none is owed.

## 1. Round-2 finding, fixed

pr.md line 3 now names the shipped semantics: the 30 minutes run from the newest of the ticket's `updated_at`, a manager message naming `#N` on the root thread after the route, a consult naming `#N` after the route, or the resolution of the manager's operator ask; the open ask blocks outright. The "Left open: a consult that is never resolved blocks the fallback forever" line is gone — nothing parks the ticket forever any more. Test count 25, 7 new, matches `intake_test.exs`. `Server.Workline.Publish` can take this as the PR body.

## What holds (unchanged since 2721f54, re-verified by the empty code diff)

- **Consult = deferral stamp.** `naming/2` bounds every query by `m.created_at > ^ticket.updated_at`; `stamps` are `created_at`/`resolved_at` with nils rejected.
- **The gate.** `Enum.any?(replies, kind == "prompt" and is_nil(resolved_at))` over the manager's root-thread messages naming #N after the route. Pane dialogs (author "tlon") cannot match; every production closer goes through `Attention.resolve/2`.
- **Tests.** Both asks via `Attention.ask/4`, resolved via `Attention.resolve/2`; the `#N0` guard, pre-route consult, manager-reply deferral and `held` unchanged.
- **2721f54** is a pure extraction for credo's complexity gate.

## Follow-ups

None. The `resolved_ago/2` helper nit from round 2 was dropped by the builder because the test file was not otherwise touched; I agree it does not earn a ticket.
