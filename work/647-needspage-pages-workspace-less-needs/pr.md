# 647: NeedsPage pages workspace-less needs; a failed page is logged

Closes #647 (QA follow-ups on #643, `server/lib/server/office/needs_page.ex`).

## What changed

- **Workspace-less needs are paged.** `job_failed`, `health` and a threadless `stranded` need have no workspace, and `run/1` used to reject them, so they never reached Uqbar. They now group under the oldest workspace's study (the lowest id from `Workspaces.all/0`), and their line in the page says `(machine-wide)`. With no workspace registered at all, the pass logs a warning and pages nothing.
- **A failed page is logged, not dropped.** `page/3`'s `with` had no `else`, so a failed `Outside.study/1` or `Channel.post/1` was lost. Its normal non-matches (`[]` when nothing is fresh, `false` when the channel is quiet) now return `:ok`, and `{:error, reason}` logs a warning.
- The info log counts the machine-wide needs in each page that posts.

## How it was checked

- Tests were written first and run red:
  - a workspace-less need was not paged;
  - a study that could not open was not logged.
- After the change, `menard run test --in server` on `needs_page_test` and `drain_test` passed: 13 tests, 0 failures.
- The new `Drain` test passes on the existing code: it pins that `Drain.perform/1` leaves a `need_page` message on the study. It is coverage, not a fix.
- The full server gate runs on the committed head through `run_task` (see the server's `tlon/check` status on the head).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
