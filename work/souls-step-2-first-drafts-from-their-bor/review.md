# Review — souls step 2 (work/souls-step-2-first-drafts-from-their-bor @ cddcd37)

**Verdict: request_changes** — one blocker; the code is otherwise spec-compliant and sound.

## Blocker

**Stray test fixtures committed.** 82588e3 ("soul: flatten draft/2 (credo nesting)") adds five files under
`server/tmp/Server.WorklineVerifyScriptTest/test-seed_hex_home…/{src,dest}/` (cache.ets, hex.config,
jason-1.4.4.tar). They are ExUnit `@tag :tmp_dir` leftovers from `workline_verify_script_test.exs`; `server/tmp/`
is not in any .gitignore, so an add-all after a suite run sweeps them in. On main the path does not exist.

Fix on the branch, one commit:

```
git rm -r --cached server/tmp && echo 'server/tmp/' >> .gitignore
```

The gitignore line is the root cause fix, not a workaround: without it the next builder repeats this. Verify
with `git diff --stat origin/main...HEAD` listing only office/, scripts/, server/{lib,test,config}, work/.

## Verified (read the whole diff; did not re-run the suite — the server's verify check is the evidence: exit 0, 1607 tests, 0 failed)

- Spec §6 step 2: every seat gets a soul (samples → model → template), Scharlach is the Dwight verbatim from §5.
  The three sample bodies match the design text.
- Never overwrites: `File.exists?` short-circuit plus `File.write(…, [:exclusive])`, `:eexist` → `{:ok, :exists}`. Test covers an edited file.
- Path safety: name guard `\A[a-z0-9][a-z0-9_-]*\z` before `Path.join` — no traversal; test covers `../etc/passwd`.
- Model output: Diary split off and replaced by an empty heading; a reply missing any §1 heading falls back to the template.
- `Soul.dir/0` resolves exactly as the TUI (`office/tui/main.ts:84`): config → `TLON_SOULS` → `$XDG_CONFIG_HOME/tlon/souls` → `~/.config/tlon/souls`. Test config pins it to tmp.
- `Persona.voice/2` made public with `@doc false`; the test's prompt assertion ("a detective") matches `@voices["lonnrot"]`.
- Branch is on top of origin/main; every commit carries the right Co-Authored-By (sonnet-5-5) and Tlon-Model trailers.
- Docs updated in the same change (server/AGENTS.md, office/AGENTS.md, tlon-cli usage header).

## Non-blocking (follow-ups)

1. `hire` hook crashes after a successful seat on a name the soul guard refuses (`Server.Agent` has no name
   format validation): `hire 3 Sonny builder` seats, prints "hired", then raises MatchError on `{:error, :bad_name}`.
2. `mise run check` passed with tracked junk under server/tmp — no check catches stray tracked files in a branch.
