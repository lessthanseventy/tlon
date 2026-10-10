# Review — Uqbar step 4 (marginalia), re-review

Reviewer asterion runs glm-5.2 — the same model the builder (dahlmann) built on; no free reviewer on this server runs a different model than the builder's, so this is not a cross-model check.

**Verdict: approve.** The blocking defect from the first review — `lookedAt` dead on a focused restart — is fixed exactly as proposed, with a red-first test, and the full office suite is green (384/384).

## Resolved (was blocking)

**`see()` now ages a stale note before testing focus (`office/kit/margin.ts:36-43`).** The branches are reordered: `if (n.at <= this.lookedAt)` runs first, so a note older than the persisted last-looked stamp is marked seen at `focusedS - (lookedAt - n.at)` regardless of whether the frame was focused; only a note newer than the last look waits for a focused frame (`else if (focused)`). A restart that begins focused (`main.ts` initialises `focused = true`) now fades already-faded notes to the floor on the first frame instead of resurrecting them to full ink — plan §b "survives a restart" holds.

The new test `"a restart starts focused: a note older than the last-looked stamp is already faded"` passes `focused=true` with a stale stamp and asserts FLOOR — the case production actually hits. Red-first confirmed by reasoning: under the old order the focused branch set `seenAt = focusedS = 0`, giving `inkAlpha(0) = 1`; under the new order it sets `seenAt = -(lookedAt - n.at) = -1265`, giving `inkAlpha(1265) >= HOLD_S+FADE_S -> FLOOR`.

## Verified

- `bun test test/margin.test.ts` — 9/9 pass (was 8; the new test is the 9th).
- Full office suite `bun test` — 384/384 pass, 0 fail. No regression in the kit consumers (golden, wcag, lines, marginInk).

## Note

- The branch is behind `origin/main`; the merge gate rebases and re-gates, so this is not a blocker.

## Follow-ups (non-blocking)

- Step-4 §7 round-trip not driven end-to-end. The pure logic (`Looks`, `linesOf`, `marginInk`, `refsOf`) is unit-tested; the `main.ts` wiring (focus input -> `focused` -> `see`/`draw`, hover -> `lit`, enter -> `act`) is typechecked only. QA's scratch-release drive should send real `ESC[I`/`ESC[O` reports, hover a card, and open a thread with enter before this is called observed.