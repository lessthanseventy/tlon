# ficciones — boundaries for a session at the repo root

This repository is one person's whole machine: an installer, dotfiles, a desktop, and an AI stack, as
Nix-shaped modules under `modules/`. It is named *ficciones* after the Borges collection that contains
the "Funes" story — the repo contains the `server` module as the book contains the story, and each module
is another story. Read `docs/plans/2026-08-14-machine-v2-and-funes-design.md` before reshaping anything
here — it is the design and every decision behind it.

## The dev loop — one shared API

The human and any agent drive this repo through the **same mise tasks** (`mise tasks` lists them) — one
control loop, not two, and no second way to run anything:

- `mise run check` — server compile-clean + tests; the green-before-commit gate.
- `mise run server:test` / `server:check` / `server:setup` / `server:doctor` — the server loop (Elixir/mix).
- `mise run flake:check` — the machine-level Nix gate.
- `mise run server:release` / `server:restart` / `server:console` / `server:logs` — the always-up server channel: a headless `mix release` kept up by a `systemd --user` service (loopback, real db), and the ways to redeploy/inspect/watch it.
- `mise run home:switch` — install/update this machine into the user profile via home-manager.

mise owns dev runtimes; Nix owns packaging and the system. **If a command belongs in the loop, it becomes
a task in `tasks/<group>.toml` (mise.toml includes them)** — never a prose instruction that drifts out of sync with what actually runs.

### Picking a pi model — the routing, as tasks ("litellm but not")

Two subscriptions, two buckets. The **$100 Claude plan** is the scarce, high-value bucket (5-hour +
weekly caps); the **$20 ollama.com plan** is the flat all-night workhorse. Neither charges per token —
"cost" means *which rate-limited bucket am I draining*, so the rule is: **push work down to the cheapest
bucket that can still do it well.** pi (the harness) rides the ollama bucket; Claude Code is the Claude
bucket — kept as two tools so a switch never drains the wrong one.

Inside the ollama bucket the routing is not a proxy — it's five mise tasks, each a named model profile
(the loop *is* the aliasing layer). Bare `pi` already starts on `ollama-cloud/deepseek-v4-flash` — the
 efficient-MoE default that drains the short rate-limit window far slower than a reasoning model
 (run `mise run ollama:usage` to see the session/weekly caps and per-model request counts); these pin an
alternate, and in-session `Ctrl+P` cycles the same ring. Pass a one-shot with `-- -p "…"`.

| Task | Model | Reach for it when |
|---|---|---|
| `mise run pi:balanced` | glm-5.2 | The strong default — Claude/GPT-alike, 976K ctx. Reach for it when the cheap default can't do the job, before escalating to pi:deep. |
| `mise run pi:deep`     | deepseek-v4-pro `thinking:high` | Hard reasoning/logic — the escalate-before-you'd-miss-Claude tier. |
| `mise run pi:code`     | kimi-k2.7-code | Coding-heavy work; code-specialized, fewer thinking tokens. |
| `mise run pi:fast`     | deepseek-v4-flash `thinking:low` | The same model as the bare default but `thinking:low` — quick/cheap throwaway, 1M ctx, fast tier. |
| `mise run pi:local`    | qwen3-coder (local daemon) | Free/offline grunt, tight iteration loops — zero cloud budget. |

Every launcher also makes the harness a **server citizen**: it opens a fresh server thread (or JOINs one
with a trailing id — `mise run pi:code -- 42`) and hands the session its identity, so the model shows up
in `server:roster` and briefs from the thread. `mise run server:claude [thread-id]` does the same for
Claude Code (its own MCP adapter, `headersHelper`-authed). If the server channel is down, the harness
still launches — just not as a citizen.

The bare default is `deepseek-v4-flash`, not glm-5.2, precisely because glm-5.2 is a reasoning model
whose thinking tokens drain the short rate-limit window fast — run `mise run ollama:usage` to watch
the session cap move per model. Two things that bite: **glm-5.2 is a reasoning model** (separate
`reasoning` + `content` fields) — give it token headroom or `content` comes back empty while thinking
eats the budget; and **`kimi-k3` is
deliberately absent** — ollama.com serves it as *extra* usage (HTTP 402), billed per-token on top of the
$20 plan, so it's out of both `flake.nix` and the live Ctrl+P ring. Every model above is plan-covered.

