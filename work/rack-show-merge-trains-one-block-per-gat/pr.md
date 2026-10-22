rack: merge trains, one block per gate (#615)

The rack's LANDING & CHECKS listed a landing twice (its check row and its merge-queue row), said
"one landing at a time" while a train lands up to 4 cars on one gate, and couldn't tell a car riding
the running gate from one waiting its own turn. The server never said who rode.

Server: `Workline.land_train/3` tells an `on_cars` callback which cars took the gate (and the lead
split off when a red train falls back), and `Jobs.Land` writes them into its own job's `meta`
(`record_cars/1`). `Room.merge_queue/1` reads that, never recomputing `companions/2`: each item
carries `train` (`%{lead, pos, size, split}` | `"solo"` for a PR or reland | `nil` for its own
turn) and, on the running gate's items, `gate: %{pid, started_at}` (pid from the checks holder
whose label names that gate).

Office: one `MergeItem` type; `queueItems` gives the gate one block (the check it runs folded into
its header, then its cars, lead marked), then the queued, each `(PR · lands solo)` or `(own turn)`.

Closes #615.

Checked: `menard run test` on workline_landing/send_back/jobs land (47/0) and office/room (21/0);
`bun test test/rack.test.ts test/rack-card.test.ts` at OFFICE_TEST_HOUR 3 and 15; `mise run
office:check` (its one red, the rack-card clock, fixed in b535d60); `server:check` and `check`
through run_task.
