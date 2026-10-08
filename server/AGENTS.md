# server

**Read `docs/spec.md` before writing anything.** It is the specification this module exists to
implement, every rule in it names the failure that paid for it, and it was reviewed adversarially twice
(`docs/spec-review.md`, `docs/v1-review.md`). If something here contradicts the spec, the spec wins; if
the spec is wrong, say so and change it in the same commit as the code that proves it.

## What is here

The spine of Tlön: SQLite is the truth (a real db reads back under `sqlite3`), Ecto over `ecto_sqlite3`,
and every layer the spine design's re-laid §9 asked for
(`../../docs/plans/2026-08-14-console-cockpit-and-elixir-spine.md`) is built and gated:

- **db + doctor** — the schema (`priv/repo/migrations/`), `Server.Doctor` (integrity_check, tables,
  pending migrations, JSONL export), `mix server.doctor`. The §4 write contract holds on `exqlite`: WAL
  and foreign keys via PRAGMA, and a bounded busy_timeout proven by a contention test (exqlite sets it
  through a NIF, not `PRAGMA busy_timeout`, so a held-lock timing test is the only honest probe).
  **Nothing ships that cannot be repaired at 2am.**
- **thread + message** (`Server.Channel`) — the atom of work and the channel/§4 capture path.
  `delivered` is a separate column from `read`, and a sender cannot fake delivery (§5b.3). A thread is
  born with a lead (`designated_lead/1`, the workspace's manager) — the lead invariant.
- **agent + session + staffing** (`Server.Staff`) — the durable named identity and its ephemeral
  instance; warmth is measured from `last_active_at`, never a heartbeat.
- **the dossier** (`Server.Dossier`) — `fact` (provenance stated | derived, CHECKed by the db;
  `check_cmd` as a separate reproducibility axis; `supersedes`; `forgotten_at` tombstones), append-only
  `event` with a closed `kind`, `issue`, `todo`, `question`, `habit`. Read capped-and-counted.
- **the container tier** — `Server.Workspaces` (roster + paths), `Server.Projects` (repos),
  `Server.Tickets`, `Server.Notes`.
- **the switchboard** (`Server.Switchboard` + `Server.Bus` + `Server.Arbiter`) — delivery WAKES the
  addressee (§5b.2): a posted message is a durable row first, then broadcast over `Phoenix.PubSub`, and
  the switchboard pokes the thread's lead / the @mentioned coworker / a reply's author through the
  arbiter behaviour (`Server.Arbiter.Tmux`). Coalesced (a backlog is one
  nudge), warmth-gated (a cold session is rotated onto a fresh, brief-seeded one, never poked), and
  `drain/0` re-delivers on restart, so killing the BEAM loses nothing. A wake its addressee never
  acted on (no call to the server since) is offered again for 30 minutes (`redeliver_unheard/1`).
- **the MCP channel** (`Server.MCP.*`) — the sovereign door for any agent, `anubis_mcp` over Bandit,
  loopback-only. Identity rides the CONNECTION: a signed token resolves to (thread, agent, session) on
  every request, so no tool takes a thread parameter and every authenticated call bumps warmth. Tools
  (`mcp/tools/*.ex`, each `use Server.MCP.Tool`) are thin context callers; reads render through
  `Server.MCP.Brief` (certainty stated > checked > opinion, caps with counts); the dossier is also a
  resource. `record_check` lands a measured exit code, never a self-report.
- **worklines** (`Server.Workline`) — a thread as a stage machine with git as the artifact chain
  (`Workline.Scribe`, `Workline.Artifacts.Git`), gates, the ledger, per-thread `Server.Worktree`s;
  entering verify queues the verifier on the service (`Server.Jobs.Verify`); approving review queues
  the landing (`Server.Jobs.Land`, one at a time, rebased onto origin's main and gated there — red bounces to build; GitHub merges it).
  An approved review of a change Andrew sees (`office/`, the operator API) goes to the bench's `qa`
  seat first: it drives the branch on a scratch release and files `submit_qa`; a fail bounces it to
  build with the finding, and nothing lands past an owed QA (`Server.Workline.qa_verdict/5`).
  An approving review is risk-graded by a model that didn't write it (`Server.Workline.Grade`, run by
  `Server.Jobs.Grade`): script limits first, then five axes; under the operator's `auto_land_risk` it
  lands without them.
  Red — a red verify, a bounce, a stuck workline, a failed schedule run — goes to the workspace's
  sheriff (`Server.Sheriff`, bench archetype `sheriff`) on its beat thread, not the operator's list;
  a beat incident resolved naming its PR is banked as a `postmortem:` fact.
- **the PM** (`Server.Release.PM`, bench archetype `pm`) — what ships: `release_status`,
  `propose_release` (graded commit by commit with `Grade.assess/2`, the max per axis; under
  `auto_land_risk` it cuts, else one gate on the root thread — a window-less `prompt` answered through
  `Attention.respond/3`), the changelog posted and recorded as event `release:<sha>`, and
  `set_urgency` on the backlog. Work runs in `Server.Jobs.Release`; tests hand it a repo (`:release_root`).
- **the calendar** (`Server.Schedules`) — agent runs, worklines and scripts on a cron or once, fired by
  a per-minute dispatcher (`Server.Jobs.Dispatch`, OSS Oban having no dynamic cron); each firing a
  `schedule_run` row (the automation board); a script's `ran-on: <check> <sha>` line records the commit
  it checked, which `Server.Release.Candidate` reads. Crons read the server's local clock.
- **feature flags** (`Server.Flags`) — `fun_with_flags` on the store's Postgres, each node's cache
  busted over `Server.PubSub` (no Redis, no restart): work that lands dark ships behind a flag the
  server names, off; the office gets every flag in its snapshot. Flip one with
  `mise run server:cli -- flag <name> on|off` or `PATCH /api/flags/:name`.
- **recall + forgetting** (`Server.Recall`, `Server.Search`) — the budgeted always-loaded set.
- **seed + bootstrap** (`Server.Seed`, `Server.Bootstrap`) — the wipe-proof base knowledge
  (`priv/seed/repo_knowledge.exs` + the machine-appended `promoted_facts.exs`) and the default
  workspace, applied idempotently on every boot.
- **the steering evals** (`Server.Eval`, `evals/`) — scenarios over the briefs and playbooks,
  deterministic ones in the gate, judged ones in `mise run server:eval`.

Still deferred: the engine-credit half of presence (clocked-out from spent credits/rate-limit), the
human-notification path, and the `Sense` collectors. (A mention of a coworker who isn't on the
thread reaches them in their window on the workspace's standing thread; they answer with
`consult_peer`.)

Version one ran on the *work* machine and is **not on this clean-room box** (§8c). It is **evidence, not
a source**: it exists to show what a failure looked like, never to copy a shape. Nothing here needs to be
backwards compatible with it.

## Public surface

The module's public API *is* its boundary: the `exports:` list in `lib/server.ex` (`use Boundary`).
That annotated list is the whole surface a consumer may call,
machine-enforced: reach a non-exported module and the `:boundary` compiler fails the build. Each
export is a context whose functions carry `@doc`s — call `Server.<Context>.<fun>` (e.g.
`Server.Dossier.raise_issue/1`, `Server.Channel.machine_thread/0`). To find one, read the context
module or `h Server.Dossier.raise_issue` in `iex -S mix` — the `@doc`s are the reference. Don't grep
for it, and don't copy it into a hand-maintained doc that would drift. Widening the surface is a
one-line diff in that file, on purpose.

## The rules most likely to be broken by accident

- **When two things can answer the same question, delete one.** Three defects in one day were "two
  sources of truth where the untested one was in the live path".
- **Ask the tool whose output contains the field you care about.** A test that reads our own files
  proves only that we were consistent — ask `tmux` what windows exist, ask `git` what the branch is.
- **A field computed at write time is not a fact at read time.** Compute age, staleness and counts in
  the query.
- **A cache that reports an empty world is a lie.** A collector that cannot collect writes nothing and
  says so — and an empty derived scope is never a licence to show everything.
- **Never invent a duration.** A log entry is a stamp, not a clock-in.
- **A measurement that returns nothing must be proven capable of returning something.** A false zero
  from a wrong key reads exactly like a real zero, and one of those got into the spec.
- **Rank and cut every surface.** Complete is not the same as useful; the count of what was set aside
  is the honest way to omit it.
- **No provider, model or vendor is part of the design.** They are configuration. A role states a
  capability requirement — "not the weights that wrote this", "long context", "cheap per turn" — and the
  mapping to an endpoint is local. Local models are first-class, and anything that assumes a frontier
  model must degrade honestly rather than break. The same goes for credentials: how this machine
  authenticates is local configuration and no code here may know which mechanism it is.
- **In production, Andrew presses Enter.** Prefill the exact reviewed text in a visible pane and stop.
  Typing into a pane is only inert where the pane is proven to have a shell in the foreground.

## The dev loop

Drive everything through the shared mise tasks (`mise tasks` lists them) — the human and any agent use
the same commands, which is the one control loop §3 asks for:

- `mise run server:test` — the ExUnit suite (`mix test`).
- `mise run server:check` — the **precommit gate**: `mix precommit` = format-check + warnings-as-errors +
  `credo --strict` + the suite (runs in `:test`), then the deterministic evals.
- `mise run server:setup` — deps + create/migrate the repo-local scratch db (run once).
- `mise run server:doctor` — `mix server.doctor` against the scratch db, never the real one.
- `mise run server:serve` — the dev iex with the MCP channel up, against the scratch db.
- `mise run check` — every module's gate, the green-before-commit gate.

The **always-up channel** is a headless service, distinct from the `server:serve` dev iex: a
self-contained local `mix release` run by `systemd.user.services.tlon` (flake.nix) — loopback, the
**real XDG db**, migrate-on-boot (`Server.Release.migrate/0` via `bin/server eval`, so it never serves
on a schema it can't repair), and a named node + cookie (`rel/env.sh.eex`) so the operator can reach
the live node:

- `mise run server:release` — build the release the service runs, in `.release/` at the release pointer.
- `mise run release:cut` — ship: move the pointer to origin/main (or a commit on it), build, restart once quiet. A merge to main alone deploys nothing.
- `mise run release:smoke -- [<sha>]` — the candidate as a scratch release on :4047 and db `tlon_smoke` (never 4040 or `tlon`): `/api/office`, then the office driven headless; torn down after (`TLON_SMOKE_HOLD=1` keeps a passing node up to drive, as QA does). `TLON_NODE` names its node beside `funes@`.
- `mise run server:restart` — rebuild + restart the service (redeploy a server change). It refuses
  while a restart would cut work off (a coworker mid-turn, a verify or a landing running —
  `Server.Rollout.busy/0`); `-- --force` restarts anyway.
- `mise run server:console` — remote iex INTO the running service node.
- `mise run server:logs` — follow the service's journal.

The **standalone binary** is the same release for a box with no unit file (a Mac, say):
`mise run server:package` wraps the `tlon` release with Burrito into `burrito_out/tlon_<target>`
(Linux and macOS, x64 and arm64; ERTS inside, exqlite rebuilt per target). Run with no arguments
it migrates and serves until signalled (`Server.Standalone`), every `TLON_START_*` defaulting on as
the service sets them; it still needs Postgres (`PGHOST`, else `/tmp` on macOS) and tmux.
`tlon office` is the office TUI from the same file: the launcher's plugin (`rel/burrito/plugin.zig`)
carries that target's TUI (staged by `Server.Package.Office`) and execs it before the VM starts,
so it has the real terminal. Each build's version carries its commit, because Burrito reuses an
unpack named by version. `burrito` is build tooling (`runtime: false`): nothing ships it.

The **shell parity pack** — operate the live channel from the shell, our peer to the agents' MCP tools
(all via `scripts/tlon-cli.sh` → `bin/server rpc` into the running node, so the service must be up):

- `mise run server:spawn -- "<title>" <agent>` — open a thread, staff+register the agent, mint a
  token, print the `export TLON_*` block for a pi pane.
- `mise run server:roster` — who's on the clock (live sessions, warm/cold).
- `mise run server:dossier -- <thread-id>` — render a thread's brief (parity with get_dossier).
- `mise run server:post -- <thread-id> <text…>` — post as the operator (parity with post_message).
- `mise run server:cli -- <subcommand>` — everything else the CLI knows (worklines, approve, …).

The `home:switch` that installs the service is the human's (system-mutating); build + verify the
release with `server:release`, and on the home machine with ficciones' `flake:check`.

If a command belongs in the loop, it becomes a task in the root `mise.toml`. Do not invent a second way
to run these.

## Verify

Built test-first (RED before GREEN), and a claim that something works is backed by having run it — the
spec exists because "it works" without running it happened repeatedly in version one. `mise run
server:check` is the gate; `server doctor` against a real db, read back with `sqlite3`, is the 2am proof.
