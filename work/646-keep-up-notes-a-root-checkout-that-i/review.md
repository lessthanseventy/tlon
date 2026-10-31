# Review — work/646-keep-up-notes-a-root-checkout-that-i @ a15f716

**Verdict: request_changes.** One confirmed correctness finding in the change's own lines; everything else holds.

Read: the two commits past 34f84f8 (7640836, a15f716), `server/lib/server/jobs/keep_up.ex`, `server/lib/server/workline/publish.ex`, both test files, `work/646-…/pr.md`, tertius's intake (message #25154). CHECKS: `mise run check` exit 0 on verify. No `bench_contrast` row (no persona edit), so none owed. The branch is one commit behind origin/main (the spawn.ex read-dirs dedupe); a raw `git diff origin/main..HEAD` shows that commit reversed — it is not part of this change, and the landing's rebase carries it.

## 1. CONFIRMED — exit 128 from `symbolic-ref` is read as "detached HEAD", but a missing or non-git path exits 128 too

`publish.ex`, `follow_main/2`:

```elixir
      # exit 128 is a HEAD that is no branch
      {_, 128} -> {:off_main, "detached at " <> (git.(["rev-parse", "--short", "HEAD"]) |> elem(0) |> String.trim())}
```

Measured, not guessed — `git -C <dir> symbolic-ref --short HEAD` on: a detached HEAD → `fatal: ref HEAD is not a symbolic ref`, 128; a missing directory → `fatal: cannot change to '/x': No such file or directory`, 128; an empty non-repo directory → `fatal: not a git repository …`, 128. In the latter two, `rev-parse --short HEAD` also exits 128 with the fatal text on stdout, and the clause takes `elem(0)` regardless of exit.

`KeepUp.repos/0` passes `Server.Projects.primary_repo_path/1` through as given; nothing checks the path exists. So a project whose checkout was moved or deleted now sets the operator a keyed note reading "`<repo>`: the root checkout is on detached at fatal: cannot change to '…': No such file or directory, not main, so it is not following origin/main — switch it back to main". Before this diff that path fell to `{:error, _}`, which `drifted(_repo, _other)` swallows, so this is a regression in the exact surface #646 is about (keep_up telling the operator the truth about root).

A detached HEAD is one whose HEAD still resolves. Fix, in the clause the change owns:

```elixir
      # exit 128 is a HEAD that is no branch — or no repo at all: only a HEAD that resolves is detached
      {_, 128} ->
        case git.(["rev-parse", "--short", "HEAD"]) do
          {sha, 0} -> {:off_main, "detached at " <> String.trim(sha)}
          {out, _} -> {:error, String.slice(out, 0, 200)}
        end
```

And one test beside "a detached HEAD is off main too" in `workline_publish_test.exs`:

```elixir
    test "a path that is no repo is an error, not a detached HEAD" do
      gone = {"fatal: cannot change to '/repo': No such file or directory\n", 128}

      run =
        runner([
          {&match?(["git", "-C", _, "symbolic-ref" | _], &1), gone},
          {&match?(["git", "-C", _, "rev-parse", "--short", "HEAD"], &1), gone}
        ])

      assert {:error, "fatal: cannot change to" <> _} = Publish.follow_main("/repo", run)
    end
```

Red before (today it answers `{:off_main, "detached at fatal: cannot change to …"}`), green after.

## Checked and holding

- `follow_main/2` has exactly one caller (`KeepUp.keep_up/2` → `drifted/2`); the new `{:off_main, _}` shape is matched there. The intake's "check every caller" is satisfied.
- `{:off_main, repo}` is cleared on `:forwarded` and on `{:diverged, _}` (the drift note takes over), set and updated in place otherwise; the two new keep_up tests cover both. Leaving `{:drift, repo}` alone while off main is right: being on a branch says nothing about whether main has local commits.
- The three keep_up fixtures that said `feature` to dodge following now say `main`. With the catch-all `{"", 0}` runner they walk `fetch → merge-base (0) → merge --ff-only → :forwarded`, and the assertions they carry are about gh failures, which they still test.
- Moduledoc in keep_up and the `follow_main` docstring both updated with the new shape; no AGENTS.md names `:skipped` for this path.
- Intake asked for key `keep_up:branch:<repo>`; the builder used `{:off_main, repo}`, matching the existing `{:drift, repo}` tuple style. Not a finding.
