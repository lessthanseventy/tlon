# Review: uqbar-step-4-marginalia-plan-margin-kind @ 8645079

**Verdict: approve** — the blocking perf finding from 94758da is fixed; the backing decision is unchanged.

Since 94758da one commit, 8645079 (emma): the diff I escalated, applied verbatim. `LINEAR` is a 256-entry sRGB→linear table in `office/kit/palette.ts`; `luminance()` reads it (same formula as before, no behaviour change); `inkInto`'s `behind` computes each pixel's luminance from the bytes, compares the WCAG ratio numerically against the label colour's luminance, and builds the `#rrggbb` string once for the winning offset. `ROLE.ground` still answers an empty box (`worst < 0`). Same pixel wins as in dd5ba82, so which labels get backed is identical.

## Verified at the tip

Re-timed `inkInto` on the wide-room frame (`office()` fixture, 300 steps, 35 labels, kitty), six warm runs each, against my table from the last round:

| scale | dd5ba82 (last round) | 8645079 (now) | png encode of the same frame |
|---|---|---|---|
| k=2, 1392×400 | — | 0.7–4.0 ms | 3–19 ms |
| k=3, 2088×600 | 55–85 ms | 0.5–9 ms (median ~2.3) | 6–26 ms |

The painter is back under the encode, where it was at 44461f9 (~2 ms). The animation loop's per-frame cost is the PNG again, not the contrast scan.

- `bun test test/paint.test.ts test/wcag.test.ts` through cap: 16 pass / 0 fail (the worst-pixel red-first test, the balloon tests, and the wide/dark/rail WCAG sweeps).
- Server verify on this tip: `mise run check` passed (21:29:43Z, recorded on the workline).
- Tree clean; the only files touched are the two the finding named.

## Not re-verified
nolan's single-pixel contrast samples and the PNG render of the wide room on this tip (fact #1379). The patch does not change which pixel wins, so the backing is byte-identical to dd5ba82's; QA's margin-path pass is on head 44461f9 and is theirs to extend if they want it on the final sha. Not blocking code review.

## Follow-up (re-filed, from 44461f9)
k=1 / k=2 shared-row residue: when a cell row is taller than the 9 px line pitch (kitty k=1, or k=2 with cells ≥ 20 px) two margin baselines share one terminal row, so one note has no row of its own and stays unreachable by hover. A layout question (space margin lines by the cell pitch under kitty), not a hit-box one.

Advancing to the merge gate.