REQUEST_CHANGES (lonnrot, at 3866e5f; prior round by tzinacan at 90e63a8 approved, QA sent it back for the dog)

Read: the diff since 90e63a8 (kit/store.ts SHELF = every species; tui/store.ts draws DOG; store/store-view tests; AGENTS.md) and the whole branch's kit/store.ts, tui/store.ts, tui/main.ts store wiring, kit/pets.ts, tui/pets.ts, kit/draw.ts, kit/sim.ts. Ran `bun test test/store.test.ts test/store-view.test.ts test/pets.test.ts test/petsfile.test.ts`: 57 pass, 0 fail. The gate run (mise run check, 22:26, exit 0) is the authority for the rest.

## Blocking

1. **A dog adopt says Argos leaves by the door, and he doesn't.** Nothing in the room reads the dog slot: `DOG_NAME` is hardcoded in his tooltip (kit/pets.ts:208), the pet card is titled "ARGOS" (tui/main.ts:1553), the finder says "Argos, the dog", and `Sim.setPets` applies the cat slot only. So on a dog candidate the slot row reads "the dog slot — Argos leaves by the door", the confirm reads "Argos leaves by the door. adopt Rex?", `y` writes pets.json, and Argos stays on screen as Argos. That is the path QA drives and the operator will see. The spec keeps this slice out of rooms/wide.ts, so the fix in-slice is honest text: when the slot is the dog's, the row says "the dog slot — pets.json only for now, the room still draws Argos" and the confirm says "adopt Rex into the dog slot? (the room still draws Argos)". Add the assertion to the store-view dog test that the row does not say "leaves by the door". (The wider choice, wire Argos / unshelve the dog / ship pets.json-only, is the tech lead's; flagged to hronir on the thread.)

2. **`storeTaken` is still dog-only** (tui/main.ts:183) now that the shelf holds both families. A dog candidate's roll avoids the dog's own name (he leaves anyway) and not the cat's; spec §5 says minus the other slot's pet. NAMES has no Nina/Argos, so it only bites once a store-named pet sits in the other slot, and then two pets share a name. Make the excluded name the other slot's, from `slotOf(store.species)`, with a store test that a dog roll never returns the cat's name.

Both are a few lines; patches are on the thread.

## Checked and fine
- `adopt(dog, "dog")` writes the dog slot and refuses the cat slot; `loadStore` keeps "dog" and drops an unknown species.
- DOG's letters (k e i n p t c) all have a paint entry, so the card draws him; `furOf` tints k/t.
- `drawCat` indexes `frames[i % frames.length]`, so a sit-only species is safe at any frame index.
- `previewOf` passes the species, so the card's line is the species' own (hamster test covers it).
- The sandbox pets path and `TLON_PETS` precedence are tested; the sandbox adopt never reaches the real file.
- The prior review's non-blocking note (storeTaken excludes the replaced occupant) is by design: it leaves.

## Non-blocking (follow-ups filed with this review)
- The dog has no `SPECIES_VOICE` pack: his "says" line is Nina's.
- `storeRows` special-cases `DOG` instead of `SPECIES_ART` holding it; spec §4 says a species is data, never a branch in drawing code.
- Wire the dog slot into the wide room (name on the tooltip, card and finder; shade on drawDog), so a dog adopt is real on screen. Touches #255's files.
- Spec §3's confirm example ("⏎ / esc") differs from the office's y/n `ask2`; the office convention stands, the spec text should say y/n.