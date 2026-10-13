# Souls step 2: first drafts from their Borges stories

Closes ticket #61 (souls design §5–6 step 2).

- New `Server.Soul`: writes a seat's first-draft `SOUL.md` to the souls dir the office TUI polls
  (`TLON_SOULS` / `~/.config/tlon/souls`). Created with an exclusive write, so an existing soul —
  edited or not — is never touched.
- The three §5 samples (scharlach, daneri, sonny) ship verbatim, so Scharlach is the Dwight with no
  model call. Other seats are drafted by `Server.Generator` from their Borges story line, role and
  the §2 voice (`Persona.voice/2`, now public); a missing/capped/malformed model falls back to a
  handwritten template, so every seat has a soul. The draft never writes diary (empty `## Diary`).
- `tlon-cli soul <ws> [name]` backfills the bench; `hire` drafts one for a new seat.
- Not in scope: voice/room/diary consumption (steps 3–5, #62–#64); `office/kit/souls.ts` untouched.

Checked: `server/test/server/soul_test.exs` (7 tests: headings + empty Diary, never overwrites, bad
name/no seat, samples verbatim, model draft with diary stripped, malformed reply falls back,
draft_all); `mise run check` exit 0 (names gate, server 1607 tests 0 failed, adapters 0 fail).
