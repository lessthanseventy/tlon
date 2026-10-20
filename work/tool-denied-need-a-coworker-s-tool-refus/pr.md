# tool_denied: the Need says the allow rule and the check's reason, and the office has its verbs

Closes #236 (Cause 1 of `docs/plans/2026-10-13-cohesion-off-the-happy-path.md`, the class of #242).

Most of the ticket was on main (9588f33: the `tool_denied` event, the Need derived from two refusals since the workline last moved with nobody on duty, the by-hand / back-to-build / Uqbar answers). What it lacked:

- **The report never carried the command.** `tool.check` hands the mod the call's arguments as `input`; the summary was read off the event itself, so a live report was the bare tool name. Fixed; the mod test that caught it stays. The check's `reason` rides with the report, the event stores it, and the Need's text says it.
- **"Allow" had no answer.** An allow rule only counts in the operator's own Claude Code settings (the harness law, and andrew on #1 msg 4834), which the server never writes. So the Need carries `rule`, the `Bash(<command>)` rule a refused Bash command needs, and the "Allowed it" verb posts that it is in on the thread: the answer is movement, so the item clears and the lead is woken to run it again. A truncated summary or another tool's refusal carries no rule, and no "Allowed it".
- **The office TUI had no `tool_denied` kind at all**: not in the Need type, not in `needActions`, not in the kind/tone tables, so the operator's own surface showed nothing for it. Added, with `A` allowed it, `r` by hand (reply), `B` back to build (its why), `u` hand to Uqbar, and `data.sendBack` / `data.allowed` behind them.

Checked: `menard run test --in server` on `test/server/office/needs_test.exs` (43 green, RED first on `rule` and the reason) and the `tool_denied` wire test in `test/server/mcp/server_test.exs` (RED on the missing reason first); `mix compile --warnings-as-errors`; `mise run adapters:claude-code:mod` (40 green, the new refusal test RED first on the bare summary); `mise run office:check` (typecheck caught the two per-kind tables; the tests green). Not proven against a live refusal: the README says so.

Filed on the way: #441 (`run_verb compile` runs outside `server/`), #442 (`edit_clause` "Internal error" on a valid replace), #443 (hall-hire test times out under the full suite's second pass).
