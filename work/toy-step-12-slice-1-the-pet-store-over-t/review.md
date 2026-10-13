APPROVE (lonnrot, at 2859017; my prior round at 3866e5f requested two changes, both fixed)

Read: the diff since 33c615a (tui/store.ts `storeNamesTaken` + the dog slot row; tui/main.ts `storeTaken` and the dog confirm; store-view tests) against kit/store.ts (roll/candidateOf/carry/shelve) and the store wiring in main.ts. Ran in office/: `bun test test/store.test.ts test/store-view.test.ts test/pets.test.ts test/petsfile.test.ts` → 59 pass, 0 fail; `bunx tsc --noEmit -p .` → exit 0. The gate run on the branch (verify, 22:42) is the authority for the rest.

## Prior findings, checked fixed
1. **The dog's adopt no longer claims Argos leaves.** The slot row reads "the dog slot — pets.json only for now, the room still draws Argos"; the confirm reads "adopt Rex into the dog slot? (the room still draws Argos)". Test asserts the dog row never says "leaves by the door" and does say "the room still draws Argos". Cat-family rows and confirm are unchanged.
2. **`storeTaken` excludes the other slot's pet.** `storeNamesTaken(bench, pets, species)` picks the slot opposite `slotOf(species)` (unknown species falls to cat → excludes the dog, same as before); main.ts calls it with `store.species`. Test covers dog → Nina excluded, hamster → Argos excluded. The replaced occupant is deliberately not excluded (it leaves).

## Checked and fine
- Every `storeTaken()` call site (shelve, pass, back, adopt, the card) goes through the one helper; no second list left behind.
- `storePass(store, [...taken, c.name])` after an adopt still carries the just-adopted name as taken, so the next card can't repeat it.

## Non-blocking (follow-ups filed with this review)
- A locked name carried across a cross-family shelve is checked against the old species' taken list: `shelve` calls `carry(s, taken)` with taken computed for the current species, so a name lock equal to the other slot's pet can survive onto the new species' card. Only bites with a lock + a store-named pet in the other slot; `rename` likewise never checks taken.
- The dog has no `SPECIES_VOICE` pack; his "says" line is Nina's.
- `storeRows` special-cases `DOG` instead of `SPECIES_ART` holding it (spec §4: a species is data, never a branch in drawing code).
- Wire the dog slot into the wide room (tooltip, card title, finder; shade on drawDog), so a dog adopt is real on screen and the "pets.json only for now" text can go. Touches #255's files.
- Spec §3's confirm example ("⏎ / esc") differs from the office's y/n `ask2`; the office convention stands, the spec text should say y/n.

Design note for the operator: the dog is shelved and adopts into pets.json only; the room keeps drawing Argos until the wide-room follow-up lands. The slice says so on screen rather than pretending.