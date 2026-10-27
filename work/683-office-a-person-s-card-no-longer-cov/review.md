# Review: #683 office: a person's card no longer covers their conversation

**Verdict: approve.** Reviewed cb63e34 + c4ea509 (work/683-office-a-person-s-card-no-longer-cov @ c4ea5098e9b3) against ticket #683 and hronir's pinned shape (msg #15649).

## Spec compliance

1. **Conversation stays the body.** `rows = [head, ...threadRows(threadOf(c.thread), c.thread, 1)], ...cardRows` — threadRows is untouched, open() still sets `scroll = Infinity` for a person, and closed `cardRows` is at most one row, so the newest row the pane opens on is the one dim line directly under the latest messages. The scroller is untouched.
2. **Card shrinks to head pill + one dim line.** `personCard(..., false)` returns `[]` or exactly one `{tone: "dim"}` line: persona backstory, else the first soul line, truncated to width with a ` (space)` hint. Test covers all four soul/persona combinations.
3. **Full block behind a `person.*` bind listed in ACTIONS.** `person.space` ("the card", scope card:person) is in KEYS, and the action is appended to the person card's actions, so it renders in the ACTIONS column. The Sheriff's nameplate/mug/ledger go behind the same toggle, which is the right call: they were part of the pane-filling block.
4. **Why `space`:** every letter and symbol is taken on that screen (keys.test's one-verb-per-key rule), and the test file's own exemption line says "⏎ and space and the arrows are the lit row". I checked the dispatcher: `name = k === " " ? "space" : k; own = detail().actions.find(x => x.key === name)` runs the card's own action first, and the fallback switch has `case "enter"` but no `case " "`/`"space"`. So a bare space had no meaning on a person card before; nothing is shadowed. threadActions/liveActions/seatActions carry no space key either.

## Bugs / security

5. **State reset is correct.** `cardOpen` is a module-level flag reset to false on every `open({kind: "person"})`, so switching people never inherits an open card. Toggling sets `scroll = Infinity` both ways: opening lands on the persona block (what the toggle promises); closing lands back on the one-line card under the latest messages.
6. No security surface: pure data transformation of already-rendered soul/persona text, no new I/O.
7. CHECKS: `mise run check` green on the branch (office 928 pass / 0 fail). No bench_contrast row, so nothing to contrast.

## Nits (non-blocking, see follow-ups)

8. `persona?.backstory ?? sl[0]?.text…` — an empty-string backstory (`""`) does not fall through to the soul line (`??` only skips null/undefined), so such a person shows no card line at all. Cosmetic; seeds today always have a backstory.
9. The ticket's own acceptance step, a screenshot of a clicked coworker showing their latest messages against the live service, was not taken: the builder's sandbox cannot reach :4040, and neither can mine. The code reasoning in (1) is tight, but the pixel check belongs to whoever opens the office after the cut.
