# Review: mod.ts: count a background subagent from agent.spawn, not turn.start (#546)

**Verdict: approve.** Branch work/mod-ts-count-a-background-subagent-from @ 33f5ece, diffed against origin/main (merge-base 14d491c). Four files, +25/-24.

## Verified

- `mise run adapters:claude-code:mod` run by me on the branch: 48 pass, 0 fail (log `.logs/20261029T175838-mise-run-adapters-claude-code-mod.log`). The verify stage's `mise run check` row is green (exit 0). No `bench_contrast` row in CHECKS.
- Commit trailer `Co-Authored-By: claude-sonnet-5-5` matches `Tlon-Model: anthropic/claude-sonnet-5-5`.

## Findings

1. **The fix matches the brief (msg 17632) and the cause.** `agent.spawn` now awaits `next` on both the plain and the Explore→haiku path and adds `r.agentId` when present; `turn.start` keeps only `mainEnded = false` and the thinking declare; `turn.complete` is untouched, so `running.delete(e.agentId)` / `mainEnded = true` / the `running.size === 0` idle check stand as before. The STALE_REFRESH poll (mod.ts:538) and `session.end`'s `running.clear()` need no change.
2. **The guard is right.** `if (r?.agentId)` covers a remote or isolated agent and a hook-refused spawn, where the result has no id; nothing is added, so a seat cannot be pinned busy by an agent that never gets a `turn.complete` of its own.
3. **The tests now pin the host's contract, not an invented one.** Every `turn.start({... agentId})` is gone. The RED path is real: emma reports 2 fail before the change, both an unexpected `presence_idle`, which is exactly #440's live symptom. The deleted test ("a subagent's turn.start declares no presence_thinking") asserted an event the host never raises; dropping it is correct, and `turn.start` always declaring thinking is now the whole truth.
4. **Deviation accepted.** The fake engine's `agent.spawn` returns `{ model, agentId }` because the kit rejects a spawn result without `model`; the compaction test spawns before its subagent `turn.complete` instead of losing the "a subagent completing doesn't compact" assertion. Both preserve what was asserted.
5. **Docs in step.** README's "Being a citizen" line says the subagent counts from `agent.spawn` since the host raises no `turn.start` for it. pr.md names the cause, the guard, the ticket and the check.
6. **Not verified by me:** the host's own type file. I could not locate Claude Code 2.1.293's hook `.d.ts` on disk (not under its nix store path, and `claude-code/testing` resolves inside the host). The contract I reviewed against is the one the tech lead quoted in msg 17628/17632 (`TurnStartInput` has no `agentId`; `agent.spawn` resolves the id). The kit accepting `{ model, agentId }` as a spawn result is consistent with it. The owed live proof is what closes this.

## Out of scope, already owned

Typechecking mod.ts against the host's types in `adapters:claude-code:check` is hronir's follow-up ticket per the brief. #545 (a spawn that never completes pins the seat busy) stays its own ticket, by this fix's design too.
