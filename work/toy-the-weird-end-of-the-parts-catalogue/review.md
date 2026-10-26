# Review — toy-the-weird-end-of-the-parts-catalogue

**Verdict: request_changes**

Ten parts as data in `office/kit/parts.ts`, `figure()` untouched, dials only. The library invariants and the 69k-figure stable-looks golden are green. One real defect: the fishbowl deletes the head it is supposed to cover.

## Blocking

**`fishbowl` erases the head inside the glass.** It draws through `hat()`, which turns every `.` in a crown row into `_` (clear). The bowl's interior is written as dots — `${d.glass}....${d.glass}` — so the wearer's hair at rows 1–2 is deleted and the *room* shows through the bowl. Rendered with `figure({...lookOf("yu"), head:{id:"fishbowl"}}, …)`, front:

```
             plain          fishbowl
  row 1  ...h..h..h..     ...c....c...   hair gone (spiky/curly/long/parted)
  row 2  ..hhhhhhhh..     ...c....c...   hair gone (every style)
  row 3  ..hhhhhhhh..     ..cccccccc..
```

A see-through helmet should show the head *under* the glass. `halo` and `ufo` right below get this right and say why in a comment ("hover over the hair rather than sit on it: nothing is cleared"); the bowl should be built the same way — a view of `mid()` rows where `.` leaves the pixel:

```diff
-  fishbowl: part("head", { glass: ["c", "w"] }, (d) => hat(3, [rep(d.glass, 6), `${d.glass}....${d.glass}`, `${d.glass}....${d.glass}`], rep(d.glass, 8))),
+  // a bowl is see-through: the head shows inside it, so nothing is cleared (unlike a hat)
+  fishbowl: part("head", { glass: ["c", "w"] }, (d) => {
+    const v = (shift: number): View => ({ 0: mid(rep(d.glass, 4), shift), 1: mid(`${d.glass}......${d.glass}`, shift), 2: mid(`${d.glass}......${d.glass}`, shift), 3: mid(rep(d.glass, 10), shift) })
+    return { front: v(0), side: v(1), back: v(0) }
+  }),
```

8-wide walls at cols 2 and 9 enclose the hair rows; the rim at 10 covers the 10-wide head row. Rendered over mop/curly/spiky/parted: hair stays, glass surrounds it. Width is yours to tune — the point is that the bowl must not clear.

## Checked

- `bun test test/weird-parts.test.ts test/parts.test.ts test/looks.test.ts test/stable.test.ts test/dials.test.ts` → **33 pass, 0 fail**. `parts.test.ts` sweeps every part × every dial × three views against its slot's paint letters, so the new rows are in-bounds and clear 3:1 by the existing test.
- `stable.test.ts`'s 69125-figure sha still matches (`lookOf` sets no parts). `rollLook` and `nextPart` read `idsIn`, so the look card cycles the new ids with no other change — head goes 7 → 14, `PART_IDS` 21 → 31.
- Rendered all ten front and side through `figure()`: duck, cone, plantpot, cloud, ufo, halo, banana phone and horn read as their things; the snail's front/back is on the shoulder.
- Server verify passed on this branch; I did not re-run the full office suite.

## Follow-ups

See the three filed with this review: eyeball the parts in the look card (office law: a frame change is seen, not assumed); the snail's side view hangs in front of the chest; the halo's `glow` and horn's `toot` dials are inert (behaviours #98 named, left to a sim hook).
