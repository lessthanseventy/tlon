# Review: 342 wide room's dog slot reads pets.json — at 772a54a

**Verdict: approve.** Both blocking findings from the round at a8fb7c3 are fixed, and follow-up 1 with them. The gate is green on the branch (`mise run check`, office 920 pass / 0 fail, tsc clean; no bench_contrast row in CHECKS).

## 1. Coat ramp — fixed, measured

The witness, `office/kit/pets.ts:207`:

    const coat = d.shade > 0 ? tint(ROLE.prose, ROLE.body, [0, 0.15, 0.3, 0.45][d.shade]!) : ROLE.body

Computed on this branch (`bun run` against `kit/palette`):

    shade 0..3: #FFB000 #f7b31e #eeb73c #e6ba5a   (body #FFB000 → prose #C7C7C7, monotonic)

Identical to the "args swapped" row I predicted last round. The new test (`pets.test.ts:416`, "the dog's shade") drives `drawDog` with a stub scene and asserts the last `figure` paint's luminance distance to prose shrinks 1→2→3 and that shade 1 is nearer prose than the body. Builder reports it red before the swap (Expected <50, Received 75); I ran `bun test test/pets.test.ts test/store-view.test.ts test/wide.test.ts`: 77 pass, 0 fail.

## 2. pr.md — fixed

Bullet 5 is gone; the closing Spec note carries the admission and is true of the diff (the only `work/` path touched is this workline's own).

## Follow-up 1 — fixed

`office/tui/main.ts:1889` title now reads `(petsNow ?? resolvePets(loadPets())).dog.name.toUpperCase()`, the same source the store card uses at `:2007`, so a narrow terminal names the adopted dog too. Same pattern as the cat draft at `:635` and `:1859`.

## Still open, non-blocking

Follow-up 2 (menu and home literals "Argos, the dog" / "or Nina, or Argos") was dropped as parity with the cat's literal "Nina, the cat". Agreed it is not this change's defect; listed below so it is not lost.

## Checked and fine (unchanged since last round)

- Store card occupant, exchange prefix parser, the `this.line("Argos", …)` role key (fact 4320), `p.dog.shade ?? 0` clamp, the tooltip with the name.
