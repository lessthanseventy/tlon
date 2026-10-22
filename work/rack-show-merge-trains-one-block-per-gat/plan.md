# Plan — rack: merge trains, one block per gate (#615)

## Pinned contract (`health.merge_queue` items, order unchanged)
`%{thread_id, title, state: "landing"|"queued", train: %{lead, pos, size, split} | "solo" | nil, gate: %{pid|nil, started_at} | nil}`
- train map = a car of the RUNNING gate (lead pos 1; `split: true` only on a lead that fell back to landing alone after the train went red twice)
- "solo" = PR landing, reland, or a running landing carrying only itself
- nil = queued, waiting its own turn
- `gate` on the running gate's items only. `started_at` = executing job's `attempted_at`. `pid` = machine-checks holder whose line starts `#<LAST car id> landing` (Land.gate_train runs on the last car) or `PR #n landing`, else nil.
- Membership source of truth: executing job's `meta` `%{"cars"=>[ids],"split"=>bool}`; merge_queue never recomputes `companions/2`.

## Server (strictly before office)
1. `Workline.land_train/3` (workline.ex ~L515): new opt `on_cars: fn ids, split -> end`. Call `(ids, false)` with rideable ids (or `[lead]` if <2 / lead not first); in `train/2`'s `{:error,_}` fallback call `([lead.id], true)`.
   Test first (workline_landing_test.exs, "land_train/3"): `assert_received {:cars,[a,b],false}`; non-rideable b → `[a]`; stub stack red twice → `([a], true)`.
2. `Jobs.Land.perform`: pass `on_cars` writing `meta` via `update_all(set: [meta: ...])` on its own job id (merge with existing meta).
   Test first: perform with a companion → `job.meta["cars"] == [a,b]`.
3. `Room.merge_queue(checks \\ checks())` (room.ex ~L224): select job_id/meta/attempted_at; derive train/gate per contract.
   Tests first (room_test.exs): (a) 3 worklines, a executing with meta cars [a,b,c] → one train of 3, pos 1..3, gate.started_at; (b) PR alone and PR behind a train → "solo", gate nil; (c) queued non-member → nil; (d) holder line `#<c> landing … (pid 4242)` → gate.pid 4242, other line → nil; (e) split meta → lead split:true size 1, b/c nil.
   Gate: `menard run test --in server test/server/office/room_test.exs`, then `mise run server:check`.

## Office (only after 3 is green; do not overlap #616's main.ts / types.ts slice)
4. One shared `MergeItem` type in kit/types.ts (replaces inline types at types.ts L72, tui/data.ts L248). `queueItems` in kit/rack.ts → kinds check|wait|gate|car|next|restart; a check row whose pid the gate owns folds into the gate header (`🚃 train → main  gate running 3m · pid N`; `landing → main` when size 1; `split: lead lands alone` when split); cars `1 #343 …` lead flagged; `next` rows end `(PR · lands solo)` / `(own turn)`. Injectable `now` for deterministic age.
   Test first (office/test/rack.test.ts): 3-car train + PR + own-turn + split + unowned check stays a `check`. Gate: `bun test test/rack.test.ts`.
5. main.ts `queueRow` (~L1497) renders gate/car/next (car indent + `(lead)`, `▸` for next); header drops "one landing at a time". rack-card.test.ts stub becomes a 3-car train + queued PR: assert header once, `(lead)`, `(PR · lands solo)`, and `office-drive` appears exactly once (no double listing). Gate: `bun test` + `mise run office:check`.

Final: `mise run check`, advance_stage. One commit per task. Out of scope: per-car red/green, queue reordering, train size changes.
