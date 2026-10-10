# Review — Uqbar step 4 (marginalia)

**Verdict: request_changes.** Server half (migration, `margin` kind, switchboard, needs, `Office.Margin`, route, `margin_note` tool) is clean, test-first, and spec-true. The office half has one blocking defect in the "since you last looked" core; the FLOOR 0.45→0.65 deviation is justified (the plan's own ≥4.5:1 test fails at 0.45) and guarded by a test, so it stands.

## Blocking

**`lookedAt` never takes effect on startup — "survives a restart" (plan §b) is dead.**

`office/tui/main.ts:170` initialises `focused = true` (the stated graceful degradation for terminals without DEC 1004). The first `looks.see(notes, true)` in `addMargin` (`main.ts:1719`) therefore marks every note newly-seen at `focusedS = 0`. The persisted `~/.local/state/…/margin-looked` stamp is only consulted in the `else if (n.at <= this.lookedAt)` branch of `see()` (`office/kit/margin.ts`), which runs only when `focused` is **false** — and a fresh start never is (no focus-out precedes the first frame, and by the time one arrives, every note is already in `seenAt`). Consequence: notes that had already faded to the floor return to full ink after a restart and re-fade over ~21 minutes, contradicting plan decision (b) "Survives a restart".

The dedicated test `"a note older than the last-looked stamp is already seen, aged by the wall gap"` passes `focused=false`, so it proves the branch works but not that production ever reaches it. Fix — reorder the `see` branches so a note older than the last look is aged regardless of current focus, and add a red-first test that starts focused with a stale stamp:

```ts
// office/kit/margin.ts
see(notes: Note[], focused: boolean) {
  this.focused = focused
  for (const n of notes) {
    if (this.seenAt.has(n.id)) continue
    if (n.at <= this.lookedAt) this.seenAt.set(n.id, this.focusedS - (this.lookedAt - n.at))
    else if (focused) this.seenAt.set(n.id, this.focusedS)
  }
}
```

```ts
// office/test/margin.test.ts — currently fails, green after the reorder
test("a restart starts focused: a note older than the last-looked stamp is already faded", () => {
  const l = new Looks(10_000)
  l.see([note(1, 10_000 - (HOLD_S + FADE_S) - 5)], true)
  expect(l.alpha(note(1, 0))).toBe(FLOOR)
})
```

## Notes (not blocking)

- **Branch is 31 commits behind `origin/main`.** `787210c` (server-side tool refusal via `Server.MCP.Tool.refusal/2`, wired through `@before_compile`) and `014d036` (profiles → Claude Code cut lists; pi driver removed) landed in that gap. The merge gate will rebase onto main and re-gate; `endpoint.ex`, `server_test.exs` and `office/tui/main.ts` are touched by both sides. Under main's exclude-based refusal (allow-by-default), `margin_note` is in no cut list, so the builder's open item #4 ("not in the pi directTools allow-list") is moot — it is reachable via the Claude Code MCP either way, and there is nothing left to add to `profiles.ex`.
- **Step-4 §7 check not driven end-to-end.** The pure logic (`Looks`, `linesOf`, `marginInk`, `refsOf`) is well unit-tested; the `main.ts` wiring (focus input → `focused` flag → `see`/`draw`, hover → `lit`, enter → `act`) is typechecked only. The unfocused→`ESC[I`→full-ink→fade round-trip, hover-lights-card, and enter-opens have not been observed in a live office; QA's scratch-release drive should send real `ESC[I`/`ESC[O` reports, not just assert types.