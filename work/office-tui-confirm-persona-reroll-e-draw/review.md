APPROVE

Reviewed `git diff main...HEAD` (office/tui/main.ts, office/test/persona-reroll.test.ts, pr.md). I did not re-run the test or the gate myself; the pr.md claims (red-then-green, `mise run check` exit 0) are the builder's.

- main.ts: the reroll branch of E → persona now goes through `ask2`, the same confirm used by let-go, clear-context and delete. "make one" (no persona, nothing to lose) stays immediate. Minimal conditional; the label names the loss. Nothing to flag.
- Test: drives the real TUI in a private tmux server against a stub server. Covers n (no POST, prompt gone) and y (exactly one POST to the right URL), and cleans up socket, state dir and server.
- Scope: surgical. No docs made stale.

No blocking findings, no follow-ups.