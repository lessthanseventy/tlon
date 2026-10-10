# tlon — boundaries for a session at the repo root

Tlön, the dev product: `server/` (the always-up brain — threads, facts, worklines, staffing; its node
is `funes@`), `adapters/` (what makes a Claude Code session a citizen of the server) and `office/`
(the pixel-art room over it: a shared kit, its rooms, and the standalone TUI that is the operator's
surface). It runs on any box with Postgres and mise; the home machine wires it in from
ficciones (`~/projects/ficciones`), which is where the Nix, the desktop and the secrets live. The
design that split it out: ficciones' `docs/plans/2026-09-25-sovereign-repos-and-aleph-design.md`.

## The dev loop — one shared API

The human and any agent drive this repo through the **same mise tasks** (`mise tasks` lists them) — one
control loop, not two, and no second way to run anything:

- `mise run check` — names gate + server, adapters and office gates + the task manual; the green-before-commit gate.
  One at a time per machine: it waits its turn in the checks queue (`scripts/checks-queue.sh`, saying who
  holds it) and runs `check:all`, so a verify, a landing's gate, a schedule and a session never run two full
  suites on the one test database at once. Don't call `check:all` to skip the line.
- `mise run server:test` / `server:check` / `server:setup` / `server:doctor` — the server loop (Elixir/mix).
- `mise run server:release` / `server:restart` / `server:stop` / `server:console` / `server:logs` — the always-up server channel: a headless `mix release` kept up by a `systemd --user` service (loopback, real db), and the ways to rebuild/stop/inspect/watch it (`server:stop` takes the coworker panes down with it).
- `mise run release:cut` / `release:status` — what the service runs is the **release pointer** (`refs/heads/live`, built in `.release/`), not main: a merge ships when a cut moves the pointer (fast-forward, merged work only; `-- --rollback` to go back). `scripts/release.sh`. `release:status` also reads whether main is releasable (`Server.Release.Candidate`: `check:main` and `release:smoke` passed on exactly that commit — each run ends `ran-on: <check> <sha>`, which a scheduled run records — and nothing mid-flight). The `pm` coworker proposes cuts (`Server.Release.PM`): under `auto_land_risk` it cuts them itself, else they reach you as one gate on the root thread.
- `mise run bench:longmemeval` — LongMemEval (agent-memory-benchmark's harness, ollama.com answers and judges) against
  server recall on the throwaway `tlon_bench` db, never the live store; `bench/longmemeval/bridge.exs` says what each
  `TLON_BENCH_MODE` measures, and `-- --memory bm25` runs the keyword reference on the same slice.
- `mise run bench:roles -- --suite canary|full [--role R] [--model provider/model[:effort]]` — can each coworker
  role do its job on the model it is routed to, and at what cost: frozen tasks per role (`bench/roles/tasks/`),
  graded, run headless through the role's own harness; `bench/roles/README.md` is the table, newest first. It
  spends real plan quota and touches no db (`Server.Bench.Roles`).

On the home machine, installing and updating the service is ficciones' job (its `home:switch` and
`machine:update`); here you build and restart the release. mise owns the dev runtimes. **If a command belongs in the loop, it becomes
a task in `tasks/<group>.toml` (mise.toml includes them)** — never a prose instruction that drifts out of sync with what actually runs.

### Picking a model — the routing, as tasks ("litellm but not")

Two subscriptions, two buckets. The **$100 Claude plan** is the scarce, high-value bucket (5-hour +
weekly caps); the **ollama.com Pro plan** is the all-night workhorse. ollama.com now meters plans in
monthly usage credits spent at per-model per-token rates; accounts still on a legacy plan (this one, as of
2026-10) get a short session window and a weekly cap instead. Either way "cost" means *which capped bucket
am I draining*, so the rule is: **push work down to the cheapest bucket that can still do it well.**
Every agent runs in **Claude Code**; an ollama model through Claude Code's gateway setting
(`adapters/claude-code/gateway.sh` points `ANTHROPIC_BASE_URL` at ollama.com or the local daemon), so a
session on an ollama model sends nothing — its subagents and background requests included — to the
Claude plan.

