APPROVE

Branch work/release-smoke-fails-on-main-since-380-on, one commit 1333acd on top of origin/main (88628bb). Diff: 3 lines in scripts/release-smoke.sh + the new pr.md.

Spec compliance
- The drive's keys are exactly the spec's: `"Enter" "Escape" "Escape" "c" "Escape" "R"`, and the one comment line above says why (reply box focused on open; first Escape leaves the box, second the card). Nothing else touched.
- pr.md: what changed, why, closes ticket #365, how it was checked.

Correctness (read, not re-run)
- office-drive labels each screen `=== after: <step>`; `after()` in release-smoke concatenates every section with that header. Only Escape repeats and no `expect` reads the Escape screens, so the duplicate headers change no assertion (`expect "c" "CREW"` still reads the single `c` section).
- TUI (office/tui/main.ts:621): a focused reply box eats `esc` as unfocus-and-redraw, which is the behaviour the fix accounts for. On home, `esc` is `back()`, a redraw with no card change, so the extra key is harmless if a card ever opens unfocused.
- Commit trailers: Co-Authored-By names the builder's launched model (claude-sonnet-5-5); Tlon-Model agrees.

Evidence
- Builder's report (#8165): `mise run release:smoke` red before the change (FAILED: the office after 'c' doesn't show 'CREW'), green after ("smoke passed on 88628bb"). The operator reported the same by hand in the opening.
- Server verify: `mise run check` exit 0 on the branch (brief, 04:52Z).
- I did not re-run the smoke myself.

Follow-ups: none.