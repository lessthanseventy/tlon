# tool_denied carries the Bash command as a field; rule_of/1 stops parsing the summary

Closes #492 (follow-up from #294).

`Server.Office.Needs.rule_of/1` built the "Allowed it" rule by matching `"Bash · " <> command` in the mod's summary string: an unwritten contract that a separator change in the adapter would silently break. Now the contract is a structured field:

- `tool_denied` takes an optional `command`; the event stores it.
- The mod's `commandOf` (adapters/claude-code/lib/doing.ts) sends a Bash call's whole command only when `summaryOf` holds it as is (nothing redacted, joined, cut or made relative), so a secret never leaves and a cut command never makes a wrong rule.
- `rule_of/1` reads `detail["command"]`; an event with only a summary offers no rule.

Checked: `menard run test --in server` on needs_test.exs + mcp/server_test.exs (189 green; RED first on the new field and on a summary-only event); `bun test lib` (90) and `bun run typecheck` in adapters/claude-code; `mise run adapters:claude-code:mod` (47 green, the refusal test RED first on the missing `command`).
