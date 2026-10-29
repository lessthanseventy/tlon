APPROVE.

Read: git diff origin/main...HEAD (office/test only). Ran `bun test test/kill-server.test.ts test/terminal.test.ts` in office/: 7 pass, 0 fail. Did not run the full office gate (verify does).

What it does: one `killServer(name)` helper reads `#{socket_path}` from tmux, kills, then unlinks that path. This replaces four hand-built `${TMUX_TMPDIR ?? "/tmp"}/tmux-uid/...` paths. The helper has its own test, including a poisoned TMUX_TMPDIR and the no-server no-op. Sound.

Non-blocking:
- hall-hire.test.ts: `socket =\`tlon-office-hall-taken-...\`` lost the space after `=`. Style only.
- terminal.test.ts: the private `TMUX_TMPDIR` mkdtemp dir is gone, and with it its comment ("a sandboxed /tmp is read-only"). The test now uses the default tmux socket dir. It passes here, but on a box where that dir is not writable it would fail where it used to pass. If the removal is deliberate (killServer now cleans the socket), say so in pr.md. If not, restore it.
