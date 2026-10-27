Souls step 4b (server half): side projects on the corkboard. Closes #323.

- `Corkboard.side_due?/2`, `side_state/2`, `post_side_project/4`: a seat with a non-empty
  "The side project" soul section (`Server.Soul.read/1`) gets one note a day; its stanza counter is
  its `side project` messages on the standing thread, so it survives a restart.
- `notes/1` starts one `side_write/1` task at most once a minute per workspace: first due bench
  seat, one call through `Server.Generator` (so banter-off and `generator_daily_cap` skip it, no
  queue). The note enters the same 12-note window via `{:pinned, …}`. No new scheduler.
- New `side project` message kind: **migration** `20261026170000_message_side_project` widens the
  kind check; switchboard/needs treat it like `suggestion`/`margin` (wakes nobody, never a need).
- Plan said `Writer.write/2`; used `Generator.run/1` instead, since only it counts against the cap.

Checked: `menard run test test/server/office/corkboard_test.exs` 12/12 (red first). Full
`server:check` run via run_task on the committed head.
