# Plan: play menu — `E` opens the toys as a numbered card (#607)

Decided (thread 1 #17185): `E` opens a card; D T F N W P C retire; every toy stays two keystrokes away (`E`, digit).
Run office checks unsandboxed: `mise run office:check`. All paths under `office/`. Three commits, in order.

## Rows (digits = the card's own numbered menu, exempt from the one-verb rule)
1 random event · 2 summon Gary · 3 doorbell · 4 fire drill · 5 treat · 6 night* · 7 weather* · 8 pet · 9 call over*
(* sandbox only — needs `world`; off the sandbox with OFFICE_TOY_KEYS=1 the card lists rows 1-5 and 8 only.)

## Task 1 — the key table (red first)
Files: `test/keys.test.ts`, `test/sandbox.test.ts`, `tui/keys.ts`, `tui/sandbox.ts`.
1. Tests first (watch them go red):
   - sandbox.test "the help line's play keys…": `expect(PLAY.map(p=>p.key).join("")).toBe("E")` (was `"DETFNWPC"`); the `case "${key}"` loop stays.
   - sandbox.test roomKey test: rename to "off the sandbox, E runs on the room with OFFICE_TOY_KEYS=1…"; loop over `["E"]` only; the `["N","W","C"]` loop becomes `["D","T","F","N","W","P","C"]` expecting `roomKey(k,false,true)` false.
   - keys.test: add `test("the seven retired play letters are unbound in sandbox-play", …)` asserting `all.filter(b=>b.scope==="sandbox-play").map(b=>b.key)` equals `["E"]`; add `test("the play card numbers its rows 1..9 in order")`: `all.filter(b=>b.scope==="card:play").map(b=>b.key)` equals `["1",…,"9"]`.
2. `tui/keys.ts`: replace the eight `play.*` rows (≈l.187-194) with one `{ id: "play.e", scope: "sandbox-play", key: "E", label: "play", verb: "play" }`, and add scope `card:play` rows: `play.1`…`play.9` → ids/labels: `play.event` "a random event", `play.gary` "summon Gary", `play.doorbell` "the doorbell", `play.drill` "a fire drill", `play.treat` "a treat (they come running)", `play.night` "night / morning", `play.weather` "the next weather", `play.pet` "pat the pet", `play.call` "call someone over", keys `"1"`…`"9"`. Add `"card:play"` to the `screens` list in keys.test only if it enumerates cards by hand (check `CARD_PARTS` use at l.17-20; no helper scopes needed). Mind the "no `key: "` literal outside keys.ts" test: sandbox.ts/main.ts must use `bind(id)` only.
3. `tui/sandbox.ts`: `ROOM_PLAY` filter → `["E"]`. Add `export const PLAY_ROWS = KEYS.filter(b => b.scope === "card:play")` (import KEYS) and `export const WORLD_ROWS = ["play.night","play.weather","play.call"]`.
Done: `mise run office:test -- test/keys.test.ts test/sandbox.test.ts` green.
Commit: "office: one play key (E); the play card's nine numbered rows in the key table (#607)".

## Task 2 — the card in main.ts (keep it small: #602 edits main.ts too)
File: `tui/main.ts` (+ nothing else).
1. Mode union (l.76): add `| { kind: "play" }`.
2. Split `toyKey`'s switch bodies into `function playDo(id: string): void` (a switch on `"play.event" | "play.doorbell" | "play.drill" | "play.treat" | "play.night" | "play.weather" | "play.pet" | "play.call"`, bodies moved verbatim from the old `case "E"/"D"/"F"/"T"/"N"/"W"/"P"/"C"`), plus `case "play.gary": status = r.event("gary") ? "Gary's at the dumpster" : r.eventsHere() ? "a scene is running, or Gary is switched off (the wackiness dial)" : "events need the wide room (kitty graphics)"`. The `N W C` bodies keep `if (!world) return`. The existing `E` body is `play.event` unchanged (random event path stays).
3. `toyKey(k)`: only `case "E": open({ kind: "play" }); return true` (keep the `!world && !roomKey(...)` guard at the top). It must not call `changed(); draw()` twice — `open` then `draw()`.
4. `detail()`: add `case "play":` returning `{ title: "PLAY", rows: [{ segs: [plain("pick a toy")] }], actions: [...PLAY_ROWS.filter(b => world || !WORLD_ROWS.includes(b.id)).map(b => ({ ...bind(b.id), run: () => { playDo(b.id); changed(); back(); draw() } })), back1] }` — `back()` first so the room is visible; copy the `pet` card's shape (l.1857-1900) for field names. Rows run through the card's own-actions path, so digits already work (`onKey` → `detail().actions.find`).
5. Update the help card hint: the two `sect(...)` titles at l.2051 keep working (PLAY now has one row); rename "the sandbox's play keys" → "the sandbox's play key".
Done: `mise run office:check` green (typecheck + tests); the sandbox.test "toyKey() handles" loop passes (`case "E"` present).
Commit: "office: E opens the play card; Gary has his direct summon (#607)".

## Task 3 — drive check + docs
Files: `test/drive/walk.steps`, `README.md` (l.65), `AGENTS.md`→`office/AGENTS.md` (l.54, l.106), `docs/plans/2026-10-08-office-as-a-toy-design.md` (l.159 only if it lists the letters).
1. `walk.steps` l.46-53 (`D E T F N W P C`): replace with `E`, `2`, `Escape`, `E`, `3`, `E`, `5`, `E`, `6`, `E`, `7`, `E`, `9`, `E`, `8`, `Escape`, `E`, `4`. The card is read from the screens the replay prints.
2. Docs: play keys are now `E` (a numbered card) — README, office/AGENTS.md l.54 (“the play keys are the shifted letters `D E T F N W P C`” → “one play key, `E`, opens a numbered card; digits pick the toy”), l.106 wording. 
3. Verify, read the output: `office/test/drive/run.sh walk` exits 0 and the screen after the first `E` lists nine numbered rows incl. "summon Gary"; after `2`, run `OFFICE_WIDE=1 OFFICE_TEXT=1 office/test/drive/run.sh walk` and see Gary's mutter ("I WILL END YOU…") in the wide room text (events need the wide room). Then `mise run office:check` green.
Commit: "office: drive walk and docs for the play card (#607)".

## Definition of done (the ticket's check)
- keys.test: sandbox-play = `["E"]`, D T F N W P C unbound; card:play rows 1-9.
- drive replay: `E` opens the card; `2` summons Gary.
- `mise run office:check` green; `docs` match (README, office/AGENTS.md).
## Not doing
No new scope convention, no config, no extra toys; `Sim.play`, `event()` and gary.test untouched (his `event("gary")` is already covered at gary.test l.111-128).
