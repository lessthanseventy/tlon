# adapters/fmt — the agent's format-on-save

One job: keep `mix format --check-formatted` from ever failing on an agent-written
file. A `tool_result` middleware hook watches the `edit`/`write` tools; when the
touched file is an `.ex`/`.exs` inside a mix project, it runs `mix format <file>`
in that project's root the instant the agent writes it. The file on disk is always
styler-compliant, so the format gate is a formality, not a blocker.

## Law

- **Elixir only.** `mix format --check-formatted` is the only formatter in any gate
  (`funes:check`, `aleph:check`). TypeScript has no formatter in its gate
  (`adapters:consult:check` is typecheck + tests), so `.ts` is left alone here.
  Diagnostics/typecheck for `.ts` is the LSP stack's job, not this extension's.
- **No typecheck on save.** A project-wide `mix compile --warnings-as-errors` or
  `tsc --noEmit` after every edit is too heavy. The spirit is "don't leave broken
  *unformatted* code lying around" — formatting is cheap and immediate; verifying
  it compiles/typechecks is on-demand (the LSP stack, or the gate at commit).
- **Best-effort and invisible.** A `mix format` failure never fails the edit — the
  `tool_result` is returned unchanged. `mix format` is a no-op on already-compliant
  code.
- **The race.** If `mix format` reformats a file the model just wrote, the model's
  *next* edit's `oldText` (from its pre-format memory) can mismatch the formatted
  disk. mix format only changes non-compliant code; the natural recovery is a
  re-read, which the agent does before editing files it didn't just write. Net-
  positive: it kills the recurring format-check failure for a rare, self-recovering
  retry. If the race bites too often, the fallback is a pre-commit hook (format
  once at commit, after all edits) — but try this first.
- **No state, no npm deps.** Hand-declared `ExtensionAPI` slice (`src/pi.ts`),
  type-only, erased at runtime — the adapters idiom.

## Verify

`mise run adapters:fmt:check` (typecheck + tests). The extension loads live from the
repo path (no build step), so `home:switch` is what installs it. The `formatTarget`
decision is unit-tested without spawning mix; `findMixRoot` is exercised against
the real repo layout.