# server

**Read `docs/spec.md` before writing anything.** It is the specification this module exists to
implement, every rule in it names the failure that paid for it, and it was reviewed adversarially twice
(`docs/spec-review.md`, `docs/v1-review.md`). If something here contradicts the spec, the spec wins; if
the spec is wrong, say so and change it in the same commit as the code that proves it.

## What is here

The spine of Tlön: SQLite is the truth (a real db reads back under `sqlite3`), Ecto over `ecto_sqlite3`,
and every layer the console doc's re-laid §9 asked for
(`../../docs/plans/2026-08-14-console-cockpit-and-elixir-spine.md`) is built and gated:

- **db + doctor** — the schema (`priv/repo/migrations/`), `Server.Doctor` (integrity_check, tables,
  pending migrations, JSONL export), `mix server.doctor`. The §4 write contract holds on `exqlite`: WAL
  and foreign keys via PRAGMA, and a bounded busy_timeout proven by a contention test (exqlite sets it
  through a NIF, not `PRAGMA busy_timeout`, so a held-lock timing test is the only honest probe).
  **Nothing ships that cannot be repaired at 2am.**
- **thread + message** (`Server.Channel`) — the atom of work and the channel/§4 capture path.
  `delivered` is a separate column from `read`, and a sender cannot fake delivery (§5b.3). A thread is
  born with a lead (`designated_lead/1`, the workspace roster's first builder) — the lead invariant.
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
  arbiter behaviour the host implements (the console's tmux arbiter). Coalesced (a backlog is one
  nudge), warmth-gated (a cold session is rotated onto a fresh, brief-seeded one, never poked), and
  `drain/0` re-delivers on restart, so killing the BEAM loses nothing.
- **the MCP channel** (`Server.MCP.*`) — the sovereign door for any agent, `anubis_mcp` over Bandit,
  loopback-only. Identity rides the CONNECTION: a signed token resolves to (thread, agent, session) on
  every request, so no tool takes a thread parameter and every authenticated call bumps warmth. Tools
  (`mcp/tools/*.ex`, each `use Server.MCP.Tool`) are thin context callers; reads render through
  `Server.MCP.Brief` (certainty stated > checked > opinion, caps with counts); the dossier is also a
  resource. `record_check` lands a measured exit code, never a self-report.
- **worklines** (`Server.Workline`) — a thread as a stage machine with git as the artifact chain
  (`Workline.Scribe`, `Workline.Artifacts.Git`), gates, the ledger, per-thread `Server.Worktree`s.
- **recall + forgetting** (`Server.Recall`, `Server.Search`) — the budgeted always-loaded set.
- **seed + bootstrap** (`Server.Seed`, `Server.Bootstrap`) — the wipe-proof base knowledge
  (`priv/seed/repo_knowledge.exs` + the machine-appended `promoted_facts.exs`) and the default
  workspace, applied idempotently on every boot.
- **the steering evals** (`Server.Eval`, `evals/`) — scenarios over the briefs and playbooks,
  deterministic ones in the gate, judged ones in `mise run server:eval`.

Still deferred: the engine-credit half of presence (clocked-out from spent credits/rate-limit), the
human-notification path, cross-thread mentions, and the `Sense` collectors.

Version one ran on the *work* machine and is **not on this clean-room box** (§8c). It is **evidence, not
a source**: it exists to show what a failure looked like, never to copy a shape. Nothing here needs to be
backwards compatible with it.

## Public surface

The module's public API *is* its boundary: the `exports:` list in `lib/server.ex` (`use Boundary`).
That annotated list is the whole surface a consumer (the console, an MCP adapter) may call,
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

- `mise run server:release` — build the release the service runs.
- `mise run server:restart` — rebuild + restart the service (redeploy a server change).
- `mise run server:console` — remote iex INTO the running service node.
- `mise run server:logs` — follow the service's journal.

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
