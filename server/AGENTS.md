# funes

**Read `docs/spec.md` before writing anything.** It is the specification this repository exists to
implement, every rule in it names the failure that paid for it, and it was reviewed adversarially twice
(`docs/spec-review.md`, `docs/v1-review.md`). If something here contradicts the spec, the spec wins; if
the spec is wrong, say so and change it in the same commit as the code that proves it.

## What to build, in order

The build order is the aleph doc's **re-laid §9** (`../../docs/plans/2026-08-14-aleph-cockpit-and-elixir-spine.md`),
which supersedes `docs/spec.md` §9's ordering: the thread/channel is the spine and moves up, so it is
db+doctor → thread+message → agent → the dossier → the board → collectors. Step one is still the database
plus `funes doctor`: **nothing ships that cannot be repaired at 2am** — schema, migrations,
`integrity_check`, JSONL export. Do not skip ahead to a later step because it is more interesting.
**Steps 1–3 are built and green in Elixir:**

- **Step 1** — Ecto over `ecto_sqlite3`, the `collection` migration, `Funes.Doctor` (integrity_check,
  tables, pending migrations, JSONL export), and `mix funes.doctor`. The §4 write contract is re-verified
  on `exqlite`: WAL and foreign keys via PRAGMA, and a **bounded busy_timeout proven by a contention test**
  (exqlite sets it through a NIF, not `PRAGMA busy_timeout`, so a held-lock timing test is the only honest
  probe).
- **Step 2** — `thread` + `message` (`Funes.Channel`): the atom of work and the channel/§4 capture path,
  with `delivered` a separate column from `read` and a sender who cannot fake delivery (§5b.3).
- **Step 3** — `agent` + `session` and staffing (`Funes.Staff`): the durable named identity and its
  ephemeral instance (aleph §3), a thread's `agent_id`, and the opaque `pane_ref` the arbiter jumps
  into. This is the recipient model step 2 deferred its PubSub wake to await.
