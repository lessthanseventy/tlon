# Review: 342 wide room's dog slot reads pets.json — at 6e50685

**Verdict: request_changes.** One real bug in the one line no test covers; one pr.md line that contradicts the paragraph under it. Everything else matches the brief (#14730) and the gate is green (`mise run check` on the branch, office 919 pass; no bench_contrast row in CHECKS).

## 1. The coat ramp runs backwards (blocking) — `office/kit/pets.ts:207`

The witness:

    const coat = d.shade > 0 ? tint(ROLE.body, ROLE.prose, [0, 0.15, 0.3, 0.45][d.shade]!) : ROLE.body

`tint(c, base, t)` is `base + (c − base) · t` (`kit/palette.ts:31`). The cat's `furOf` (`kit/draw.ts:204`) calls it `tint(ROLE.prose, ROLE.fieldInk, t)`: base ink at shade 0, each shade a step toward prose. The dog's call has the arguments the other way round, so shade 1 is 85 % prose and shades 2–3 walk back toward amber. Measured, not eyeballed (`bun -e` against this branch):

    as shipped  : #FFB000 #cfc4a9 #d8c08b #e0bd6d   (shade 1 is the palest; 3 is nearly default)
    args swapped: #FFB000 #f7b31e #eeb73c #e6ba5a   (monotonic, like the cat's #0A0A0A #262626 #434343 #5f5f5f)

`pets.ts:239` promises "a lighter fur within the species"; as shipped the dog's shade 3 is darker than his shade 1. Fix:

    -  const coat = d.shade > 0 ? tint(ROLE.body, ROLE.prose, [0, 0.15, 0.3, 0.45][d.shade]!) : ROLE.body
    +  const coat = d.shade > 0 ? tint(ROLE.prose, ROLE.body, [0, 0.15, 0.3, 0.45][d.shade]!) : ROLE.body

Add the test that would have caught it: draw the dog with a stub scene (as the trail test at `pets.test.ts:342` does) at shades 1, 2, 3 and assert the `k` paint of the last `figure` call moves monotonically from `ROLE.body` toward `ROLE.prose` — or just that shade 1's coat is nearer `ROLE.body` than shade 3's. A `coatOf(shade)` beside `furOf` would make that a one-line test, but the swap alone is enough.

## 2. pr.md contradicts itself about the spec line (fix while you're there)

Bullet 5: "Spec step 12 slice 1 §3 got the admission line first (commit 1); this change makes it obsolete, so it stays as history rather than being dropped." The closing "Spec note" says the opposite, and is the true one: 6e50685 restored that spec from main, so nothing in this diff touches it. Drop bullet 5; the Spec note carries the admission. The PR body is what GitHub keeps.

## Checked and fine

- Store card: `main.ts:2007` passes `petsNow[slot].name` as occupant, so "Biscuit leaves by the door" names the adopted dog, not a literal Argos. The store-view test passes "Argos" by hand, which is why it reads as if hardcoded.
- Exchange parser (`wide.ts:641`): exchanges come only from the server's `duo` (`sim.ts:248`), which writes "Nina:/Argos:" prefixes; a server-written "Argos:" turn still lands on the dog and loses its prefix, and the test proves a "Biscuit:" turn does too.
- Keeping `this.line("Argos", …)` as the role key: agreed, the cat's `this.line("Nina", …)` is the precedent and the server keys voices by role. Banked as fact 4320.
- `p.dog.shade ?? 0`: `PetSetting.shade` is optional and `resolvePets` clamps it below `SHADES`, same guard as the cat's.
- `drawDog` tooltip with the name: rendered it, `"Biscuit - click to pat him"`.
- Verify's path rule: the fix restored the other workline's spec from main in a new commit, no history rewritten. The brief's spec amendment is therefore owed elsewhere or nowhere; that is tertius's call, and the admission it asked for is moot once this lands.
