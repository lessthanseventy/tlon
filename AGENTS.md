# tlon — boundaries for a session at the repo root

Tlön, the dev product: `server/` (the always-up brain — threads, facts, worklines, staffing; its node
is `funes@`), `adapters/` (what makes a Claude Code session a citizen of the server)
and `house/` (a standalone Godot window over the home: what the operator's jots left open). It runs on any box with Postgres and mise; the home machine wires it in from
ficciones (`~/projects/ficciones`), which is where the Nix, the desktop and the secrets live.

## The dev loop — one shared API

The human and any agent drive this repo through the **same mise tasks** (`mise tasks` lists them) — one
control loop, not two, and no second way to run anything:

- **A session lands through babylon**, the ticket board every session on this machine shares:
  `claim_ticket`, then the `start` command its answer gives (a `wt` worktree on the ticket's branch
  `t<id>-<slug>`); work there, run only the tests of what you changed (`menard run test <files>` for
  Elixir, a module's own targeted check otherwise), commit on that branch, `submit_ticket`. babylon, one
  ticket at a time machine-wide, rebases the branch onto origin/main in its own warm worktree
  (`~/.cache/babylon/work/tlon`), runs `mise run check` once, has the change reviewed headlessly (it
  approves, fixes small things itself, or requests changes) and fast-forwards main. The outcome is typed
  into the session's pane and kept in its babylon inbox: done, or back to `doing` with why in the
  ticket's `stage_note`. No PR, no `review_branch`, no `mise run land`, no full check from the session.
  Worklines (the server's own coworker seats and threads) keep the server's line, below.
- `mise run check` — names gate (which also holds the task manual to its source) + script self-tests (`check:scripts`: each `scripts/*.test.sh` is a `check:scripts:<name>` task, run in parallel) + tracked-junk gate (`check:ignored`: no tracked file under an ignored path) + server and adapters gates + the task manual + the house's gate (`check:house`, after the others: `house:gate`, below, but only when `house/` changed in the commits being gated, the range from the merge-base with `origin/main` to HEAD and any uncommitted `house/` file; on main itself there is no range, so a full run); the green-before-commit gate. A session's change gets it once, from babylon at `submit_ticket`.
  The house gate needs Godot, which is the machine's, not mise's: with `godot` on PATH it always runs when `house/` changed. Without it, a machine that sets `TLON_HOUSE_GATE=required` (the home machine does) fails the gate; any other prints `house: SKIPPED — godot not on PATH …` and `check`'s closing summary repeats the skip, so a pass that skipped the house never reads as one that ran it (and such a tree is not recorded green).
  One at a time per machine: it waits its turn in the checks queue (`scripts/checks-queue.sh`, saying who
  holds it), first come, first served, and runs `check:all`, so a verify, a landing's gate, a schedule and a session never run two full
  suites on the one test database at once. Don't call `check:all` to skip the line. A shell that can't open
  the queue's lock (a sandboxed Bash) is refused with exit 2: run it unsandboxed; `CHECKS_UNQUEUED=1` runs it
  unqueued on a box with no usable `XDG_RUNTIME_DIR`. **A coworker seat never runs it:** its sandbox has no
  checks queue, Postgres or GitHub. Run `menard run check --in server` (or a module's own check) on your
  change and advance; verify runs the gates its diff can break on the server (`Server.CheckScope`; the full gate when the diff spans modules), and landing rebases onto main and runs the full gate again.
  Its verdict is a record, not a requirement of main: on a clean tree (nothing uncommitted or untracked) it posts
  the commit status `tlon/check` (success or failure) on HEAD's sha (`scripts/check.sh`); on a dirty tree, or a
  commit GitHub does not have yet, it posts nothing and says so, and gh missing or refusing is said, never red.
  `TLON_CHECK_STATUS=0` posts nothing. What keeps main green is the check that runs before a landing: babylon's
  for a session, the server's merge queue for a workline or an existing PR.
- `mise run land -- <pr>` — for a PR that already exists (a session lands through babylon, above): land a reviewed PR through the server's merge queue (`scripts/land.sh` →
  `Server.PRLanding`, the same line and gate as worklines): queued only when its branch's newest review on
  tlon (`review_branch`) approves its head, or that head rebased onto main with the same patches. An approving
  `review_branch` queues it by itself (`Server.PRLanding.request_branch/3`: the branch's one open PR onto main,
  through the same preflight), so the task is for a PR whose approval came first or was refused then; its turn
  rebases it onto origin/main, gates it, pushes it with lease, comments the review on the PR, posts
  `tlon/check` and merges at exactly that head (`gh pr merge --rebase --match-head-commit`). The outcome is
  posted on the review's thread. The service must be up. A sandboxed seat (no epmd) calls the `land_pr(pr)`
  MCP tool instead: the same preflight and queue, over MCP. `land -- <pr> --operator` is the operator's
  word in place of the review, for a change the operator directed and said to land: recorded as an
  approval of its head by "the operator", then the same queue and gate. Only on the operator's say.
- `mise run review -- <branch>` — a review with no seat, on demand (not a step of a session's landing): one headless model run reads the pushed branch's
  diff in a throwaway checkout of its head, read-only, and prints the review (`Server.BranchReview.Headless`).
  The reviewer is the first of `:branch_reviewers` that wrote none of the branch, by its commits'
  `Tlon-Model` and `Co-Authored-By` trailers; with none left it is refused. The verdict is recorded on that
  commit as `review_branch` records one: an approval queues the branch's open PR as `land` does, requested
  changes exit 1 with the findings. The service must be up. `review -- <branch> <repo>` reads a branch of
  another repo's checkout the same way and only prints the review (`Headless.opinion/3`): that repo's
  reviews and landings are not tlon's to keep.
- `mise run house:gate` — the house's whole verification, fast (`scripts/house-gate.sh`): `house:check`, then each soak section as its own headless Godot in parallel (its own throwaway `XDG_DATA_HOME`, its own stub-server port; `TLON_HOUSE_JOBS` at once, default half the cores), a table of section times, every `FAIL` line named by its section, non-zero on a failed, timed-out or `SOAK OK`-less section. `house/AGENTS.md` has the loop.
- `mise run server:test` / `server:check` / `server:setup` / `server:doctor` — the server loop (Elixir/mix).
- `mise run server:release` / `server:restart` / `server:stop` / `server:console` / `server:logs` — the always-up server channel: a headless `mix release` kept up by a `systemd --user` service (loopback, real db), and the ways to rebuild/stop/inspect/watch it (`server:stop` takes the coworker panes down with it, mid-turn ones too: emergencies only).
- `mise run release:cut` / `release:status` — what the service runs is the **release pointer** (`refs/heads/live`, built in `.release/`), not main: a merge ships when a cut moves the pointer, and babylon's landing runs `mise run install`, which cuts at origin/main (fast-forward, merged work only; `-- --rollback` to go back). The cut is how new code runs: the restart waits for quiet, and panes whose launch changed roll themselves between turns; a cut that changes neither `server/` nor `mise.toml` builds and restarts nothing, and one that changes only server code that can be swapped hot-loads instead of restarting (`Server.Release.HotLoad`; it restarts when unsure, and says why). Each night, once the gate and smoke have run, the server cuts the newest commit that passed both (`Server.Release.PM.auto/1`): the standing approval and the gate apply as usual, and a pause or a rollback stops it. `scripts/release.sh`. `release:status` also reads whether main is releasable (`Server.Release.Candidate`: `check:main` and `release:smoke` passed on exactly that commit — each run ends `ran-on: <check> <sha>`, which a scheduled run records and a hand run reports via `scripts/lib/record-ran.sh` (`POST /api/release/ran`) — and nothing mid-flight). The `pm` coworker proposes cuts (`Server.Release.PM`): under `auto_land_risk` it cuts them itself, else they reach you as one gate on the root thread.
- `mise run scratch:new -- <name> [<ref>]` / `scratch:prune` — a change built outside the live checkout: a
  detached worktree under `~/.cache/tlon-scratch/` — a seat's under its own `tlon-scratch/<seat>/`, the one its sandbox writes (never inside the repo, where a `tN` dir reads as stranded
  work) with the gates' and menard's deps installed; publish with `git push origin HEAD:refs/heads/<branch>`.
  Prune removes the ones whose work landed (clean, every commit on origin/main by patch) and says why the rest stay.
- Machine-wide scripts (`checks-queue.sh`, `release-smoke.sh`) act on state every checkout shares, so a
  checkout whose copy `origin/main` has changed since it branched is refused (exit 2, `scripts/lib/fresh-script.sh`):
  rebase onto origin/main; `TLON_STALE_SCRIPTS_OK=1` runs it anyway. A sandboxed `release:smoke` is refused too.
  `release:smoke` goes through `scripts/run-from-root.sh`, which runs the shared root checkout's (main's) copy, so a
  seat on an old base that has the wrapper still smokes with current tooling; one too old to have it needs a rebase.
- `mise run bench:*` — memory and role benchmarks that spend real quota: `docs/models.md`.
- `mise run house:build -- windows|mac|linux|all` / `house:art-pack` — the house for another machine, with the bought art packed inside it: written only to `~/.cache/tlon/house-dist/` (refused inside a git work tree), because the art's licence allows shipping it inside the app and forbids redistributing it, and this repo is public. `house/SHIPPING.md`.

On the home machine, installing and updating the service is ficciones' job (its `home:switch` and
`machine:update`); here you build and restart the release. mise owns the dev runtimes. **If a command belongs in the loop, it becomes
a task in `tasks/<group>.toml` (mise.toml includes them)** — never a prose instruction that drifts out of sync with what actually runs.

### Picking a model

Every agent runs in Claude Code; a seat's model is routed by the server (`Server.Profiles`), not chosen
in the seat. The launchers for your own sessions (`claude:balanced`, `claude:deep`, `claude:code`,
`claude:fast`, `claude:local`, `server:claude`, `claude:operator`), the two plan buckets and the model
gotchas are in `docs/models.md`.

### Run once, read the log — never re-run to see more

When you run a command whose output you'll inspect — a test suite, a build, a `scratchpad`
script — run it through **`mise run cap -- <cmd>`**. It runs the command
**once**, captures all output to a log under `.logs/`, and prints a lean summary: the exit code,
a test/build-summary line, failure lines on a non-zero exit, and a short tail — plus the exact
`tail`/`grep` to read more **from the saved log**. A red suite never reads green: a command that exits 0 while its own report
counts failures (`6 fail`, `Failed: 1 test`) is reported as failed, and every log ends `[cap] exit N`.
It runs in the directory you call it from; in another repo, call `scripts/cap.sh` by path.

The rule this enforces: **do not re-run a command with an escalating `grep … | tail -N` to see
more of its output.** The full output is already on disk — `grep`/`tail` the log. Re-running
burns tokens, re-streams noise into context, and risks a slightly-different invocation each time.

**Elixir tests and the gate go through Menard, not `cap`:** `~/projects/menard/bin/menard run test --in
server [FILE[:LINE]]` on what you changed; `~/projects/menard/bin/menard run check --in server` is a
coworker seat's, a session's full check is babylon's. One run answers with one JSON line: `ok` and the counts when green; when red, every
failure with its kind, `file:line` and message, a failing test's name, source and the assertion's
left and right. It is this section's rule with the failures already parsed out, so there is nothing
to grep for. `cap` stays the door for everything else: builds, scripts, `mise run server:eval-det`'s
evals.

Knobs: `CAP_TAIL=all|<n>`, `CAP_SIGNAL=<n>`.

### Let the watcher run the tests — don't spend a turn doing it by hand

When you're iterating on a change, **register a watcher instead of re-running tests yourself**:

- `mise run server:watch` / `mise run adapters:claude-code:watch` — re-run that module's suite on every change.
- `mise run watch -- <cmd>` — watch-and-run anything, any scope
  (one test file, a folder, the whole suite). New test files under a watched dir are picked up.

Run it **in the background** (this harness: `Bash` with `run_in_background` — you're re-invoked
with the result when the suite settles). Then just edit: you're pinged **red/green
automatically**, and you only spend a turn when something actually breaks. Kill the watcher when
the change is done.

### Edit Elixir with Menard, not sed/python/grep

Every Elixir edit and run goes through `~/projects/menard/bin/menard VERB …` (`edit`, `clause`, `block`,
`directive`, `run test|check|format`); `--help` on a verb shows its input. Menard's own `AGENTS.md` is the
reference for which verb fits which shape. `--frozen` runs the last build, for editing Menard with Menard.
Coworkers have the same verbs as tools scoped to their worktree (`edit_clause`, `rename_identifier`,
`outline_file`, `run_verb`). The `Edit` tool is for what Menard doesn't cover: TypeScript, Lua, Nix.
`run_verb` runs `test`/`compile` in the worktree's mix project — the root, else the one subdirectory
with a `mix.exs` (`server/`); pass `in: <dir>` to pick another. `check` is minutes, longer than one tool call
lives, so `run_verb` refuses it: commit, then `run_task("check")` runs the full gate off the seat and posts the result — green records the tree, so the verify after it on the same tree is a cache hit (`server:check` records nothing). `format` args are root-relative by default; with an explicit `in:`, `format` runs in that dir and its args are relative to it.

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
  distinct dev loop, or gotchas that bite (`server`, `adapters` + its adapters, `house`). Don't add one per
  folder by reflex — `lib/schemas/`, `test/`, etc. earn a file only once they accumulate a rule a
  weaker model keeps getting wrong; until then that guidance lives in the module's file. Keep every one
  terse and actionable to the same standard as comments: orientation, the exact commands, the law, the
  gotchas, a pointer to the one deeper doc — no lore. Skeleton: **what it is → Law → dev loop → Verify.**
  `find . -name AGENTS.md` lists them.
- **Keep docs in sync with the code, in the same commit.** A change that makes a module's `AGENTS.md`
  or a load-bearing comment stale updates it in that change — stale guidance is worse than none,
  because a weaker model trusts it. Nothing mechanical can catch this (staleness is semantic, invisible
  to compile/tests), so it's on you.
- **Commit each piece of work when it is done**: one commit per bug, feature or ticket, before
  you start the next, so `git log` says what changed and why.
- **History is linear.** GitHub's `main` requires linear history only (CI runs on release tags only). Rebase onto main, never merge it in,
  never make a merge commit. A session ships through babylon (the dev loop, above): its ticket branch is
  rebased and fast-forwarded onto main, with no PR. A PR that already exists is reviewed on tlon
  (`review_branch`; never the PR's author or a builder of the branch; each review on its own thread, in a
  session its verdict ends — never from the lobby) and queued with `mise run land -- <pr>`; GitHub merges
  only what the merge queue gated, at that head. A workline's approval lands its branch the same way — reviewed on its thread (never by its builder), rebased onto
  origin's main and gated (`Server.Workline.Merge`), then published: the branch pushed, a PR opened,
  `tlon/check` posted on the sha the gate passed, and merged at once at that head
  (`Server.Workline.Publish`). The checkout's own main is never moved by a landing; it only follows origin. Rewriting pushed history is
  the human's call — except a coworker's own thread branch: the server pushes `work/<slug>` for it,
  force-with-lease (the `push_branch` tool; with `branch: work/<your handle>-<name>` it pushes that
  named branch instead, for a seat with no thread branch such as Uqbar), and a coworker pane's own `git push` is refused
  (`scripts/git-hooks/pre-push`). The server also brings that branch onto origin/main for it (the
  `catch_up_branch` tool: a clean branch behind main fast-forwarded, one with its own commits rebased, a
  dirty or half-done checkout refused with why) — a seat's own `git rebase` dies on the bind-mounted
  `.claude/settings.json`.
- **Commit as who you are.** An agent's commit ends with a `Co-Authored-By:` trailer naming the model
  that wrote it — YOUR model, read from the brief's `You are … (Claude Code)` line, never a name copied
  from an example or another model's commit. Format: `Co-Authored-By: <your model> <noreply@anthropic.com>`
  on the Claude plan, `Co-Authored-By: <your model> <noreply@ollama.com>` on an ollama model.
  `git log` is part of the machine's memory; a commit that hides its author — or names the wrong one —
  lies to it.
  The server backs it mechanically: a pane it spawns carries `TLON_MODEL`, the model its seat was
  actually launched on, and `scripts/git-hooks/prepare-commit-msg` stamps it as `Tlon-Model:` on every
  commit (a review's commit too). It is the model as launched (a mid-session switch is not seen), so
  the record holds even when a model is wrong about itself.
- **Sandboxed Bash — phantom dotfiles and unreachable localhost are the sandbox, not the repo.** Claude
  Code's bash sandbox (a coworker's runs strict, from its profile's `sandbox.json`) has four
  symptoms, and none is a bug to chase:
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
  - *A `.git/config.lock` that comes and goes.* Each sandboxed command write-protects `.git/config` by
    binding `/dev/null` over `.git/config.lock`, which creates that 0-byte file for as long as the command
    runs and deletes it after; every session's sandboxed commands do it at once. While one exists, a git
    config write (`worktree add -b`, `switch -c`, `push -u`) fails "File exists" — work detached and push
    `HEAD:refs/heads/<branch>`. A launch that races another's teardown fails "bwrap: Can't find source path
    …/.git/config.lock": run it again. Never create or `rm` the file — except a lock with no sandbox running
    that is older than a few minutes is stale, and the operator removes it (`server:doctor` names it).
  - *`git fetch origin` over SSH is refused.* The sandbox read-denies `~/.ssh/*`, so a fetch dies on
    `~/.ssh/known_hosts: Permission denied`. The checkout fetches over HTTPS instead (the repo is public) and
    pushes stay on SSH: `server:setup` sets `url."https://github.com/".insteadOf git@github.com:` and
    `url."git@github.com:".pushInsteadOf git@github.com:` in the shared `.git/config`, `server:doctor` reports
    when either is missing, and a bare clone sets the two lines by hand. Never set them from a seat (the
    config.lock mount above). The `.gitmodules: Permission denied` warning is the 0-byte `/dev/null` phantom,
    the same family as the dotfiles.

- **Comments earn their place — load-bearing only.** A comment survives only if it states a non-obvious
  *why* or a real gotcha the code can't. Narrative, lore, dated incident references, decorative
  `# --- section ---` dividers, and restatements of what the next line plainly does are noise — don't
  write them, and trim them when you touch a file. Prose belongs in docstrings (`@moduledoc`/`@doc`/
  `@spec`, JSDoc) and the `*.md` files; inline comments are load-bearing only.
  - **No devlog.** A comment describes what IS, never how it got here. Cut the evolution storytelling:
    *"used to X / now Y instead"*, *"supersedes / replaces / reverses the old…"*, *"the bug this
    replaces was…"*, *"before the fix / pre-B1.4"*, rename & migration history, "we tried X then…".
    Keep the current-state constraint even when it grew out of a past bug — just state the constraint,
    drop the incident. The git history holds the story; the code holds the present.
- **Secrets come from the machine.** tlon reads keys from the env or
  `$XDG_RUNTIME_DIR/agenix/<name>` (mise.toml's `OLLAMA_API_KEY`); it never stores one. Never a
  plaintext key in the repo.

## Verify

`mise run check` is the gate; babylon runs it once per session's change, at `submit_ticket`, and a session
runs the targeted tests of what it changed. `mise run check:names` is the names-exist gate: every
`Server.*` module, mix task and mise task that scripts, `mise.toml`, the adapters or a
guide name must actually exist — a rename that strands a reference fails here instead of at 2am. The same task holds
`docs/glossary.md` — one meaning per noun; its "lives in" names must exist and its retired words stay out of
AGENTS.md, and `docs/manual/tasks.md` must match the task descriptions: a change under `tasks/`
or to `mise.toml` runs `check:names` before submitting, and `mise run manual:gen` fixes a drift. A
claim that something works is backed by the command that proved it — and the agent and human run the
*same* `mise` tasks, so "it works" means the shared task passed, not two private ones.
