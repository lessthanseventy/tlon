# Spec — model-drawn sprite parts, one invented accessory a day (#97)

A cheap model invents one new accessory per day in the sprite row format; it is validated, kept in a
library, and worn by one actor that day. Depends on #59 (`Server.Generator`, `Server.ToyPool`) and
#67 (`office/kit/parts.ts`), both on main.

## Decisions

1. **Storage.** A db table `generated_part` (workspace_id, id, slot, front/side/back rows, day).
   `ToyPool.day/1` adds `parts:`; the existing `GET /api/office/toys/:ws` carries it; the office reads
   it through `toysOf` in `kit/door.ts`. No json file: the data travels with the server.
2. **Shape.** Fixed rows per view, no dials, one slot: head, neck or hand. Id is `gen:<day>`.
   `rollLook` does `hash(seed+slot) % (idsIn(slot).length+1)`, so adding any id to `idsIn` reshuffles
   every existing look; namespacing alone is not enough. Data parts live in a separate `DATA_PARTS`,
   and `gearOf` falls back to it for `gen:` ids. `PARTS`, `PART_IDS` and `idsIn` stay code-only.
   A test pins that `lookOf` and `rollLook` of fixed names are identical with data parts loaded.
3. **Wearing.** One actor, chosen by `hash(day) % bench`, wears the day's part through an override
   layer that is never written to looks.json. The look-card cycle also offers library parts.
   (Operator chose this, #12744.)
4. **Validator.** `Server.PartCheck.validate/1`, pure. Slot is head/neck/hand; all three views present
   and non-empty; at most 18 rows; every row exactly 12 chars; letters only `. _ y c g e w r o`
   (body colours `k f s p b h` are refused). An office wcag test asserts every legal letter reads
   >=3:1 against ROLE.ground/panel/raised/edge, so the server's list cannot drift from the palette.
5. **Daily job.** `GeneratedParts.refresh_due/1`, run from `toys:refresh`: one `Generator.run`, then
   `JsonBlob.first_valid`, then validate, then insert. A reject is logged and the call still counts.
   No retry loop.
6. **Off or capped** means no row that day and no error in the room.

## Out of scope

Retries, curation UI, eyes/mouth/back slots, dials, pruning.

## Slices (each its own commit, red test first)

1. PartCheck and its fixtures.
2. Migration, GeneratedParts and the job.
3. `ToyPool.day` parts.
4. `toysOf`, DATA_PARTS, the gearOf fallback and the look-stability test.
5. Wearer override and the look-card cycle.
6. The wcag LEGAL test.

Gate: `mise run check`. Reviewer: a coworker who did not build #67.
