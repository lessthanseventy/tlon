# Review — office talk step 4: the conversation with X (`v`), front desk naming

**Verdict: approve.**

Read: the full diff `origin/main...035a3d6` (office/tui/{talk,reader,main,data}.ts and their tests), plan.md, pr.md, design doc §2 and §4. Ran `OFFICE_TEST_HOUR=15 bun test test/talk.test.ts test/reader.test.ts test/data.test.ts test/dogear.test.ts`: 18 tests, 0 fail. The server's verify ran `mise run check` green on the branch (exit 0, 11:23Z).

## Spec compliance

- §2 "the conversation with X": `conversation()` keeps X's posts plus the operator's posts that `@X` or `reply_to` one of X's. The ticket's acceptance test (keeps exactly [1,2,5], drops system, `@adam` vs `@ada`, replies to others, unaddressed posts) is present and green. The mention regex escapes the handle and uses `(?![\w-])`, matching `replies()`'s `[\w-]+` capture — consistent.
- §2 "`v` on their card opens it": wired on the person card; the work thread moves to `w`, and the thread's own `v` is filtered out so the key is bound once. Design leaves this open; plan decision 1 states it. Reasonable.
- §4 naming: one mapping in `data.status()` (standing + title "lobby" → "the front desk"); all cards, finder, reader head read `Agents.threads`, so one place suffices. The remaining "lobby" strings in office/ are code comments. `#general`: nothing in office/ renders channels, so already true — correctly nothing built.
- Reader `keep`/`heading` are optional deps; the default path is unchanged (dogear test still green).

## Notes, none blocking

- Replying in the conversation reader posts `@X …` via `speech()`, so it is the same post `m` makes. `?? body` only fires on a whitespace-only body, which the composer's `empty` check already stops in practice.
- The filter sees loaded pages only (plan decision 3, same limit `replies()` documents); paging still works since the filter runs at render.
- The `v` flow was not driven in the live TUI by builder or reviewer; the wiring is typechecked and small, and the logic is unit-covered.
- §3's `… (v)` balloon tail stays out: no producer. Flagged in pr.md; not this ticket's check.