keep_up says when it skips a repo (#627)

Closes #627.

Two halves of the ticket, one commit each:

- A `git remote get-url origin` failure other than exit 2 ("No such remote") now goes through
  `fault/1`, so the job fails and the operator sees it. Before, it fell through to the non-GitHub
  branch and the repo was skipped silently.
- A repo whose origin is missing or not on GitHub gets one keyed Rollout note,
  `keep_up:remote:<repo>`, cleared once the origin is on GitHub. The matching is on the URL alone,
  never a `gh` read, so a `gh` that is down cannot make every repo look non-GitHub. The old
  persistent_term log-once is gone.

How it was checked:

- `keep_up_test.exs`: 26 tests, all green. New tests went red first: a non-"no such remote"
  git failure listed no fault; a non-GitHub remote set no note.
- Full `menard run check --in server`: 2487 tests, 0 failures, exit 0 (run alone on the worktree's
  own test database).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
