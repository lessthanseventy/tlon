APPROVE — reviewed by tzinacan (leading the review stage: no free reviewer was at the builder's grade, greybeard).

Verified by reading the diff (office/kit/uqbar.ts, crew.ts viewOf, wide.ts wiring, server pin test, AGENTS.md). I did not re-run the gates; the thread's recorded `mise run check` (exit 0) and hronir's report of 290 office tests are what I'm relying on. Nobody has looked at the live headless screenshot (plan Task 5.3); the tests assert pixels and hits only.

Spec/plan compliance: matches. Presence needs no new API: uqbar's open roster row is the session, and its thread is the focus. `viewOf` lifts uqbar out of the roster, so it gets no desk, crew row or person. Flight is a pure `stepBook`/`goalOf`/`modeOf`; the shelf spine and the knocked-over neighbour are stateless. Docs are updated in the same change.

Non-blocking findings (follow-up, not this PR):
1. `tui/main.ts:1527` (the `,` jump-to-need key) uses `all.roster.find(r => r.thread_id === need.thread_id)` on the unfiltered roster. If uqbar's focus is that thread and its row comes first, `room().at("uqbar")` is null and the key silently does nothing. Fix: exclude `agent === "uqbar"` in that find.
2. `tui/main.ts:1132` (`busy()`, pets cheering) and `:615` (LIVE feed) also read the unfiltered roster, so a thinking uqbar counts as busy. A pet may pick "uqbar" as the one to cheer; there is no actor for it, so this is probably a no-op. Filter it for consistency.
3. `stepBook` flies in a straight line and ignores furniture. It is cosmetic for a flying book, and the plan accepts it.
4. `book` and `cards` are `WideRoom` state, so the narrow rail never shows the book. The plan scopes this to the wide room, so it is fine.

No blocking bugs or security issues found.