APPROVE — the earlier blocking finding is fixed in b27b37d.

- scripts/tmux-sweep.sh now refuses (exit 2) when tmux is missing. It removes a socket only when tmux's error says "no server running" or "error connecting"; any other failure keeps it.
- scripts/tmux-sweep.test.sh gained the cases I asked for: a tmux that cannot answer removes nothing, and no tmux on PATH exits 2 with nothing removed. I ran it here and all six cases are ok.
- The killServer fallback path is unchanged and was already fine.

Nit, not blocking: "error connecting" also matches "(Permission denied)". The `-O` ownership check makes that unlikely.

Not verified: I ran only tmux-sweep.test.sh, not the full gate or the office tests.