### Run once, read the log — never re-run to see more

When you run a command whose output you'll inspect — a test suite, a build, a `scratchpad`
script — run it through **`scripts/cap.sh`** (or `mise run cap -- <cmd>`). It runs the command
**once**, captures all output to a log under `.logs/`, and prints a lean summary: the exit code,
a test/build-summary line, failure lines on a non-zero exit, and a short tail — plus the exact
`tail`/`grep` to read more **from the saved log**.

The rule this enforces: **do not re-run a command with an escalating `grep … | tail -N` to see
more of its output.** The full output is already on disk — `grep`/`tail` the log. Re-running
burns tokens, re-streams noise into context, and risks a slightly-different invocation each time.
Catching yourself about to run the same command a second time with a different filter is the
signal to read the log, not repeat the call — the same escape hatch any SWE reaches for when a
loop starts repeating itself.

`cap` prints a distilled **signal** view (results, errors, warnings, counts) and drops the
install/compile/debug noise; a green suite collapses to a couple of lines. Knobs when you need
them: `CAP_TAIL=all` (the whole log inline, once), `CAP_TAIL=<n>`, `CAP_SIGNAL=<n>`. `mise run
cap:clean` sweeps the logs (they self-cap at 40 anyway).

### Let the watcher run the tests — don't spend a turn doing it by hand

When you're iterating on a change, **register a watcher instead of re-running tests yourself**:

- `mise run server:watch` / `mise run adapters:pi:watch` — re-run that module's suite on every change.
- `scripts/watch.sh <cmd>` (or `mise run watch -- <cmd>`) — watch-and-run anything, any scope
  (one test file, a folder, the whole suite). New test files under a watched dir are picked up.

Run it **in the background** (this harness: `Bash` with `run_in_background` — you're re-invoked
with the result when the suite settles; pi: a pane). Then just edit: you're pinged **red/green
automatically**, and you only spend a turn when something actually breaks. Kill the watcher when
the change is done. This is the intended inner loop here — not "edit, then manually run tests,
then read 1800 lines," every time.

### Edit Elixir with Menard, not sed/python/grep

`modules/menard` is the repo's AST-aware toolbox for Elixir (Sourceror patches: only the bytes
you named change). It is three doors onto one library — mix tasks, the `menard` stdio MCP in
Claude Code, and the coworkers' `rename_identifier` / `edit_clause` / `outline_file` / `run_verb`
tools scoped to their worktree. Use it for every Elixir edit and search:

- `clause replace|delete|insert-after|insert-before FILE [Mod.]name/arity HEAD [CODE] [--nth N]` —
  one clause, addressed by its head as written (guard included, parens optional). In a file with
  several modules, qualify the name (`Menard.MCP.Clause.execute/2`); a bare name they share is
  refused. A miss lists the heads that exist — read it, don't guess again. Two clauses CAN share a
  head (an insert beside its twin); that is refused with both line numbers, and `--nth` says which.
- `clause rewrite … HEAD CODE` — the WHOLE clause, head included. The verb for changing args,
  adding a guard, destructuring a parameter; `replace` only ever swaps a body. `CODE` may lead with
  the clause's comment, which then replaces the one already there.
- `clause doc|comment FILE name/arity HEAD [TEXT]` — the `@doc` above a clause, or the `#` comment
  above it. Prose in, `#`/heredoc added; no TEXT deletes it. Both are string literals no other verb
  reaches — this is why a docstring or a `why` used to mean editing the file as text.
- `clause insert-at FILE (Mod.Name|-) [top|bottom] CODE` — a whole new FUNCTION, which has no
  sibling clause to anchor to. Placement follows the code: a `defp` lands with the other private
  functions, a `def` with the public ones. (A new *clause* of an existing function is
  `insert-after` — name its sibling.)
