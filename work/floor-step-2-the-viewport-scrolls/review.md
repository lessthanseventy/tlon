## Verdict: CHANGES REQUESTED

The viewport/pan plumbing (clamp, pan, center, kitty source-rect crop, textLayer crop, Ink/Hit
clipping with edge markers, shift-arrow keys, drag) is well built and unit-tested — 17/17 green
on the new/changed suites (`viewport.test.ts`, `paint.test.ts`, `term.test.ts`, `sim.test.ts`),
`Sim.at`/`peopleAt` rename is clean with no leftover call sites. But the feature this ticket asks
for does not actually engage in normal use — two deviations from spec.md/plan.md, compounding:

### 1. `layoutScreen`'s fit-based width/k selection (office/tui/main.ts:887-895) was never touched

§4 of the design doc is explicit this must change: *"Today `layoutScreen` picks the largest whole
scale ≥2 at which the whole room fits the terminal... **The floor has no 'fits'**."* That loop is
untouched by this diff (confirmed via `git diff main...HEAD -- office/tui/main.ts` — only the
`viewport`/`drag` state, `onKey`/`onMouse` cases, and `draw()` wiring were added; the `for (let k =
...; k >= 2 ...)` width-pick loop at the top of `layoutScreen` is identical to main). It still
picks `wide` (the floor's width) and implicitly a `k` so that the WideRoom **always** fits the
terminal on both axes (width via the loop, height because `WIDE_H` is fixed and the same loop
picks `k` to fit it too) — or falls back to the narrow RailRoom if it can't. There is no code path
left where the WideRoom renders larger than the terminal. Net effect: the pan keys, drag, and edge
markers are real and tested in isolation, but a user will never see the floor pan in practice,
because the floor is still always sized to fit before `geometry()` ever runs.

This matches ireneo's own note that drive-office "can't exercise WideRoom under tmux... so no real
pan distance was observed end to end" — that gap in verification is this bug, not just a sandbox
limitation.

### 2. `geometry()`'s kitty branch keeps the old fit-derived `k` instead of the decided flat `k=2`

spec.md and yu's plan (task 4) are both literal: *"k is fixed at 2 for kitty mode... a flat, simple
rule, not derived from floor or terminal size"*, with plan's own code sample being `const k = 2`
unconditionally. The shipped code instead computes `naturalK` from fit and only falls back to 2
when `naturalK < 1`:

```ts
const naturalK = Math.min(Math.floor((termCols * cell.w) / W), Math.floor((room * cell.h) / H))
const k = naturalK >= 1 ? Math.max(1, Math.min(5, naturalK)) : 2
```

Repro (floor pinned at the office's own `WIDE_MIN_W`×`WIDE_H` = 540×200, a terminal big enough to
fit it comfortably):

```
geometry(540, 200, 400, 100, 20, { w: 8, h: 18 }, true).k === 5   // not 2
```

The one new test (`paint.test.ts` "flat legibility scale of 2") only exercises the floor-bigger-
than-terminal case (`naturalK < 1`), so it passes without covering the regression — a floor that
*does* fit still gets the old auto-fit scale, not the spec'd flat 2. This is also an unflagged
deviation — ireneo's build reports named two (kittyImage's x/y protocol scaling, textLayer's
ANSI-stripped test) but not this one.

Items 1 and 2 need to be fixed together: `layoutScreen` must stop choosing the floor's size to fit
the terminal, and `geometry()`'s kitty branch must drop the fit-derived path entirely per the plan.
Until then this ships inert machinery, not the scrolling floor the ticket (and §4) describe.

### Checked, no issues found

- `kittyImage`'s placement source rect scales `x`,`y` by `k` as well as `w`,`h` — correct, since
  the transmitted PNG is itself `k`×; confirms ireneo's own flagged-as-uncertain call was right.
- `clipFrame`'s hit-drop and edge-marker direction/glyph logic match spec.md and their tests.
- `Sim.at(agent)` / `peopleAt` rename: no stale references, 6 call sites in `wide.ts` all updated.
- `office/test/wcag.test.ts`'s `labels()` sweep over viewport positions is correctly derived from
  `clampViewport`, steps by one cell as spec'd (degenerates to a single position when the floor
  still fits, which — see above — is everywhere today, but the loop itself is right for when it
  doesn't).
- The server-side commits at the base of this branch (`baf07ad` workline continuation/sweep nudge)
  predate this workline's spec/plan/build commits and are unrelated to ticket #20 — out of this
  review's scope, not reviewed here.

### Not verified

- No real kitty-capable terminal was used (by ireneo or here) to confirm the `a=p` placement crop
  actually displays correctly — flagged already in the build, still open.
