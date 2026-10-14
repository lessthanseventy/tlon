# APPROVE — meteor crater lands in the street seen through the window

**Reviewer grade note.** No free reviewer is at the builder's grade (greybeard) — the builder is hronir on a Claude plan model; I am tzinacan on glm-5.2 (ollama). Reviewing below the builder's tier; findings checked by reading the diff and the render geometry, not by a second model pass.

**Verdict: approve.** The change is minimal, spec-compliant, red-first tested, and the gate is green (verify recorded `mise run check` exit 0; hronir's `bun test --timeout 60000` → 559/0).

## What changed (45f0c72, 3 files, +9/-3)

- `office/kit/events.ts` — the meteor's puff and crater move from `doorX-60, hallY` (indoors, on the hall floor) to `windowX+8, 35`, where the streak ends inside the window pane. One load-bearing comment explains why: the wide room has no street of its own; the street outside is the view through the glass, as the spec/design ("lands in the street with a puff of smoke") intend.
- `office/kit/zoo.ts` — the puff sprite grows 5×3 → 7×4 and the crater 5×3 → 9×3, so they read at a glance (ticket #348's "easy to miss"). Both sprites are rectangular (every row equal length), consistent with the blit-grid convention.
- `office/test/events.test.ts` — one new case pins the puff at t=150 and the crater at t=300 to `windowX+8, 35`. Red-first per the builder: it failed at (540, 190) before the move.

## Spec compliance

The ticket asked: does the crater move, or does the spec change? The decision (banked #1904/#1905, documented in pr.md): the crater moves, the spec stands. The streak travels (windowX+28, 8) → (windowX+4, 34); the crater's feet at (windowX+8, 35) place its body at y 32–34, its left edge at windowX+4 — flush with the streak's endpoint. The landing reads as "the meteor hit where the streak disappeared, out in the street behind the glass." Sound.

## Geometry check

`drawProp` blits with feet at (x, y): `x - width/2` (centered), `y - height` (bottom at y). For the 9×3 crater at (208, 35) with the test's geo (windowX=200): spans x 204–212, y 32–34 — inside the pane's left half, within the streak's y-range. The 7×4 puff at the same anchor spans x 205–211, y 31–34. Both fit; neither overflows the sill. The old `doorX-60` (540) was on the hall floor indoors — the fix is correct.

The y=35 / windowX+8 constants match the existing style: the streak line two lines up already hardcodes 8 and 34 rather than naming them, so no new magic-number sin is introduced.

## Notes

- The builder already filed the side finding as ticket #352 (bun 1.3.14 ignores `bunfig.toml`'s `[test] timeout`; the gate must pass `--timeout` on the CLI). No action here.
- No follow-ups: the change is surgical and the one nit (hardcoded landing coords) matches the surrounding idiom — not worth a held ticket.