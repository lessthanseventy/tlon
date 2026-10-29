Office test: navigation.test.ts no longer reuses the tmux socket it just killed.

Its play-card test ran kill-server then start() on the same `-L` socket; the new session could reach the dying server and the pane stayed empty (issue #45, seen again on #437's verify). Each start() now takes its own socket (`...-${pid}-${++starts}`) and both kills go through `killServer`, which also unlinks the socket. hall-hire and rack-card already had this fix on main; a sweep of the other office tests found only kill-server in afterAll, never mid-file.

Closes ticket #482. Checked: `bun test test/navigation.test.ts` — 5 pass, 0 fail.
