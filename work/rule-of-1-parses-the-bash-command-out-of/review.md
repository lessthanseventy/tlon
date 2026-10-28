No free reviewer is at the builder's grade (greybeard); tzinacan (deepseek-flash) reviewed.

APPROVE.

Read the full diff origin/main...HEAD. The allow rule moves off the summary string (`"Bash · " <> command`, rejected when it ended in `…`) onto an explicit `command` field. The adapter sets it only when `summaryOf` holds the command unredacted, uncut and single-line.

- `commandOf` (doing.ts) requires summary == `Bash · ${trimmed}`. Redaction, newline joining, truncation and cwd-relativising all give undefined, so it fails closed and no secret leaves. New doing.test.ts cases cover a redacted key, a 500-char command, multi-line, non-Bash and lowercase `bash`.
- mod.ts computes it only on a denial and omits `command` when undefined.
- The ToolDenied schema and event carry `command`. `rule_of` reads it (binary, non-empty) and otherwise returns nil. A new needs_test checks a summary-only event gives `rule: nil`. The smoke fixture seeds `command` and fixtures_test asserts `Bash(echo hi)`.
- README updated in the same change.

Verified by me: `bun test lib/doing.test.ts` passes. mod.test.ts would not load in my seat (`Cannot find module 'claude-code/testing'`, deps not installed in the worktree), and I did not run the Elixir tests. Those are unverified by me; verify and landing run the full gate.

Non-blocking: tool_denied events recorded before this lands have no `command`, so an already-open Need loses its allow-rule hint until the next denial.

No limit-gate triggers (no migration, dependency, gate/CI, spec or deleted test).