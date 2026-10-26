# Review: keep-up-a-project-with-no-github-repo-ra (b6cd98e)

**Verdict: approve.** All three items from the send-back are in, the two behavioural ones proven red first, and the scope regression the last review missed is gone.

## 1. Drift runs for every repo again (the send-back's first item) — fixed

`keep_up/2` calls `drifted(repo, Server.Workline.Publish.follow_main(repo, run))` at `keep_up.ex:40`, above the `if github_remote?`, so a GitLab or bare-path origin has its main followed and its drift surfaced as on main. For a repo with no origin `follow_main` returns `{:error, _}`/`:skipped` (`workline/publish.ex:195-203`) and `drifted/2`'s catch-all (`keep_up.ex:194`) ignores it, so the ticket's goal — no `gh` read, no item — still holds.

New test `keep_up_test.exs:259-272` stubs a GitLab origin with local main ahead and asserts the drift note appears. On 9e7edaa no drift call ran for such a repo, so it is red first.

## 2. `github_remote?` matches the GitHub remote forms — fixed

`keep_up.ex:62`: `~r{^(?:(?:https?|git|ssh)://)?(?:[^@/]+@)?(?:ssh\.)?github\.com[/:]}`.

Checked by hand: `git@github.com:`, `https://github.com/`, `ssh://git@github.com/`, `https://user:token@github.com/`, `ssh://git@ssh.github.com:443/`, `git://github.com/` all match; `git@gitlab.com:`, `https://gitlab.com/`, `/srv/git/app.git`, `https://notgithub.com/x` and `https://github.com@evil.com/x` do not — the host itself must be github.com, so a userinfo naming github.com cannot smuggle another host through.

Test `keep_up_test.exs:274-287` iterates the three new forms and asserts a `gh pr list` actually runs; all three are red on the old regex.

## 3. The end-to-end pass test — added

`keep_up_test.exs:200-208` runs `KeepUp.keep_up/2` on a GitHub origin with a red PR and asserts the PR is closed and the workline is back at build. It passed on first run — the behaviour already worked, only untested — which is stated plainly, and is the right thing for a pinning test.

## Follow-ups

None. The three the earlier review filed are disposed: (1) credentialed / `git://` remotes is fixed above; (2) the stale note after an origin change and (3) `red_checks/2` clearing on half a pass were dropped on the thread (03:09) with reasons, and (3)'s trap is banked as a constraint since the function is `@doc false` with no caller outside its own tests.

## Checked and fine

- The moduledoc at `keep_up.ex:15-16` and the `github_remote?` comment at `57-59` say what the code does: skipped for the `gh` reads, main still followed, said once.
- One keyed note per repo, cleared only when both reads of a pass succeed; no reference to the old per-read key survives anywhere (`grep keep_up:`).
- `read/3` noting per repo (rather than only on a changed reason) is what collapses the two-items-per-pass case, and the existing test pins it.
- Ran `menard run test --in server test/server/jobs/keep_up_test.exs` here: 22 tests, 0 failed. The verify stage's `mise run check` on b6cd98e is green (2076 tests, 0 failed).
- `pr.md` matches the change.
