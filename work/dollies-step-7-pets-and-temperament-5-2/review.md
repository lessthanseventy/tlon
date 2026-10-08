APPROVE — dollies step 7 (pets + temperament, §5.2–5.3)

Scope of my check: read the full diff of kit/ and tui/ (temperament, pets, voices, sim wiring, pets.json load/save, pet card). I did not rerun the gate; I rely on the server's recorded `mise run check` pass (exit 0) on the branch. I did not drive the TUI.

**What holds**
- Neutral temperament reproduces `stepCat`'s old thresholds (nap .45 / desk .1 / perch .15 / play .1 / litter .05 / spot .15), and `bucketFor` rolls only when warmth > 0, so the seeded sequence and golden.json are unaffected (learnings #570/#571).
- With no pets.json the Sim keeps temperament {0,0,0}, so today's room is unchanged.
- `resolveSlot` is defensive: a bad species, a bad name, a non-object or a non-numeric axis falls back to the base, and axes are clamped.
- `savePets` merges per slot, so it writes only what changed.
- Hard-coded `"Nina"` in `line()` is the voice-pool key, not the display name, so renaming a pet via the file doesn't break voices.
- No dependency on the life track (#569).

**Non-blocking findings**
1. The card can show a different pet than the one on screen. With no pets.json the sim runs neutral, but the card's draft (`resolvePets(loadPets())`) starts from the `classic` preset (warmth -2, wits 1, energy 1). Pressing `S` on an untouched card therefore changes her behaviour, and the preview shows classic Nina before that. Follow-up: make `classic` neutral, or start the card from the live sim temperament.
2. `previewOf` ignores species: it calls `bucketFor` without the species and `pickDest` without `speciesBase`, so a rabbit or bird card previews Nina's lines and the cat's destinations.
3. `followPets`: if pets.json is deleted, `statSync` throws, the function returns false and `petsNow` keeps the old values. The pet stays on stale settings until restart, where reverting to the default would be expected.
4. The plan said 5 stacked PRs. This is one branch with 8 separable commits. Root AGENTS.md prefers stacks, so the merge gate or the operator should decide whether to split.

**Stated deviations (builder-reported)**: Enter-to-cycle instead of ←/→, `S` to save, rename deferred, 2+2 species lines per occasion, dog axes and the pet array deferred. All acceptable for this step.