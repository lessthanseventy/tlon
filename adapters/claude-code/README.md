# adapters · claude-code

What makes a `claude` session a citizen of a tlon thread — on any model — and, for the operator,
their own window onto the office.

## The identity

A citizen's identity is `(thread, agent)`, carried in the environment (`TLON_MCP_URL`,
`TLON_THREAD`, `TLON_AUTHOR`). You get it by launching through the loop, never by hand:

```
mise run server:claude              # on the Claude plan; opens a fresh thread
mise run claude:balanced -- 42      # on an ollama model (also deep / code / fast / local); JOINS thread 42
mise run claude:operator            # your own session, in operator mode: no thread
```

`launch.sh` evals the identity from `server:spawn` (or keeps one the server's window exported), then
execs Claude Code through `gateway.sh` with:

- `--mcp-config`: `tlon` (HTTP, `headersHelper` = `scripts/tlon-cli.sh token`, which mints a fresh
  token per connect, so auth survives a server restart; no token is ever on disk) and `lsp` (the
  LSP tools, `../lsp/src/mcp.ts`).
- `--settings`: the profile's deny rules (`TLON_PERMISSIONS_DENY`: the write fence, the bash and
  secret-path floor, the cut MCP tools), its read-only repos (`TLON_READ_DIRS`), the operator's
  statusLine off (the band replaces it), and — for a seat with `TLON_SANDBOX_FILE` — a strict bash
  sandbox with an allow list, in `dontAsk` mode: nothing waits on a prompt nobody watches.
- `--plugin-dir ..`: the tlon-citizen mod (the plugin root is `adapters/`).
- the citizen protocol and the role's persona (`TLON_ROLE_PROMPT_FILE`) as the appended system prompt.

`gateway.sh PROVIDER CMD…` turns `TLON_PROVIDER` (`ollama-cloud`, `ollama`, or none for the Claude
plan) into Claude Code's gateway settings — `ANTHROPIC_BASE_URL`, the ollama key from the env or
agenix, the model aliases pointed at ollama models — so a session on an ollama model never draws on
the Claude plan. The server's aside, role bench and one-shots run through it too.

## The mod (`mod.ts`)

A Claude Code [mod](https://code.claude.com/docs/en/plugins/mods/overview): hooks Claude Code runs in
its own process. Every server call goes over the session's own `tlon` connection (`$.mcp.call`); its
pure parts are `lib/` (bun-tested).

**Being a citizen**
- `session.start` registers the pane (`register`), and the session is on the roster.
- `turn.start` / `tool.call` / `turn.complete` declare thinking, what it is doing (`doing.ts`: the
  kind of work and a one-line, redacted summary for the activity feed) and idle — a subagent's turn
  ending is not the session's. The mod's own `$.mcp.call`s raise `tool.call` too and are skipped.
- **Wakes**: the server queues a teammate's message or an opening assignment (`Server.Wake`) instead
  of typing it into the pane; the mod drains `take_wakes` every few seconds and submits each as a
  turn, which Claude Code holds until the session is idle; a wake whose submit fails is put back
  (`put_back_wakes`) for the next poll. Taking a wake is not activity, so an idle session stays cold
  and an unheard wake reads unheard.
- **The brief** rides each prompt as context (`prompt.submit`) when the dossier changed, and again
  after a `/clear`. It says `You are <model> (Claude Code).` — the model that signs the commits.
- **Capture**: at turn end, above a 2k-char floor, the new transcript (brief cut out, secrets
  redacted) goes to the cheap ollama extractor and comes back as `derived` facts and questions;
  a compaction flushes whatever is there. A correction in a prompt is proposed as a habit, once.

**What the session shows**
- **The band** above the prompt: the thread and goal, the workline stage and its gate, the last
  check, todos, blockers, what is red (`office_glance`), and context / 5h / week use.
- **`/thread`**: a pane with the coworker's own figure (`office/cli.ts figure`), its voice, the
  workline with **advance** / **finish** buttons that fill the prompt (never call), the branch's
  commits, cited threads, the crew and what each is doing, and the thread's conversation.
- **Toasts**: a new @mention of this seat, something newly red, the day's landings at start, a
  landing the seat led (with a chime), and a line from the office's pool at most hourly.
- The spinner speaks in the seat's catchphrase; a finished turn gets a Borgesian verb.
- `#` and `@` complete from the threads and crew the session knows.

**What the session does differently**
- `tool.check` holds a `git push` (call `push_branch`), a branch switch in the live checkout, and a
  production write (`bin/server rpc`, `tlon-cli code`, `release:cut`: asked, never allowed).
- `attribution.text` signs a commit as the running model, on its provider's address.
- An Edit or Write carries the language server's diagnostics for the file.
- On the Claude plan with the five-hour window hot, Explore subagents run on Haiku and, near the
  cap, requests run at low effort. That last is its own mod, `plan/`, which `launch.sh` loads only
  for a Claude-plan seat: a `turn.step` hook re-yields the model's stream, and a stream that passes
  through a hook is held to Claude's tool-call id shape, which other models' ids fail (kimi's
  `functions.Bash:0`), so a gateway seat's stream never passes through one.
- `tool.describe` points Elixir edits at `edit_clause` / `rename_identifier`.

**Tools and commands** (from the mod, beside the server's)
- `consult` (a tool) and `/consult`, `/fresh` (commands): a one-shot Claude Code on another ollama
  model, with or without the session's transcript, read-only tools, held to the seat's own deny
  rules (`TLON_PERMISSIONS_DENY`, passed as its `--settings`).
- Auto-vision: an image Read on a text-only ollama model is described by a vision model instead.
- `web_search`: on the ollama gateway, where Claude Code's own WebSearch cannot reach.

**Operator mode** (`claude:operator`: `TLON_OPERATOR`, no thread): the band shows what waits on you
(`/api/office/needs`, at `TLON_MCP_URL`'s origin, else `127.0.0.1:4040`), the live release and what is unreleased, and your streak; each coworker's ask
is put to you as a question and answered by its key.

## Not here

- Jev-style decision models (`/v1/systemone` on a local ollama) for correction detection and capture
  triage: their endpoint is unverified here, and they need a local model pulled first.

## Verify

`mise run adapters:claude-code:check` (the helpers) and `mise run adapters:claude-code:mod` (the mod,
in Claude Code's own test kit). Live: launch a citizen against a node running this code, take a turn,
read the thread's activity feed — and `mise run server:roster`.
