office:monitor keys DOWN, so a restart while the service is down stays quiet.

`scripts/office-monitor.sh` printed `DOWN` unkeyed, and `down` starts at 0 in every process. Under `--until-new`, each relaunch while the service was down said DOWN and exited at once, a tight relaunch loop until UP. DOWN now goes through `say "down:$url"`, so a restart stays quiet and keeps watching. UP forgets that key (and its line in the seen file), so the next outage is said again.

Closes #635.

Checked: test-first. `scripts/office-monitor.test.sh` is new: it ran red first (the restart while down printed DOWN and exited 0). After the fix, `scripts/office-monitor.test.sh` exits 0 with all four cases ok: first DOWN is said and exits; restart while still down stays quiet and keeps watching; UP is said, exits, and drops the DOWN key; the next outage is said again. The test is not yet wired into the `server:check` list in `tasks/server.toml`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
