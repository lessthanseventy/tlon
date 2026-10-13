# Review — souls step 2 (work/souls-step-2-first-drafts-from-their-bor @ 3f44390)

**Verdict: approve.**

## Round 2 — the blocker is fixed

The delta since my first verdict (8da3ef6) is one commit, 3f44390, and it is exactly the requested fix: the five
`server/tmp/Server.WorklineVerifyScriptTest/…` leftovers are deleted and `server/tmp/` is added to `.gitignore`.
`git ls-files server/tmp` → 0; `git diff --stat origin/main...HEAD` touches only `.gitignore`, office/AGENTS.md,
scripts/tlon-cli.sh, server/{AGENTS.md,config,lib,test}, work/. No source file changed between rounds, so the
round-1 verification below still holds. Branch is on top of origin/main; 3f44390 carries the sonnet-5-5
Co-Authored-By and Tlon-Model trailers. The server's verify check ran again on 3f44390: `mise run check` exit 0.

## Verified in round 1 (read the whole diff; did not re-run the suite — the server's verify check is the evidence)

- Spec §6 step 2: every seat gets a soul (samples → model → template), Scharlach is the Dwight verbatim from §5.
  The three sample bodies match the design text.
- Never overwrites: `File.exists?` short-circuit plus `File.write(…, [:exclusive])`, `:eexist` → `{:ok, :exists}`. Test covers an edited file.
- Path safety: name guard `\A[a-z0-9][a-z0-9_-]*\z` before `Path.join` — no traversal; test covers `../etc/passwd`.
- Model output: Diary split off and replaced by an empty heading; a reply missing any §1 heading falls back to the template.
- `Soul.dir/0` resolves exactly as the TUI (`office/tui/main.ts:84`): config → `TLON_SOULS` → `$XDG_CONFIG_HOME/tlon/souls` → `~/.config/tlon/souls`. Test config pins it to tmp.
- `Persona.voice/2` made public with `@doc false`; the test's prompt assertion ("a detective") matches `@voices["lonnrot"]`.
- Docs updated in the same change (server/AGENTS.md, office/AGENTS.md, tlon-cli usage header).

## Non-blocking (follow-ups, filed as tickets held until merge)

1. `hire` hook crashes after a successful seat on a name the soul guard refuses (`Server.Agent` has no name
   format validation): `hire 3 Sonny builder` seats, prints "hired", then raises MatchError on `{:error, :bad_name}`.
2. `mise run check` passed with tracked junk under server/tmp — no check catches stray tracked files in a branch.
3. The CLI `soul` command and the hire hook are covered by check:names and syntax only (rpc needs a release cut):
   QA by hand per plan.md's last section once the cut lands.