- **Step 4** — the dossier: `fact`/`event`/`issue` scoped to threads (`Funes.Dossier`) →
  `LEARNINGS`/`SHIPPED`/`BLOCKERS`. `fact` is the ledger's successor with `provenance` (stated | derived,
  the DB CHECKs it), a separate reproducibility axis `check_cmd`, and explicit `supersedes`; `event` is
  append-only with a closed `kind` that includes the `work_landed` outcome; `issue` is a local,
  ticket-shaped finding read capped-and-counted by `open_issues_for_thread` (§5's acceptance test).

- **The switchboard** (`Funes.Switchboard` + `Funes.Bus` + `Switchboard.Server`, `Funes.Arbiter`,
  `Funes.Mentions`) — the liveness layer step 2 deferred. Delivery WAKES the recipient (§5b.2): a posted
  message is broadcast over `Phoenix.PubSub` and the switchboard pokes **who the message is addressed to** —
  the thread's **lead** for a plain post, an **@mentioned** coworker, or a **reply's** author — through the
  **arbiter, a capability not a product** (Herdr | tmux, §8) that defaults to `Inert`. §10 holds: the message
  is a durable row before any wake, and `drain/0` re-delivers on restart, so killing the BEAM loses nothing.
  Three guard-rails against burning a five-hour window: the wake is **coalesced** (a backlog is one nudge,
  not N); **warmth-gated** — a **cold** session (idle past the ~1h prompt-cache window, `last_active_at`) is
  never poked, the "resumed a thread and burned my allotment" footgun; and the default arbiter is **inert**,
  so nothing real is poked until a backend is deliberately wired.

- **The MCP channel** (`Funes.MCP.*` — Track B slice 1, pi doc §2a/§5.1): funes' sovereign channel to
  any agent, over `anubis_mcp` + Bandit (loopback-only, opt-in via `:start_mcp`). Identity rides the
  CONNECTION — an in-node token (`Funes.MCP.Tokens`) resolves to (thread, agent, session) claims on
  every request, so no tool takes a thread parameter and every authenticated call bumps warmth through
  `Staff.touch_sessions` (measured, never a heartbeat). Tools are thin context callers: register
  (supersedes the zombie), post_message, bank_fact (derived by default; STATED only by quoting the
  operator's own message verbatim via `Dossier.bank_stated_fact`), raise_issue, record_done (evidence
  required), get_dossier/get_facts/get_messages rendered through `Funes.MCP.Brief` (read-time
  certainty stated > checked > opinion, caps with counts). The dossier and always-loaded constraints
  are also MCP resources — same reads, second door. Proven end-to-end by a raw JSON-RPC client, not
  the anubis client.

Change the build-order status line above as each step lands — do not leave it asserting a step that is
already built (the trap the step-2 handoff caught here). Track B slices 1–2 (the MCP channel, the pi
adapter) and capability-map moves #1–#3 (funes-as-a-service, the mise parity pack, the claude-code
adapter) are built. **The `todo` slice (pi doc §5 slice 3) is built**: `todo` (thread-scoped, `done_at`
from birth), `add_todo`/`complete_todo` (complete refuses another thread's step), and the dossier's
TODOS / NEXT (derived, first open) / DONE (a MERGED view — completed todos + `work_landed`, replacing the
old SHIPPED-only pane), rendered in both `Funes.MCP.Brief` and the pi `brief.ts`; the `keep-todos-current`
skill. **The `question` slice (pi doc §5 slice 4) is built too**: `question` (`resolved_at` from birth,
`state` open/resolved), `raise_question`/`resolve_question` (resolve refuses another thread's; resolution
optional, a durable answer is `bank_fact`'d), and the dossier's UNKNOWNS beside FACTS — rendered in all
three surfaces. **Measured verification (capability-map #5) is built too**: `record_check(cmd, exit, tail)`
→ a `check_passed`/`check_failed` event keyed on the real exit code, a CHECKS dossier pane, and the
`verify-with-evidence` skill — "it works" is measured, not self-reported. **Next is the arbiter bootstrap
(pi doc slice 5)** — env-in-spawn automated (§2d). The aleph board (step 5) has its first live cockpit; its
build order lives in the aleph docs. Deferred
still: the **engine-credit half of presence** (clocked-out from spent credits/rate-limit — combine into
`recipients/1` before an auto-poking backend replaces `Inert`), the human-notification path + re-deliver
on session-join, cross-thread **mentions**, and the `Sense` collectors. SQLite is the truth — a real db
reads back under `sqlite3`.

Version one ran on the *work* machine and is **not on this clean-room box** (§8c). It is **evidence, not
a source**: it exists to show what a failure looked like, never to copy a shape. Nothing here needs to be
backwards compatible with it.

## Public surface

funes' public API *is* its boundary: the `exports:` list in `lib/funes.ex` (`use Boundary`). That
annotated list — `Channel` (threads/messages/chorus), `Board`/`Staff`/`Dossier`/`Presence` (read
models), `Doctor`, `MCP.Spawn`, `Arbiter`, `Thread`/`Message` (structs) — is the whole surface a
consumer (aleph, an MCP adapter) may call, machine-enforced: reach a non-exported module and the
`:boundary` compiler fails the build. Each export is a context whose functions carry `@doc`s — call
`Funes.<Context>.<fun>` (e.g. `Funes.Dossier.raise_issue/1`, `Funes.Channel.machine_thread/0`). To
find one, read the context module or `h Funes.Dossier.raise_issue` in `iex -S mix` — the `@doc`s are
the reference. Don't grep for it, and don't copy it into a hand-maintained doc that would drift.

## The rules most likely to be broken by accident

- **When two things can answer the same question, delete one.** Three defects in one day were "two
  sources of truth where the untested one was in the live path".
- **Ask the arbiter whose output contains the field you care about.** A test that reads our own files
  proves only that we were consistent. `herdr config check` said `config: ok` about a stale registry
  and `herdr plugin list` printed neither the version nor the actions that had diverged.
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
  Typing is only inert where `herdr pane process-info` proves a shell is in the foreground.

## The dev loop

Drive everything through the shared mise tasks (`mise tasks` lists them) — the human and any agent use
the same commands, which is the one control loop §3 asks for:

- `mise run funes:test` — the ExUnit suite (`mix test`).
- `mise run funes:check` — the **precommit gate**: `mix precommit` = format-check + warnings-as-errors +
  `credo --strict` + the suite (runs in `:test`). Same alias a git pre-commit hook would call.
- `mise run funes:setup` — deps + create/migrate the repo-local scratch db (run once).
- `mise run funes:doctor` — `mix funes.doctor` against the scratch db, never the real one.
- `mise run check` — the funes precommit gate, the green-before-commit gate.

The **always-up channel** is a headless service, distinct from the `funes:serve` dev iex:
a self-contained local `mix release` run by `systemd.user.services.funes` (flake.nix) —
loopback, the **real XDG db**, migrate-on-boot (`Funes.Release.migrate/0` via
`bin/funes eval`, so funes never serves on a schema it can't repair), and a named node +
cookie (the release's `rel/env.sh.eex`) so the operator can reach the live node:

- `mise run funes:release` — build the release the service runs.
- `mise run funes:restart` — rebuild + restart the service (redeploy a funes change).
- `mise run funes:console` — remote iex INTO the running service node; the only place a
  token minted by `Funes.MCP.Spawn.env` survives (the `Tokens` registry dies with its node).
- `mise run funes:logs` — follow the service's journal.

The **mise parity pack** — operate the live channel from the shell, our peer to the
agents' MCP tools (all via `scripts/funes-cli.sh` → `bin/funes rpc` into the running node,
so the service must be up):

- `mise run funes:spawn -- "<title>" <agent>` — open a thread, staff+register the agent,
  mint a token, print the `export FUNES_*` block for a pi pane (the human-arbiter path).
- `mise run funes:roster` — who's on the clock (live sessions, warm/cold).
- `mise run funes:dossier -- <thread-id>` — render a thread's brief (parity with get_dossier).
- `mise run funes:post -- <thread-id> <text…>` — post as the operator (parity with post_message).

The `home:switch` that installs the service is the human's (system-mutating); build + verify
the release with `funes:release` and `nix build .#homeConfigurations.personalbox.activationPackage`.

If a command belongs in the loop, it becomes a task in the root `mise.toml`. Do not invent a second way
to run these.

## Verify

Built test-first (RED before GREEN), and a claim that something works is backed by having run it — the
spec exists because "it works" without running it happened repeatedly in version one. `mise run check`
is the gate; `funes doctor` against a real db, read back with `sqlite3`, is the 2am proof.
