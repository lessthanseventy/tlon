REQUEST_CHANGES — one misplaced comment; the logic is fine.

Read the diff at 09ca687; I did not run the suites.

- Fix is right: `Server.Alerts.code_span/1` and `codeSpan` in office/tui/data.ts fence with one backtick more than the longest run, space-padded. A rule with no backtick renders as before. Each side has an exact-body test.
- BLOCKING (small): commit 09ca687 says "the allow-rule comment sits on allowed", but office/tui/data.ts:316 still sits above `codeSpan` (317 is its doc, 318 the const), so the "the refused command's allow rule is in your own settings now…" doc now describes `codeSpan`. Move line 316 to directly above `export const allowed` (line 323), after codeSpan's closing `}`. Nothing else changes.
- Nit: pr.md ends "`mise run check` below" with nothing below it; add the result or drop the words.