Office talk step 4 (ticket #73): the conversation with X, and the room stops saying "lobby".

- `v` on a person's card opens the lobby as a reader filtered to X's posts plus the operator's posts that `@X` or reply to X's (`conversation()` in `tui/talk.ts`, a filter — no DM schema). Replying in it posts `@X …` to the lobby. The person's work thread moves from `v` to `w`.
- `Reader` takes optional `keep` (filter) and `heading` deps.
- The standing thread is shown as "the front desk" (one mapping in `data.status()`); the "no lobby" status line says "front desk".
- Not done: §3's `… (v)` balloon tail has no producer yet; #general is already invisible (the office reads no channels).

Checked: `OFFICE_TEST_HOUR=15 mise run office:check` — typecheck clean, 490 pass / 0 fail (run twice, hours 3 and 15). The `v` flow itself was not driven in the live TUI.
