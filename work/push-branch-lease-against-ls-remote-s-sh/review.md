# Review: push_branch leases against the server's own push record (70ab219)

**Verdict: request_changes.** The design (hronir, #16487) is implemented faithfully and the real-git tests prove the three cases, but the landing's own push in `publish/5` was left on the old bare lease and never records, which makes the new refusal fire against the server's own push.

## Findings

1. **`publish/5` pushes with a bare lease and does not record** (publish.ex:24). After this change every server push except this one writes `refs/tlon/pushed/<branch>`. Sequence: seat `push_branch` P (record P) → approve → landing publishes rebased L with auto-merge armed → operator `send_back` to build (`behind/2` admits `landed`) → builder `push_branch` → ls-remote L, record P → refused "moved since the server last pushed it (P → L): a hand push, or GitHub moved it". The server moved it; a false refusal this change introduces. Fix: the publish push is the same intentional replacement a reland is, so route it through `replace_branch/3`:
   ```
   -         {:push, {_, 0}} <- {:push, run.("git", ["-C", repo, "push", "--force-with-lease", "origin", branch], opts)},
   +         {:push, :ok} <- {:push, replace_branch(repo, branch, run)},
   ...
   -      {:push, {out, _}} -> {:error, "push of #{branch} refused: #{String.slice(out, 0, 200)}"}
   +      {:push, {:error, why}} -> {:error, why}
   ```
   publish_test.exs:25 is the one remaining bare-lease assertion to update. Three push paths become two.

2. **`remote_sha/3` takes the first token of merged stdout+stderr as the sha** (publish.ex:115). With `stderr_to_stdout: true`, a stderr line (ssh "Warning: Permanently added…", a credential-helper note) lands first and becomes `expect`; the push then fails on an invalid lease. Loud, not silent, so not blocking alone, but in the change's lines: select the line whose second field is `refs/heads/<branch>` and take its first field.

## Verified

- ls-remote runs before the push and nothing fetches or prunes; a failed ls-remote is `{:error, _}`, never "absent".
- Absent on origin → lease `""`; record present and moved → refused, proven against a real bare origin and a second clone (case b); no record → the sha read once, then recorded; `replace_branch/3` relands over a hand-advanced head and records.
- `work/uqbar` push leaves `origin/work/uqbar-fix` untouched.
- `fetch_branch`/`prune_branch` gone; no stale reference in lib, docs or AGENTS.md (rg).
- Branch gate green: CHECKS row `mise run check` exit 0 at 70ab219. No bench_contrast row (no persona file touched).