Closes #342. An adopted dog now replaces Argos on screen, as the cat slot already does.

- `Dog` carries `name` and `shade`; `drawDog` tints his coat by shade and his tooltip uses his name (`kit/pets.ts`).
- `WideRoom.setPets` fills the dog from `pets.json`; new `dogProfile()` reports it. Argos stays the default.
- The pair's exchange is parsed by prefix, so a turn from the adopted dog's name is the dog's, said without it.
- The pet card's title shows his name; the store card's "pets.json only for now" text is gone, the dog slot says who leaves like the cat's.
- Spec step 12 slice 1 §3 got the admission line first (commit 1); this change makes it obsolete, so it stays as history rather than being dropped.

Not done, on purpose: the model's voice lines are still keyed "Argos" (as the cat's are "Nina") and the server's `/office/pets` doesn't know the dog's name, so an adopted dog speaks Argos-written lines until the server learns the dog (server change, outside this ticket).

Checked: new tests in `office/test/pets.test.ts` (default Argos, setPets, tooltip, exchange) and `store-view.test.ts` went red first; `bun test` on pets/store-view/sim/wide green; office check via run_task.

Spec note: the brief asked for an admission line in step 12 slice 1's `spec.md` §3 ("For now adoption writes `pets.json` only: the room still draws Argos for the dog slot until the wiring lands (#342)"). The gate refuses a workline touching another workline's docs, so it is not on this branch; this change makes that line obsolete anyway, since the room now draws the adopted dog. The spec's "No sim change" is still true.
