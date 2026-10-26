# Review — model-drawn sprite parts (#97)

Verdict: approve

The branch implements the spec faithfully and verify's full `mise run check` is green on it.

- `Server.PartCheck`: slots head/neck/hand, three views, 12-wide rows 0..17, gear colours only (body colours `k f s p b h` refused); garbage is a shape error, never a crash. 7 tests pin it.
- `Server.GeneratedParts` + `generated_part` table: one model call a day, `JsonBlob.first_valid` → `PartCheck` → insert; rejects are logged and not retried, the call still counts against the cap; `:off`/`:capped`/`:unparsed` keep no row; `library/1` is oldest-first and per workspace. Hooked into `ToyPool.refresh_all_due/1` as `:part`, served as `parts` on `ToyPool.day/1`. The `exists?` + `on_conflict: :nothing` on `(workspace_id, day)` makes a concurrent double-run waste a call but not error — fine for a single scheduled job.
- Office: `DataPart`/`useDataParts` beside the code parts, kept out of `PARTS`/`idsIn` so `rollLook`'s modulus (and every fixed look) never moves — pinned by the snapshot test in `data-parts.test.ts`. `toysOf` narrows `parts` (only `gen:` ids, slot in head/neck/hand, rows well-formed), and an old payload with no `parts` yields `[]` — backward compatible. `wearerOf` sorts then `hash(day) % n` (order-independent, rotates over a month); `wearing` is a view over the look, never written back. The room dresses exactly one actor, only on the part's own day; `setToys(null)` (curated, main.ts:533) and a stale/non-today `dayPart` both undress everyone. The `worn` cache key re-dresses/undresses correctly across the UTC-midnight rotation. wcag guard proves every legal letter reads >=3:1 against ground/panel/raised/edge.

I checked the one deviation from the plan: door.ts uses a local `PART_SLOTS = ["head","neck","hand"]` rather than importing `SLOTS`. It's correct — `SLOTS` includes eyes/mouth/back, so the plan's "use SLOTS" would have let `eyes` through, contradicting the plan's own test. The narrower list is right; the slot triple is now duplicated across `part_check.ex @slots`, `door.ts PART_SLOTS` and (implicitly) the wcag `LEGAL`, with no cross-file guard the way the letter list has. Worth a note, not a block.

## Follow-ups (non-blocking)

- **looks.ts: orphaned doc comment.** `bossLook`'s doc `/** the operator at the big desk, with whatever they changed about themselves */` now sits directly above `wearerOf` (lines 15-16 — two adjacent `/** */` blocks), so `bossLook` (line 26) lost its doc and the comment mislabels `wearerOf`. Re-attach it to `bossLook`. Cosmetic; no behaviour change.