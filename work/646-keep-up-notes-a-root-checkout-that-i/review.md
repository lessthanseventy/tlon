# Review — work/646-keep-up-notes-a-root-checkout-that-i @ 6efcd19

**Verdict: approve.** The one finding from the round at 5c04d66 is fixed as prescribed; nothing new in the change's lines.

Read: my review.md at 5c04d66, then `git diff 5c04d66..6efcd19 -- . ':!work/646-…'` (two files, +27/−5), and the branch's whole diff past 34f84f8 (keep_up.ex, publish.ex, their two test files — the same four as last round). CHECKS: verify's `mise run check` exit 0 at 22:20:47 on 6efcd19. No `bench_contrast` row (no persona edit), so none owed. I ran `test/server/workline_publish_test.exs` myself: 42 tests, 0 failures. The branch is one commit behind origin/main (e16575e, the spawn notice dedupe); it is not part of this change and the landing's rebase carries it.

## 1. FIXED — exit 128 from `symbolic-ref` no longer reads a missing or non-git path as "detached HEAD"

`publish.ex`, `follow_main/2`, as the witness now states it:

```elixir
      # exit 128 is a HEAD that is no branch — or no repo at all: only a HEAD that resolves is detached
      {_, 128} ->
        case git.(["rev-parse", "--short", "HEAD"]) do
          {sha, 0} -> {:off_main, "detached at " <> String.trim(sha)}
          {out, _} -> {:error, String.slice(out, 0, 200)}
        end
```

The guard is on `rev-parse`'s exit, not `symbolic-ref`'s text, so a true detached HEAD (whose `rev-parse` exits 0) still becomes `{:off_main, "detached at <sha>"}` and the existing test for it holds. The new test "a path that is no repo is an error, not a detached HEAD" stubs both commands with exit 128 and asserts `{:error, "fatal: cannot change to" <> _}`; emma reports it red first (`{:off_main, "detached at fatal: …"}`), then green, which matches what the old clause did.

## Checked and holding (unchanged from last round)

- `follow_main/2` has one caller (`KeepUp.keep_up/2` → `drifted/2`); `{:error, _}` still falls to the catch-all there, so a moved or deleted checkout is silent in keep_up rather than a false "switch it back to main" note. That is the pre-change behaviour for that path, restored.
- `{:off_main, repo}` set on a branch or detached HEAD, cleared on `:forwarded` and on `{:diverged, _}`; both keep_up tests cover it.
- Docstrings and moduledoc already carry the new shape; no AGENTS.md names this path.