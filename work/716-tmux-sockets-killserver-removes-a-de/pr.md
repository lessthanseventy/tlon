Stop the tmux socket leak in office tests, and sweep the pile already left behind.

`killServer` read the socket path from tmux before killing. A server whose only pane had exited (started.test's `true` case) answers nothing, so the path was empty and the dead socket file stayed in `/tmp/tmux-<uid>`. It now falls back to `${TMUX_TMPDIR:-/tmp}/tmux-<uid>/<name>`, where tmux leaves the file. A new `office:tmux-sweep` (`scripts/tmux-sweep.sh`) removes the dead sockets already there: each socket the uid owns is asked `display` with a client command, which never starts a server, so a live one stays and a dead one goes. Its self-test runs under a private `TMUX_TMPDIR` and is in `check:names`.

Closes ticket #716. Checked:
- `bun test test/kill-server.test.ts` — 3 pass, 0 fail (the new test was red on the leftover socket before the fix).
- `bun test` in office — 969 tests, 0 fail.
- `scripts/tmux-sweep.test.sh` — 4 ok.
- `mise run check:names` — exit 0; `mise run manual:gen` regenerated `docs/manual/tasks.md`.

The sweep is not run here: the 464 entries in the real `/tmp/tmux-1000` include the operator's `tlon-office` and the seats' workspace sockets, so the first real run is andrew's call.
