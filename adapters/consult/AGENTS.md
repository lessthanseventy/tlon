# adapters/consult — delegate to a different model

Two slash commands, one spawn path. The v1 `/consult` pattern, repo-native.

- **`/consult [model] <prompt>`** — RICH. The delegate receives the recent session
  transcript (text turns, last ~40, capped at ~20k chars) as context, then the prompt.
  "Review the current session and any relevant info." Default model `minimax-m3`.
- **`/fresh [model] <prompt>`** — THIN. No session context — just the prompt. A clean
  one-shot, the `pi -p "…"` shape. Default model `minimax-m3`. The vision case lives here:
  `/fresh read /tmp/pi-clipboard-….png and describe it` lets a text-only main model hand a
  screenshot to the multimodal one without dragging session context into a "what's on
  screen" question.

Both spawn a transient `pi -p --no-session --provider ollama-cloud --model <id>` — a
one-shot that writes no session file and registers no funes thread (the adapters adapter
stays quiet: the spawn passes no `TLON_*` env). The delegate's stdout is injected back via
`pi.sendUserMessage`, so it lands in the transcript and triggers the main agent to react.

## Law

- **No npm dependencies, no state.** Hand-declared `ExtensionAPI` slice in `src/pi.ts`,
  type-only, erased at runtime — same idiom as `../pi/src/pi.ts`. A change in what we
  rely on is a change to that file.
- **The thin/thick axis is context, not tools.** Both commands give the delegate
  `read,grep,bash` so it can review relevant files. `/fresh` is "no session baggage," not
  "no tools."
- **Model arg is the first token if it's a known cloud id**, else the default
  (`minimax-m3`) and the whole string is the prompt. The known list is the flake.nix ring.
- **Refuse while the main agent is running** (`ctx.isIdle()` guard) — `sendUserMessage`
  triggers a turn, and stacking a delegate onto a running turn would interleave.
- **No recursion guard needed beyond the transcript skip.** The spawned pi loads this
  extension too, but `-p` one-shots don't fire slash commands; `serializeSession` also
  drops prior `[/consult]`/`[/fresh]` injections so the transcript doesn't nest.

## Deferred (v2)

- **`see_image` tool** — a model-INVOKED tool (not a human-typed command) so a text-only
  main model auto-delegates when it gets an image path it can't read, without the operator
  typing `/fresh`. Needs a typebox param schema (a peer dep); the slash commands cover
  vision manually until then.
- **`/screenshot`** — capture via grim/slurp (worklist item #2) then delegate to
  `minimax-m3` in one motion. Sits on top of `/fresh`.

## Verify

`mise run check` (the shared gate) once wired; the extension loads live from the repo path
(no build step — pi loads `./src/extension.ts` directly), so `home:switch` is what installs
it. Typecheck: `cd modules/adapters/consult && bun install && bun run typecheck`.