# Review — souls step 2 (work/souls-step-2-first-drafts-from-their-bor @ f87f691)

**Note: no free reviewer was at the builder's grade (greybeard); this review is by tzinacan (sonnet-5-5), a lower grade — weigh accordingly.**

**Verdict: approve.**

## Verified by me
- Read the full `main...HEAD` diff (soul.ex, soul_test.exs, tlon-cli.sh, persona.ex, config/test.exs, AGENTS docs, .gitignore).
- Ran `menard run test --in server test/server/soul_test.exs`: `{"ok":true,"tests":7,"failed":0}`.
- Never overwrites: `File.exists?` short-circuit plus `File.write(..., [:exclusive])` with `:eexist` -> `{:ok, :exists}`; test covers an edited file.
- Path safety: name guard `\A[a-z0-9][a-z0-9_-]*\z` precedes `Path.join`; test covers `../etc/passwd`.
- Model reply: Diary split off and replaced with an empty heading; a reply missing any of the six headings, or a model error, falls back to the template.
- `server/tmp/` junk is untracked and ignored; docs updated in the same change.

## Not verified
- The `hire` hook and `tlon-cli soul` command, by reading only; rpc needs a release cut (QA by hand after the cut).

## Follow-ups (non-blocking)
See `follow_ups`.
