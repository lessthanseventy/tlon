# Review — 8811302, workline 251

**Verdict: request_changes.**

## Findings

1. **The clause is broader than the ticket, and its comment's premise is false.** `defp unheard?(%Message{author: "tlon"}), do: false` skips every tlon-authored message. The comment says a tlon-authored notice "@mentions no one", but tlon posts with a fixed addressee exist and are common: `@ireneo ✓ mise run check passed` (message #14232 on this thread), staffing.ex:304 `@#{agent} the machine restarted while you were mid-turn`, channel.ex:169 `#{mention}✅ child … closed`, jobs/smoke.ex:102 `to <> body`. For those the stale-lead blame #251 describes never applies, and today they get the 10–30 min unheard retry; after this diff a builder whose turn died on the check-passed wake waits for the 60-min stall nudge instead. Narrow the clause to the tlon post that names nobody (no @mention, no reply), which is the only shape that resolves to the lead *now*. Patch and a red-then-green test posted on the thread (#14237).

## Checks read

- `mise run check` green on 8811302 (CHECKS 19:46 and 19:53). No bench_contrast row.
- Not verified by me: I ran nothing; this is a read of the diff and `addressed/1`, `mentioned_agents/1`, `reply_author/1` in switchboard.ex.

## Non-blocking

- The test proves the predicate (tlon author, lead silent 12 min) but not the ticket's scenario (deliver, reassign the lead, assert the new lead is not woken), which the build brief asked for.