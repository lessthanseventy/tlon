## verdict: approve

No free reviewer at the builder's grade (greybeard) — the builder is hronir on claude-fable-5-1 (Claude plan); this review is tzinacan on glm-5.2 (ollama), a tier below. Read with that in mind.

Closes #236's gaps on top of what was already on main: the mod's `tool.check` reads `e.input` (was `e`) so `tool_denied` reports carry the command summary; the check's `reason` rides the event, the Need's text and the adapter report; the Need carries a `rule` (`Bash(<command>)`) for the operator to add to their own settings; and the office TUI gets the `tool_denied` kind with A allowed it / r by hand / B back to build / u hand to Uqbar. The full gate (`mise run check`) is green on the branch.

Spec compliance: matches the opening ask — the four answers, rule for Bash only, an answer is movement. The "the server never writes the operator's Claude Code settings" constraint is held: `allowed` only posts on the thread, which is the movement that clears the item (same path as the existing by-hand verb) and wakes the lead.

Verified: `rule_of/1` degrades safely — non-Bash tools, missing reason, and truncated summaries (the `…` guard) all yield `nil` and no "Allowed it" verb, covered by the new needs test. `summaryOf(e.tool, e.input, cwd)` is the right fix (tool.check's args live on `e.input`; the unchanged `tool.call` line correctly reads `e` directly — different event shapes, not a missed fix). The alerts and TUI paths agree on `/threads/:id/messages` with the same body.

Findings, none blocking:

- `rule_of/1` recovers the command by parsing the summary string `"Bash · " <> command`. That is an implicit cross-boundary contract between the mod's `summaryOf` (produces it) and the server (parses it); if the separator or cap format changes, `rule_of` silently returns nil and the "Allowed it" verb vanishes. Degrades safely, but the contract is unwritten — filed as a follow-up.
- The "Allowed it" body wraps the rule in backticks: `Allowed: \`Bash(…)\` is in my settings`. A command containing a backtick would nest and break the markdown. Cosmetic — filed as a follow-up.
- `tool_denied` remains unproven against a live refusal (README and pr.md say so): both "Allowed it" and "by hand" clear the item only via the operator-message-moves-workline path. Already documented, not a new finding — noted so the merge gate knows.

Follow-ups filed below; neither blocks this change.