Office tests stop leaking tmux sockets (closes #484).

tmux does not unlink its socket on `kill-server`. Six socket names still leaked per gate run:
`terminal.test.ts` mutated `process.env.TMUX_TMPDIR` (which `Bun.spawnSync` doesn't see, and which
poisoned the rm path of files loaded after it), `cast-view` never removed its second server's socket,
`hall-hire` removed only its last name, and `reply-box`'s per-test kills left their files.

- `office/test/kill-server.ts`: `killServer(name)` reads `#{socket_path}` from tmux before the kill, kills, removes it. Its own test is red without the removal.
- `terminal`, `cast-view` (both servers), `hall-hire` (both names) and `reply-box` use it; `terminal.test.ts` no longer touches `process.env`.
- Teardown-only; the other files' existing rmSync lines are untouched.

Checked: `OFFICE_TEST_HOUR=3 bun test --timeout 20000` in office/ — 936 pass, 0 fail, and zero `tlon-office-*-<pid>` files left in /tmp/tmux-1000 for that run's pid (reply-box leaked two before its last fix). The existing pile in /tmp is not cleared.
