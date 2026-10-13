# Review — toy step 4: the front door and the doorbell

**Verdict: request_changes.** The sim, the drawing, the server field and the tests are sound; the spec's own check ("a cut brings pizza") does not reach the real TUI, for two reasons on the wiring side. Both are small.

## Blocking

1. **`office/tui/data.ts status()` never copies `release` off the wire.** It builds the snapshot field by field (`revs: j.revs, flags: j.flags ?? {}, life: j.life ?? {}`) and `j.release` is not among them, so in the running TUI `all.release` is always `undefined`, `arrivals()` can never return `"pizza"`, and `tellNews`'s new line is dead. door-visit's §8 test passes only because it hand-builds the `Agents`. Fix: `release: j.release,` in that object (keep `undefined` for an older server, as the type comment says), and the test is the existing pattern at `office/test/data.test.ts:19` ("status carries the server's revs … and its flags") — one more assertion that a served `release: {sha, cut_at}` comes back on the snapshot, red before, green after.

2. **A cut's restart skips `tellNews` on exactly the poll that carries the new sha.** `note_live/0` runs at application boot (`server/lib/server/application.ex:68`), so the sha changes across the service restart. `refresh()` (`tui/main.ts:289`) compares against the immediately previous snapshot and calls `tellNews` only when `all.ok && before.ok`. The TUI polls every 10 s; any poll that lands in the stop→ready gap returns `{...EMPTY, ok:false}`, so the first `ok` poll after the restart (the one with the new sha) has `before.ok === false` and tells no news, and the poll after that sees the same sha on both sides. Pizza arrives only when no poll hits the gap. Fix: diff against the last **ok** snapshot, not the last poll —
   ```ts
   let lastOk: Agents = EMPTY, lastOkNeeds: data.Need[] = []
   // in refresh(), in place of `const before = all, beforeNeeds = needs` and the tellNews line:
   if (all.ok && lastOk.ok) tellNews(lastOk, lastOkNeeds)
   if (all.ok) { lastOk = all; lastOkNeeds = needs }
   ```
   The side effect is that needs and a health warn that arrived during an outage are told once it is back instead of swallowed, which reads as the right behaviour. If you prefer a narrower fix, carry only the last ok `release` and pass `{ ...before, release: lastOkRelease }` to `arrivals`.

3. **`office/AGENTS.md` does not mention the door.** The `rooms/` paragraph names every fixture of the wide room with its file (the bathroom down to `kit/bathroom.ts` and the print fade); the front door, its visitors, `kit/door.ts` and the snapshot diff that rings it (`arrivals`) are absent. Repo rule: docs that a change makes stale move in the same change — and #6404 said task 4 would add this paragraph. One or two sentences.

## Checked and fine

- Spec coverage: carrier (ties to the mailbox count via `mailbox(needs).total`), pizza on a sha change, cookies, tourist with the shelf-spine nudge (`wiggle(tick, nudge)`), seasonal trick/carol. The visitor is sim state, not an actor; no thread, ticket or turn is touched.
- Determinism: `stepDoor` draws only when it schedules a ring, first at tick 6000; answerer is nearest-non-thinking, ties by name. Goal chain puts the door after fire and leaving and before the queue, so a fire drill still wins and a blocked caller can't strand someone. The give-up condition (idle with no path left after `WAIT`) is correct given `moving` flickers between waypoints.
- `live_release/0` matches `note_live/0`'s own "newest said" query; nothing else in `server/lib` posts a notice with a `live` payload key (`mcp/tools/release.ex` is a tool result, not a message). The `? \? 'live'` fragment is the one `live_since/1` already uses.
- `Office.status` picks it up; both server tests say the right things (nil before, newest wins).
- Golden re-hash is its own commit; the draw test pins door shut/ringing/open and three distinct silhouettes.

## Nits (take or leave on the same pass, no tickets)

- `kit/floor.ts` door comment says it is "clear of the muster grid (x >= w-8 downward in steps of 9)": the second muster column is `w-17`, 1 px from the door at `w-18`. Harmless (fire outranks the door in the goal chain) but the comment's own numbers contradict it.
- door-visit test "nobody comes if nobody can: no door in the rail room, …" never builds a rail room.
- The "draws no random number" test ends in `expect(draws).toBeGreaterThanOrEqual(0)`, which cannot fail; the plan already says the golden is the real proof.