- `stmt insert-after|insert-before|replace|delete|list FILE name/arity HEAD MATCH [CODE] [--nth N]`
  — ONE statement inside a clause body, addressed the way a clause is: name the clause, then the
  statement by what is WRITTEN. Reaches a line in a `do` block, a step in a `with`, and a `case`
  ARM alike. `list` prints what is there; a miss prints it too.
- `write FILE CODE` (`-` reads stdin) — a whole file: a NEW module, or a rewrite so total that
  patching is the wrong tool. Refuses Elixir that doesn't parse before it reaches disk. Reach for
  this instead of the `Write` tool for `.ex`/`.exs`.
- `clause visibility FILE name/arity public|private` — EVERY clause of a function at once, since a
  half-flipped one does not compile. Going private drops an attached `@doc` (Elixir discards it and
  warns).
- `attr get|set|delete|list FILE NAME [VALUE]` — module attributes: `@hints`, `@colors`, `@panes`.
  A name that repeats per clause (`@doc`, `@impl`, `@spec`) is refused — those belong to the clause
  verbs, which already carry them.
- `block get|replace|add|relabel|list FILE NAME [CODE] [--label X] [--in PARENT]` — a macro's `do`
  block (`schema do`, `describe "…" do`). `--label` is its first string argument; `--in` names a
  parent to append inside, either a labelled block or a MODULE. `relabel FILE NAME OLD NEW` renames
  a `test`/`describe` label. A schema field lives here (`block replace FILE schema … --label <table>`),
  not in the clause verbs.
- `directive add|remove|list FILE alias|import|require|use MOD [OPTS]` — placed in Elixir's
  conventional order (use → import → alias → require, alphabetised), so the next format pass does
  not move it.
- `module add|list FILE [CODE]` — a whole `defmodule` in a file that already has one.
- `deps FILE name/arity` — what a function references: local calls (with who ELSE calls them),
  remote calls, the modules whose aliases must travel, the attributes that will not. The read
  before moving code. There is no `move` verb on purpose — a move is this report plus insert-at,
  directive add, delete, find calls and run compile.
- `rename OLD NEW FILES…` — an identifier across files (heads, calls, captures, variables).
- `find calls|defs|aliases TARGET FILES…` — grep that knows the code; strings and comments never match.
- `outline FILE` — read a module's shape before editing it.
- `run check|test|format|compile [--in DIR]` — one structured answer, failures with the test's source.

CLI: `mise run menard -- VERB …` (always compiles the current code; the MCP server runs the code
it started with — restart Claude after changing Menard). Dashes and underscores both work at both
doors. `mise run menard -- --frozen VERB …` runs the last build with no compile step — the escape
hatch for editing Menard WITH Menard, where a half-applied edit otherwise locks the tool out of
finishing it.

Python/sed string patches on `.ex` files fail on reformatting and land in the wrong module; the
`Edit` tool is for small literal changes (a doc line, a test assertion) and for non-Elixir files,
which Menard does not cover (TypeScript, Lua, Nix). What Menard still has no verb for: a `case`
arm, and a `@spec` above a clause `rewrite` changes the signature of.

**Both of those are hooks now, not honour-system.** Menard ships them (`modules/menard/hooks/`,
declared in its plugin manifest): a `PreToolUse` guard that blocks `Edit`/`Write` on a module, and
a `PostToolUse` formatter that runs the file's OWN project formatter on every write — including
plugins, so `console`'s Styler runs there too.

**`modules/menard/AGENTS.md` is the working reference** — which verb for which shape, and the
gotchas no error message can teach. Read it before your first Elixir edit; it is menard's own
file, so it travels with the plugin rather than living here.

The hooks come from the **installed plugin**, not from this repo's `.claude/settings.json` — the
by-path wiring that predated the plugin is gone, because two registrations of the same hook is the
duplication menard exists to prevent. `.claude-plugin/marketplace.json` at the root publishes it:

    /plugin marketplace add ~/projects/ficciones
    /plugin install menard@ficciones

