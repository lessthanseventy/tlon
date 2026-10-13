One seat, one session: a resumed twin beside a respawned session is fenced and told to stop.

Wakes and the MCP token are keyed by (thread, agent), so after a restart two sessions for one handle
both took wakes and wrote (#262's twin reviews, #257's twin commits). `register` already supersedes
the earlier session row; nothing told the earlier *process*.

- `take_wakes` takes the `session_id` `register` returned. If it is no longer the live session, the
  wakes stay queued for the live one and the caller is answered `{superseded, by, text}`.
- The claude-code mod sends its session id, and on `superseded` submits the text once and stops
  polling/registering (it re-arms on its next session start).

Fixes ticket #313 (issue #33; workline #262 / ticket #286).

Checked: new `server_test.exs` test red (twin took the wake) then green, 73/73; new mod test red then
`mise run adapters:claude-code:mod` 30/30. Not covered: a twin's non-wake tool calls (post_message)
are still unfenced at the server; they stop only because the twin is told to.
