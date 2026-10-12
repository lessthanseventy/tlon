APPROVE — Uqbar step 4 marginalia (margin kind, focus-time fade, hover/enter).

Verified: read the diff (main...HEAD); `bun test` office margin/term/data 16 pass, 0 fail; server tests (message_margin, office/margin, switchboard, needs, mcp/server) 136 tests, 0 failures.

No blocking findings.
- `margin` is excluded everywhere `suggestion` is: changeset inclusion, DB check constraint (migration up/down symmetric; down deletes margin rows first), `recipients/1`, `reaches_nobody?/1`, needs mention filter. A margin note wakes nobody and is not an @operator mention.
- `margin_note` tool: trims, caps at 140, writes to the workspace root thread, errors surface via `fail`.
- Office: DEC 1004 focus enabled/disabled symmetrically in ENTER/LEAVE; fade clock counts focused seconds only; FLOOR 0.65 keeps notes legible; first-frame look-back ages stale notes across restarts; hits go first so hover/enter win; margin drawn after the clip so a pan can't lose it.