The routing is not a proxy — it's five mise tasks, each a named model profile (the loop *is* the
aliasing layer). Run `mise run ollama:usage` to see credits used of included and the reset date (or the
legacy session/weekly meters), plus daily request counts. Inside a session `/model <name>` switches to
another model on the same provider.

| Task | Model | Reach for it when |
|---|---|---|
| `mise run claude:balanced` | glm-5.2 | The strong default — Claude/GPT-alike, 976K ctx. Reach for it when the cheap one can't do the job, before escalating to claude:deep. |
| `mise run claude:deep`     | deepseek-v4-pro, effort high | Hard reasoning/logic — the escalate-before-you'd-miss-Claude tier. |
| `mise run claude:code`     | kimi-k2.7-code | Coding-heavy work; code-specialized, fewer thinking tokens. |
| `mise run claude:fast`     | deepseek-v4.1-flash, effort low | Quick/cheap throwaway, fast tier — the efficient-MoE model that drains the plan slowest. |
| `mise run claude:local`    | qwen3-coder (local daemon) | Free/offline grunt, tight iteration loops — zero cloud budget. |
| `mise run server:claude`   | the Claude plan's default | When it has to be Claude. |

Every launcher also makes the session a **server citizen**: it opens a fresh server thread (or JOINs one
with a trailing id — `mise run claude:code -- 42`) and hands the session its identity, so it shows up in
`server:roster` and briefs from the thread. If the server channel is down, Claude Code still launches —
just not as a citizen.

Claude Code's own prompt is ~20k tokens a request, so on credits every turn costs more than a bare
completion; the server's one-shots (banter, the judge, titles) run `--bare` with no tools for that reason
(`Server.ModelCli`, 79 tokens in). Two things that bite: **glm-5.2 is a reasoning model** (separate
`reasoning` + `content` fields) — give it token headroom or `content` comes back empty while thinking
eats the budget; and **`kimi-k3` is deliberately absent** — ollama.com serves it as *extra* usage (HTTP
402), billed per-token on top of the plan, so it's out of the model ring (`Server.Profiles`). Every model
above is plan-covered.

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

**Elixir tests and the gate go through Menard, not `cap`:** `~/projects/menard/bin/menard run test --in
server [FILE[:LINE]]` and `~/projects/menard/bin/menard run check --in server`. One run answers with one JSON line: `ok` and the counts when green; when red, every
failure with its kind, `file:line` and message, a failing test's name, source and the assertion's
left and right. It is this section's rule with the failures already parsed out, so there is nothing
to grep for. `cap` stays the door for everything else: builds, scripts, `mise run server:check`'s
evals.

`cap` prints a distilled **signal** view (results, errors, warnings, counts) and drops the
install/compile/debug noise; a green suite collapses to a couple of lines. Knobs when you need
them: `CAP_TAIL=all` (the whole log inline, once), `CAP_TAIL=<n>`, `CAP_SIGNAL=<n>`. `mise run
cap:clean` sweeps the logs (they self-cap at 40 anyway).

### Let the watcher run the tests — don't spend a turn doing it by hand

When you're iterating on a change, **register a watcher instead of re-running tests yourself**:

- `mise run server:watch` / `mise run adapters:claude-code:watch` — re-run that module's suite on every change.
- `scripts/watch.sh <cmd>` (or `mise run watch -- <cmd>`) — watch-and-run anything, any scope
  (one test file, a folder, the whole suite). New test files under a watched dir are picked up.

Run it **in the background** (this harness: `Bash` with `run_in_background` — you're re-invoked
with the result when the suite settles). Then just edit: you're pinged **red/green
automatically**, and you only spend a turn when something actually breaks. Kill the watcher when
the change is done. This is the intended inner loop here — not "edit, then manually run tests,
then read 1800 lines," every time.

### Edit Elixir with Menard, not sed/python/grep

