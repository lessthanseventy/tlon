APPROVE — workline #649, stage `merged` → `landed`.

Read the diff (`git diff main...HEAD`, 36 files) and grepped the tree for leftover stage uses of "merged". I did not run the test suite or the gate; verify runs the full gate.

- Every server reader switched: guards, `@stages`, `@openable`, the ledger doc map, the event fragments (`->> 'to' = 'landed'`), trust and needs counts, the `Workline.stats` key (`landed:`).
- The migration drops `thread_stage_check`. The baseline's inline CHECK gets that Postgres name, so the drop should hit. It then rewrites `thread.stage` and `stage_advanced` event details, re-adds the CHECK, and `down` is the reverse. Order is right: the constraint goes before the UPDATE. The old sqlite_history migration is history and was rightly left alone.
- Office: `STAGE_RING`, the progress index and the tests are renamed. README and glossary updated, with `merged` listed as a retired word for the stage.
- Remaining "merged" hits in `server/lib` and `office` are GitHub-merge senses (`Workline.merged/2`, "unmerged work", a "merged" summary string), not the stage.
- A leftover `"merged"` string in a stage position elsewhere would fail the CHECK, but I found none in lib, office, docs or scripts.

No follow-ups.