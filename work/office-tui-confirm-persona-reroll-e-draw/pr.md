Office TUI: E → "draw a new one (reroll)" now asks before it draws.

Ticket #115. Rerolling a persona replaces its hand edits, so the reroll now goes through the same `ask2` confirm the other destructive seat actions use (let go, clear context). Declining changes nothing; confirming rerolls. "make one" on a seat with no persona is unchanged, since nothing is lost.

Checked:
- `office/test/persona-reroll.test.ts` drives the real TUI in tmux against a stub server. It was red first (E + Enter posted the reroll immediately), then green after the change: E → reroll asks, `n` posts nothing, `E` → reroll → `y` posts `/api/workspaces/1/coworkers/5/persona`.
- `mise run check` (unsandboxed): exit 0.
