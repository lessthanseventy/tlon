APPROVE. Right then: small, scoped, and every line traces to #328.

Read (not run): the diff origin/main...HEAD (3 commits).

- `server:setup` sets `insteadOf` (fetch → HTTPS) and `pushInsteadOf` (push stays SSH). With both set, git's push-rewrite wins for pushes, so SSH push is preserved. Sound.
- `Server.Doctor.git_fetch_urls/1` matches `git config --get-regexp` output. That output lowercases section and variable but keeps the subsection's case, so the `url.https://github.com/.insteadof` keys in the table match. It reads `--local`, which in a worktree is the shared config, as intended. A non-repo root or a git error prints text that matches nothing, so it reports `missing` rather than crashing. That is right for a doctor.
- The tests cover both lines missing, one line missing, and ok. They use a temp repo, so they never touch the live config.
- AGENTS.md ("three" → "four" symptoms), the tasks.md regeneration and the `server.doctor` output line are all in step with the code.

Nits, not blocking:
- `System.cmd("git", …)` raises ErlangError if git is absent from PATH. Not reachable on a box that runs the gate.
- I did not run the suite or `server:setup`. The gate and landing do that.