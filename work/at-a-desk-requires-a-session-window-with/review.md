# review — at-a-desk-requires-a-session-window-with (#500)

verdict: approve

"At a desk" now requires a registered session, matching the operator's direction (#10121) and the tech lead's read (#10163): a window with no session is `:cold` in `Coworker.status` and not `"desk"` in `Office.status`'s seat. Functionally correct, minimal, tested red→green, verify green (1927 tests, 0 failed), docs in sync.

## what changed
- `server/lib/server/coworker.ex`: removed the `session: false, windowed: true → :idle` clause; a window with no session now falls through to `:cold`. Doc updated (`:idle` is now "a window it can be woken in (warm)"; `:cold` gains "or a window with no session behind it").
- `server/lib/server/office.ex`: `desk?` is now `(live and sessioned) or lead in on_it or warm`, where `sessioned = MapSet.new(roster, &{&1.thread_id, &1.agent})`. A thread whose window is up but whose lead has no registered session drops from `"desk"` to `"idle"`. Doc updated.
- tests: `coworker_status_test` asserts `:cold` for window-without-session (was `:idle`); `office_test` adds a `bare` thread (window, no session) and asserts `seat == "idle"` (was `"desk"`).

## verified
- `sessioned` is exactly the registered-session predicate: `Server.Staff.roster()` queries `Session` with `ended_at` is nil, and every roster row hardcodes `session: true` in the status call, so `sessioned` is the set of (thread, agent) with an active registered session. `live and sessioned` correctly reads "window up AND session registered".
- The thinking (`lead in on_it`) and warm clauses still stand alone, so a mid-turn or warm lead stays at a desk without a live window — matching the spec ("or thinking or warm"). Warm already implies a session (warm rows come from roster), so no regression there.
- The office TUI keys seated-at-desk off `seat === "desk"`, so it stops drawing a figure for a window-without-session thread — the visible fix the operator asked for.
- No stale doc/glossary: the only prose describing the old "window up before its session registers → :idle" was the coworker.ex doc comment, which is updated; office/AGENTS.md and crew.ts describe the seat enum's meaning, not the session condition, so they stay accurate.
- Commit attribution is correct (`Co-Authored-By: claude-sonnet-5-5`, `Tlon-Model: anthropic/claude-sonnet-5-5`) — ireneo is on Claude sonnet.

## non-blocking
- The plan (#10163) asked for the "window up, no session" predicate as one named function so the pane_stuck Need (#237) reuses it and the board and Need can't disagree. The builder deferred it — defensible, since the predicate has no natural second caller until #237 lands (it would be speculative now, and adding an explicit `:cold` clause in `Coworker.status` would cut against "not a new status"). Filed as a follow-up for #237 to extract.