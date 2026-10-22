# Toy: model-drawn sprite parts, one invented accessory a day (#97)

Once a day the server asks the generator to invent one accessory (a hat, a neck piece or a held thing),
draws it in the sprite row format in three views, checks it, and keeps it. The office loads the library
and has one actor wear the day's part; it is never written to looks.json and never enters the roll, so
no existing look moves.

- `Server.PartCheck`: the validator (slots head/neck/hand, three views, 12-wide rows 0..17, gear colours only).
- `Server.GeneratedParts` + `generated_part` table: `refresh_due/2` (one call a day, rejects logged and not
  retried), `library/1`; hooked into `ToyPool.refresh_all_due/1`, served as `parts` on `ToyPool.day/1`.
- Office: `DataPart`/`useDataParts` beside the code parts (out of `idsIn`, so `rollLook` is unchanged),
  `toysOf` narrows `parts`, `wearerOf`/`wearing`, the room dresses the wearer, and a wcag guard proves
  every legal letter reads at 3:1.

Closes #97.

Checked: red-first tests per task (PartCheck 7, GeneratedParts 7, ToyPool 13, data-parts, day-part,
day-part-room, door, wcag); `menard run check --in server` and the full office suite (`bun test`,
`bunx tsc --noEmit`). The doctor test's table list gained `generated_part`.