A clone without that install has **no guard**, and `Edit` on a module will go through. The rule
holds anyway — it is in `modules/menard/AGENTS.md`, which is where an agent should be reading it.

## How to work — the four rules

Every agent on this machine, in any repo, works by the four rules in `modules/agents/how-to-work.md`:
think before coding (state assumptions, ask when readings diverge), the simplest thing that works,
surgical changes, and goal-driven execution against a check you can run. The flake installs that file
as `~/.claude/CLAUDE.md` and `~/.pi/agent/AGENTS.md`, so it is already in your context; this section
exists so a reader of the repo knows where the law comes from and edits the one source.

## The rules most likely to be broken by accident

- **Working inside `modules/server/`? That module has its own law.** Read `modules/server/AGENTS.md` and
  `modules/server/docs/spec.md` first, and let them win. This root file governs the layer *around* the
  modules, not the modules' insides.
- **`server` is a bounded module and the boundary is load-bearing.** It must never import up into machine
  config — no reading a `theme` variable, no assuming `desktop`, no path into `hosts/`. The reason is the
  cohesion model: the *same* `server` runs on other machines, sovereign on each, talking only over its
  channel. A reach upward welds it to this box and breaks that. The unit that travels is `modules/server/`.
- **`nix` runs from the agent tools now** (Arch's nix, not Determinate — see the Nix machine-truth
  memory). So `nix flake check`, `nix eval`, and `nix build .#server` are fair to run and verify directly.
  What stays the human's are the **system-mutating** commands — `home-manager switch`, `nixos-rebuild
  switch` on the host — because building the machine is a change the human owns. A claim that a build
  works without having run it is the one thing this repo cannot afford.
- **A module is born when it has content.** Do not create empty placeholder directories to imply a
  structure that does not exist yet. The tree should not lie about what is built.
- **An `AGENTS.md` is born the same way a comment is — when a scope needs context its parent doesn't
  give.** Root holds repo-wide invariants; a module or subapp gets its own when it has distinct law, a
  distinct dev loop, or gotchas that bite (`server`, `adapters` + its adapters, `console`). Don't add one per
  folder by reflex — `lib/schemas/`, `test/`, etc. earn a file only once they accumulate a rule a
  weaker model keeps getting wrong; until then that guidance lives in the module's file. Keep every one
  terse and actionable to the same standard as comments: orientation, the exact commands, the law, the
  gotchas, a pointer to the one deeper doc — no lore. Skeleton: **what it is → Law → dev loop → Verify.**
  The tree: `AGENTS.md` (here) · `modules/server/AGENTS.md` · `modules/console/AGENTS.md` ·
  `modules/adapters/AGENTS.md` (+ `consult`/`fmt`/`lsp`).
- **Keep docs in sync with the code, in the same commit.** A change that makes a module's `AGENTS.md`
  or a load-bearing comment stale updates it in that change — stale guidance is worse than none,
  because a weaker model trusts it. Nothing mechanical can catch this (staleness is semantic, invisible
  to compile/tests), so it's on you. (The `programs.rbw` comment that survived the rbw→agenix switch
  still describing the old design is the incident this comes from.)
- **Adopt Nix gradually.** home-manager on Arch first, a disposable NixOS VM (`nixos-rebuild build-vm`)
  as the testbed, metal last. Do not propose replacing the OS as a first step.
- **Commit as who you are.** An agent's commit ends with a `Co-Authored-By:` trailer naming the model
  that wrote it — YOUR model, read from the brief's `You are … (pi)` line (or `$PI_MODEL`), never a
  name copied from an example or another model's commit. Format: `Co-Authored-By: <your model> (pi)
  <noreply@ollama.com>` (pi) or `Co-Authored-By: <your model> <noreply@anthropic.com>` (Claude Code).
  `git log` is part of the machine's memory; a commit that hides its author — or names the wrong one —
  lies to it. (The first dogfood branch shipped 7 unattributed machine commits — that's the incident
  this rule comes from.)
- **Sandboxed Bash — phantom dotfiles and unreachable localhost are the sandbox, not the repo.** Both
  harnesses are affected: pi via the `pi-sandbox` extension (`~/.pi/agent/sandbox.json`, seeded at
  `flake.nix`'s `piSandboxSeed`) and Claude Code via its own. pi-sandbox delegates to
  `@carderne/sandbox-runtime`, a fork of Anthropic's, so **the `CLAUDE_CODE_*` and proxy env vars
  inside a pi bash call come from the fork — they are not evidence you're in Claude Code.** Two
  symptoms follow, and neither is a bug to chase:
  - *Phantom untracked dotfiles.* The wrapper bind-mounts over shell-rc / `.gitconfig` / editor paths,
    so `git status` **run inside a bash call** reports `.bashrc`, `.zshrc`, `.gitconfig`, `.env`,
    `.mcp.json`, `.idea`, `.vscode`, … as untracked at the repo root. The tell: `ls -la` shows them
    0-byte `-r--r--r--` (or `crw-rw-rw- 1,3`, a `/dev/null` char device). They don't exist on disk.
    Never `git add`/`rm` them or try to "clean them up".
  - *`127.0.0.1` is not the host's loopback.* bash runs under `bwrap --unshare-net` in a private netns,
    so `curl 127.0.0.1:4041`, `ss -tlnp`, and `systemctl --user` can never see the server channel —
    **regardless of whether it is up.** `allowLocalBinding` only permits binding *within* that netns.
    External traffic escapes via a socat→unix-socket proxy, but that proxy refuses loopback targets
    with a `403`, so there is no route. Do not conclude "server is down" from a bash probe; a bash
    probe cannot answer the question. **server MCP tools still work** — pi makes those calls from its
    own process, outside bubblewrap — so use them, or ask the human to check from the host.

  To get true git state or real host network, disable the sandbox: `Alt+S`, `/sandbox-disable`, or
  relaunch `pi --no-sandbox`.
- **Comments earn their place — load-bearing only.** A comment survives only if it states a non-obvious
  *why* or a real gotcha the code can't. Narrative, lore, dated incident references, decorative
  `# --- section ---` dividers, and restatements of what the next line plainly does are noise — don't
  write them, and trim them when you touch a file. Prose belongs in docstrings (`@moduledoc`/`@doc`/
  `@spec`, JSDoc) and the `*.md` files; inline comments are load-bearing only. (A repo-wide pass cut
  ~320 comment lines to this standard — don't grow them back.)
  - **No devlog.** A comment describes what IS, never how it got here. Cut the evolution storytelling:
    *"used to X / now Y instead"*, *"supersedes / replaces / reverses the old…"*, *"the bug this
    replaces was…"*, *"before the fix / pre-B1.4"*, rename & migration history, "we tried X then…".
    Keep the current-state constraint even when it grew out of a past bug — just state the constraint,
    drop the incident. The git history holds the story; the code holds the present.
- **Secrets: agenix for the machine, rbw for you.** A secret a non-interactive process needs — a
  service, a spawned pane (e.g. `OLLAMA_API_KEY` for the Tlön pi) — lives age-encrypted in
  `secrets/*.age` (agenix), decrypted at `home:switch` to `$XDG_RUNTIME_DIR/agenix/<name>` with *no*
  runtime unlock. Human/interactive passwords live in Bitwarden via `rbw`. Never a plaintext key in the
  repo, a dotfile, or the nix store. To add a machine secret: recipient pubkey → `secrets/secrets.nix`,
  `agenix -e secrets/<name>.age`, `git add` it (nix can't see untracked files), reference it via
  `age.secrets` in `flake.nix`.

## Verify

`server` day-one step 1 exists and runs; verify with `mise run check` (tests + types) and `mise run
flake:check` (Nix). `mise run check:names` (first in `check`) is the names-exist gate: every
`Server.*`/`Console.*` module, mix task, mise task and `~/.pi/agent` file that scripts, `mise.toml`,
`flake.nix`, the adapters or a guide name must actually exist — a rename that strands a reference
fails here instead of at 2am. A claim that something works is backed by the command that proved it — and the agent
and human run the *same* `mise` tasks, so "it works" means the shared task passed, not two private ones.
