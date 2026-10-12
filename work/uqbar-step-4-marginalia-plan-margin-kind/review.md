APPROVE — Uqbar step 4 marginalia (margin kind, focus-time fade, hover/enter), re-reviewed at 1cb8f20 after the rebase onto origin/main.

Since the last round (7701565) the branch changed by one commit, 1cb8f20: a note's hit now starts at the viewport edge (`x: vp.x`, width + 2) so the terminal cell holding the first glyph is on it — the QA miss where hover left `lit` null and Enter fell through to FIND. Right edge unchanged (`vp.x + vp.w - 2`). Red-first test on the hit's left edge. Correct.

Rebase: the one conflict in office/tui/main.ts kept both main's `flown` set and the branch's `loadMargin`; both present in the diff.

Verified: read the branch diff (origin/main...HEAD, office + server) and the diff since 7701565; `bun test` office margin/term/data 17 pass, 0 fail; the server's verify ran `mise run check` on this tip, exit 0 (19:29Z).

Checked and not a finding: in kitty mode the margin's hover (`roomChanged` only) and the 1s fade redraw never set `imageDirty`, but `Sim.step` reports a change at least every 4th tick (400ms) and `changed()` re-sends the image, so the lit card and the fade land within half a second — the same convention `esc`/`back` already rely on.

No blocking findings; no follow-ups.