Menard ([its own repo](https://github.com/lessthanseventy/menard), checked out at `~/projects/menard`)
is the AST-aware toolbox for Elixir (Sourceror patches: only the bytes you named change).
**[Its `AGENTS.md`](https://github.com/lessthanseventy/menard/blob/main/AGENTS.md) is the
reference** — which verb for which shape, what each guarantees, and the gotchas no error message can
teach. It ships with the plugin, so it is the one copy; this section is only the doors into it from here.

Three doors onto one library:

- `~/projects/menard/bin/menard VERB …` — the plugin's own CLI, by the path its refusals name: the
  one way in, and the one the eval measures. It runs whatever that checkout holds, uncommitted edits
  included, as it does for every project using the plugin. Dashes and underscores both work.
- the `menard` stdio **MCP** in Claude Code — runs the code it started with, so **restart Claude
  after changing Menard**.
- the coworkers' `rename_identifier` / `edit_clause` / `outline_file` / `run_verb` tools, scoped to
  their worktree — the server's own hex dep (`server/mix.exs`, locked in `server/mix.lock`); publish
  menard and bump the lock to give them a newer one.

`~/projects/menard/bin/menard --frozen VERB …` runs the last build with no compile step — the escape hatch for
editing Menard WITH Menard, where a half-applied edit otherwise locks the tool out of finishing it.

The `Edit` tool is for the languages Menard does not cover — TypeScript, Lua, Nix. The plugin no
longer blocks it on a module: `menard` is hook-only in Claude Code now, a `PostToolUse` formatter
that runs the file's own project formatter on every write and says
what it changed. Its AST tools are the separate `manos` plugin. Neither is in
`.claude/settings.json`; the rule holds regardless.

    /plugin marketplace add lessthanseventy/menard && /plugin install menard@menard
    /plugin install manos@menard

Still missing a verb: a `@spec` above a clause whose signature `rewrite` changes.

## How to work — the four rules

Every agent on this machine, in any repo, works by the four rules in ficciones' `modules/agents/how-to-work.md`:
think before coding (state assumptions, ask when readings diverge), the simplest thing that works,
surgical changes, and goal-driven execution against a check you can run. ficciones' flake installs that file
as `~/.claude/CLAUDE.md`, so it is already in your context; this section
exists so a reader of the repo knows where the law comes from and edits the one source.

## The rules most likely to be broken by accident

- **Working inside `server/`? That module has its own law.** Read `server/AGENTS.md` and
  `server/docs/spec.md` first, and let them win. This root file governs the layer *around* the
  modules, not the modules' insides.
- **Nothing here reaches into the machine.** No reading ficciones' theme, no assuming its desktop, no
  path into `~/projects/ficciones` for tlon's own files (`Server.Profiles.tlon_root/0` is where they are). The reason is the
  cohesion model: the *same* `server` runs on other machines, sovereign on each, talking only over its
  channel. A reach upward welds it to this box and breaks that. The unit that travels is `server/`.
- **A module is born when it has content.** Do not create empty placeholder directories to imply a
  structure that does not exist yet. The tree should not lie about what is built.
- **An `AGENTS.md` is born the same way a comment is — when a scope needs context its parent doesn't
  give.** Root holds repo-wide invariants; a module or subapp gets its own when it has distinct law, a
  distinct dev loop, or gotchas that bite (`server`, `adapters` + its adapters, `office`). Don't add one per
  folder by reflex — `lib/schemas/`, `test/`, etc. earn a file only once they accumulate a rule a
  weaker model keeps getting wrong; until then that guidance lives in the module's file. Keep every one
  terse and actionable to the same standard as comments: orientation, the exact commands, the law, the
  gotchas, a pointer to the one deeper doc — no lore. Skeleton: **what it is → Law → dev loop → Verify.**
  `find . -name AGENTS.md` lists them; a copy of that list here only ever goes stale, and had.
- **Keep docs in sync with the code, in the same commit.** A change that makes a module's `AGENTS.md`
  or a load-bearing comment stale updates it in that change — stale guidance is worse than none,
  because a weaker model trusts it. Nothing mechanical can catch this (staleness is semantic, invisible
  to compile/tests), so it's on you. (The `programs.rbw` comment that survived the rbw→agenix switch
  still describing the old design is the incident this comes from.)
- **Commit each piece of work when it is done**: one commit per bug, feature or ticket, before
  you start the next, so `git log` says what changed and why.
- **History is linear.** GitHub's `main` is protected: rebase-merge only, every change through a PR.
  Rebase onto main, never merge it in, never make a merge commit; ship work as a PR branch, or a
  stack of small ones with `gh stack`. A workline's approval lands its branch the same way —
  rebased onto origin's main and gated (`Server.Workline.Merge`), then published: the branch pushed,
  a PR opened, auto-merged by GitHub once green (`Server.Workline.Publish`). The checkout's own main
  is never moved by a landing; it only follows origin. Rewriting pushed history is the human's call —
  except a coworker's own thread branch: the server pushes `work/<slug>` for it, force-with-lease
  (the `push_branch` tool), and a coworker pane's own `git push` is refused (`scripts/git-hooks/pre-push`).
- **Commit as who you are.** An agent's commit ends with a `Co-Authored-By:` trailer naming the model
  that wrote it — YOUR model, read from the brief's `You are … (Claude Code)` line, never a name copied
  from an example or another model's commit. Format: `Co-Authored-By: <your model> <noreply@anthropic.com>`
  on the Claude plan, `Co-Authored-By: <your model> <noreply@ollama.com>` on an ollama model.
  `git log` is part of the machine's memory; a commit that hides its author — or names the wrong one —
  lies to it. (The first dogfood branch shipped 7 unattributed machine commits — that's the incident
  this rule comes from.)
  The server backs it mechanically: a pane it spawns carries `TLON_MODEL`, the model its seat was
  actually launched on, and `scripts/git-hooks/prepare-commit-msg` stamps it as `Tlon-Model:` on every
  commit (a review's commit too). It is the model as launched (a mid-session switch is not seen), so
  the record holds even when a model is wrong about itself.
- **Sandboxed Bash — phantom dotfiles and unreachable localhost are the sandbox, not the repo.** Claude
  Code's bash sandbox (an ollama coworker's runs strict, from its profile's `sandbox.json`) has two
  symptoms, and neither is a bug to chase:
  - *Phantom untracked dotfiles.* The wrapper bind-mounts over shell-rc / `.gitconfig` / editor paths,
    so `git status` **run inside a bash call** reports `.bashrc`, `.zshrc`, `.gitconfig`, `.env`,
    `.mcp.json`, `.idea`, `.vscode`, … as untracked at the repo root. The tell: `ls -la` shows them
    0-byte `-r--r--r--` (or `crw-rw-rw- 1,3`, a `/dev/null` char device). They don't exist on disk.
    Never `git add`/`rm` them or try to "clean them up".
  - *`127.0.0.1` is not the host's loopback.* bash runs under `bwrap --unshare-net` in a private netns,
    so `curl 127.0.0.1:4041`, `ss -tlnp`, and `systemctl --user` can never see the server channel —
    **regardless of whether it is up.** Do not conclude "server is down" from a bash probe; a bash
    probe cannot answer the question. **server MCP tools still work** — Claude Code makes those calls
    from its own process, outside the sandbox — so use them, or ask the human to check from the host.

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
- **Secrets come from the machine.** tlon reads keys from the env or
  `$XDG_RUNTIME_DIR/agenix/<name>` (mise.toml's `OLLAMA_API_KEY`); it never stores one. Never a
  plaintext key in the repo.

## Verify

`mise run check` is the gate. `mise run check:names` (first in it) is the names-exist gate: every
`Server.*` module, mix task and mise task that scripts, `mise.toml`, the adapters or a
guide name must actually exist — a rename that strands a reference fails here instead of at 2am. A
claim that something works is backed by the command that proved it — and the agent and human run the
*same* `mise` tasks, so "it works" means the shared task passed, not two private ones.
