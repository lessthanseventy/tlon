# server

**Read `docs/spec.md` before writing anything.** It is the specification this module exists to
implement, every rule in it names the failure that paid for it, and it was reviewed adversarially twice
(`docs/spec-review.md`, `docs/v1-review.md`). If something here contradicts the spec, the spec wins; if
the spec is wrong, say so and change it in the same commit as the code that proves it.

## What is here

The spine of Tlön: Postgres is the truth (a real db reads back under `psql`), Ecto over `postgrex`,
and every layer the spine design's re-laid §9 asked for
(`../../docs/plans/2026-08-14-console-cockpit-and-elixir-spine.md`) is built and gated:

- **db + doctor** — the schema (`priv/repo/migrations/`), `Server.Doctor` (integrity_check, tables, an
  `erl_crash.dump` at the tlon root read against the service's start, pending migrations, JSONL export),
  `mix server.doctor`. The store is Postgres (`Server.Repo`): foreign keys live in the schema, and
  `integrity_check` proves the store reachable by counting its relations. `exqlite` is left only for
  `mix server.import_sqlite`, the one-time import from the old SQLite file.
  **Nothing ships that cannot be repaired at 2am.**
- **thread + message** (`Server.Channel`) — the atom of work and the channel/§4 capture path.
  `delivered` is a separate column from `read`, and a sender cannot fake delivery (§5b.3). A thread is
  born with a lead (`designated_lead/1`, the workspace's manager) — the lead invariant. The manager
  never leads a workline: `assign_lead/2` refuses it, and promoting a manager-led thread restaffs it
  (a free builder, else a hire) or, with no builder on the bench, leaves it unled.
- **shifts** (`Server.Shifts`) — crews on one bench, as many as the operator names (an account, a
  provider, a time of day): a seat is on one crew or on `all` (the default, so a bench with no
  crews is unchanged); `Workspaces.bench/1` is the crew on plus `all` (`bench_all/1` everyone), so
  staffing picks only from it. A switch restaffs the going crew's worklines the workline's own way;
  their plain threads wait for them. Nothing switches by itself: Claude's usage limit on a pane
  offers the other crews in the lobby, and a taken offer offers the way back at the reset.
- **pause** (`Server.Pause`) — the office's stop controls, in the settings file's `"pause"` key so a
  restart keeps them: pencils down (intake and continuation nudges off, every live thread told to
  finish its turn, commit and stop, as a notice; the calendar's agent and workline schedules wait,
  firing once back at work, but for the operator's delegate's, `Server.Outside`), lights out (that, plus the verify and landing
  queues paused — a boot under it starts them paused — and an Escape into every coworker pane),
  back to work (every still-open thread pencils down stopped woken: a chat @mentioning its lead as it
  is now). `POST /api/office/pause`, `tlon-cli pause`, the office's finder.
- **agent + session + staffing** (`Server.Staff`) — the durable named identity and its ephemeral
  instance; warmth is measured from `last_active_at`, never a heartbeat.
- **the two "gone quiet" clocks** — they mean different things; never read a third number for either.
  The *stale turn* (`Server.Presence.Thinking.stale_turn_seconds/0`, `config :server,
  :stale_turn_seconds`, 600 s): a turn nothing has been heard from this long (its declare or its
  latest `presence_doing`) is a turn nothing will end; the thinking sweep clears it, and staffing and Needs stop counting it as someone at work. The *quiet
  workline* (the settings knob `quiet_workline_minutes`, 60): a workline that has not moved this long
  gets a Maintain nudge and is a `stalled` Need. Other bands are not "stale": staffing's boot grace (a
  window still booting) and Maintain's gate/stall bands (`Server.Maintain.Sweep`).
- **outside citizens** (`Server.Outside`) — agents seated on no bench, like `uqbar`, the operator's
  delegate: they post as themselves. Uqbar leads one thread of its own, its study (`Outside.study/1`),
  where a post spawns its pane on its citizen profile (`Profiles.citizen_profile/2`: the Claude plan,
  unsandboxed, started in the repo's main checkout); the study is a duty, so it takes no coworker's seat.
  Every boot ensures its check-in (`Outside.ensure_checkin/1`), so the study exists from the first boot
  with uqbar registered, before anyone has talked to it; a closed study is reopened, never replaced.
  The operator hands it an ask (`Attention.hand_to_uqbar/2`, `POST /api/office/prompts/:id/uqbar`, `u` on
  an ask in the office): one post as the operator on its study, the ask resolved `handed to uqbar`.
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
  One seat, one session: spawning a window first SIGTERMs any process still holding that
  (thread, handle) identity in its environment (`Server.Orphans`), so a killed window's survivor
  cannot drain wakes beside the respawn.
- **the MCP channel** (`Server.MCP.*`) — the sovereign door for any agent, `anubis_mcp` over Bandit,
  loopback-only. Identity rides the CONNECTION: a signed token resolves to (thread, agent, session) on
  every request, so no tool takes a thread parameter and every authenticated call bumps warmth. Tools
  (`mcp/tools/*.ex`, each `use Server.MCP.Tool`) are thin context callers; reads render through
  `Server.MCP.Brief` (certainty stated > checked > opinion, caps with counts); the dossier is also a
  resource. `record_check` lands a measured exit code, never a self-report.
- **worklines** (`Server.Workline`) — a thread as a stage machine with git as the artifact chain
  (`Workline.Scribe`, `Workline.Artifacts.Git`), gates, the ledger, per-thread `Server.Worktree`s;
  entering verify queues the verifier on the service (`Server.Jobs.Verify`), which bounces a diff
  that adds a file at the repo root or touches another workline's `work/<slug>/` before any gate; approving review queues
  the landing (`Server.Jobs.Land`, one at a time, rebased onto origin's main and gated there — red bounces to build; green posts the commit status `tlon/check`, main's required check, on the sha it gated (`Workline.Publish.publish/5`); GitHub auto-merges it, and only then,
  read by `Server.Jobs.KeepUp`, does its thread close and its ticket count as done: `Workline.merged/2`;
  one GitHub isn't merging — auto-merge refused, `BLOCKED` with no check running, an hour gone — is a
  `pr_blocked` Need, answered by rebase, close and reland, or a look at the PR).
  An approved review of a change Andrew sees (`office/`, the operator API) goes to the bench's `qa`
  seat first: it drives the branch on a scratch release and files `submit_qa` (with the workline's
  `thread_id`, which only a `qa` seat on its bench may name — its session may be bound elsewhere); a fail bounces it to
  build with the finding, and nothing lands past an owed QA (`Server.Workline.qa_verdict/5`) but the
  operator's `approve <id> --skip-qa <why>` (API `{"skip_qa"}`), recorded as its QA verdict.
  The operator reviews a branch from the office (`Server.Workline.OperatorReview`): its diff as
  files, hunks and numbered lines, and notes on lines or files submitted with a verdict — comment,
  request changes (`send_back/4` to build, the notes its why) or approve — reaching the lead as one
  post in revdiff's shape (`## path:line (+) note`).
  A workline moves backwards on its own thread and branch, the build kept to improve, never redone
  (`Server.Workline.send_back/4`, the `send_back` tool, `tlon-cli send-back`): back to build by its
  lead, back to plan or spec only by the tech lead (a coherence call) or the operator; an open one
  only, never while its verify or landing is queued or running. A reviewer's or QA's non-blocking
  findings are `follow_ups` on `submit_review`/`submit_qa`: tickets tied to the workline, `held`
  until its thread closes, then left to intake (one closed unmerged says so in each ticket).
  No one reviews their own work: a verdict by the agent that built the branch (the git author or
  `Tlon-Author:` of a commit on it past main, its review.md aside) is refused (`Workline.self_review/2`).
  A review approves the code it read: its verdict records the branch's commit, and code committed
  after it (its own `work/<slug>/` docs aside) sends the workline back to build at approval or at its
  landing, never landing on the old verdict. Back at review, the reviewer's brief points at the diff
  since its last verdict.
  An approving review is risk-graded by a model that didn't write it (`Server.Workline.Grade`, run by
  `Server.Jobs.Grade`): script limits first, then five axes; under the operator's `auto_land_risk` it
  lands without them.
  Red anywhere after build — verify, the merge gate, review, QA — goes back to build on the same
  branch with the finding (`Workline.red_verify/2` for verify): the build kept, never redone. Red
  also goes to the workspace's sheriff (`Server.Sheriff`, bench archetype `sheriff`) on its beat
  thread as a copy, never instead of the operator's list (`Server.Office.Needs`, where a workline
  nothing has moved past the quiet window is `stalled`); a beat incident resolved naming its PR is
  banked as a `postmortem:` fact. An issue a ticket owns (`Dossier.fix_issue/1`, the operator's "Get it
  fixed", or `file_ticket` with `issue_id`) leaves the operator's list, says who has it as info, and is
  resolved naming the PR when the ticket's workline lands (`Dossier.resolve_fixed/2`).
- **the toy's generators** (`Server.Generator`, `Server.Persona`, `Server.ToyPool`) — cheap model
  calls (`:generator_cmd`/`:generator_model`, default Claude Code, bare, on the flat ollama flash model), never on a
  render path: `Generator.run/1` is the one door (banter on, `:generator_daily_cap` per day counted in
  `generator_call`, failures included). A seat's persona (`workspace_agent.persona`, with its seed)
  is made at hire or by `tlon-cli persona <ws> <name> [--reroll]`, falling back to the §2 voice table;
  `ToyPool` holds doorbell visitors (weekly), per-seat reaction lines per event, and puns, read as
  `[]` until generated so callers use their handwritten lines. `Server.Soul` writes a seat's first-draft
  SOUL.md (design §5–6 step 2) to the souls dir the office polls, at hire or by `tlon-cli soul <ws> [name]`:
  the three §5 samples verbatim, else `Generator`, else a template; created exclusively, so an existing
  file (edited or not) is never touched. Step 3: it is also read (`read/1`, `voice/1`,
  `tone/1`) — by `Server.Office.Banter` on every line and by `Profiles.instantiate/2` at spawn, and
  by nothing else (`soul_callers_test.exs`): a soul shapes talk and tone, never a work decision.
- **the PM** (`Server.Release.PM`, bench archetype `pm`) — what ships: `release_status`,
  `propose_release` (graded commit by commit with `Grade.assess/2`, the max per axis; under
  `auto_land_risk` it cuts, else one gate on the root thread — a window-less `prompt` answered by its
  id through `Attention.answer_prompt/3`, as every prompt is: a plain post on its thread answers
  nothing), the changelog posted and recorded as event `release:<sha>`, and
  `set_urgency` on the backlog. Work runs in `Server.Jobs.Release`; tests hand it a repo (`:release_root`).
  The service's boot says `release <sha> is live` once per new pointer (`note_live/1`), which the
  desktop toasts.
- **the librarian** (`Server.Librarian`, bench archetype `librarian`, the default bench's `quain`) —
  the office's memory: it decides the correction judge's `supersede_proposed` events
  (`review_proposals`/`decide_proposal`, through `Server.Recall.Supersede.apply_proposal/1` and
  `reject_proposal/2` — absent, it says the judge isn't installed), retires or tombstones facts
  (`supersede_fact`/`forget_fact`, the reason recorded as a `superseded`/`forgotten` event; a landed
  workline's in-flight state forgotten, its lessons kept — `landed_facts`; a
  `stated` fact is refused), and posts the weekly counts in the lobby (`knowledge_report`). Its
  sweep (daily 07:00) and report (Mondays 07:30) are standing schedules, `ensure_schedules/2`.
- **the calendar** (`Server.Schedules`) — agent runs, worklines and scripts on a cron or once, fired by
  a per-minute dispatcher (`Server.Jobs.Dispatch`, OSS Oban having no dynamic cron); each firing a
  `schedule_run` row (the automation board); a script's `ran-on: <check> <sha>` line records the commit
  it checked, which `Server.Release.Candidate` reads. Crons read the server's local clock.
- **branch reviews** (`Server.BranchReview`) — a review on tlon of a branch that is not a workline: a
  reviewer's `review_branch` (branch, the full sha it read, approve | request_changes, the review) is an
  event correlated `branch:<name>:review`; the newest is the branch's verdict (`tlon-cli branch-review <branch>`).
  A verdict by a builder of the branch is refused (`BranchReview.builders/3`), and so is an approval by
  the PR's author at landing.
  A PR lands only on it (`Server.PRLanding`, `mise run land -- <pr>`): queued in the same merge queue as
  worklines (`Server.Jobs.Land`, args `%{pr, branch, on_thread}`) when the verdict approves its head (or a
  pure rebase of it, `BranchReview.approves/4`), checked again at its turn, rebased onto main on a private
  `land/<branch>` ref and gated by `workline-verify.sh`'s branch mode, then pushed, the review commented,
  `tlon/check` posted and merged with `--match-head-commit`; the outcome posts on the review's thread.
- **feature flags** (`Server.Flags`) — `fun_with_flags` on the store's Postgres, each node's cache
  busted over `Server.PubSub` (no Redis, no restart): work that lands dark ships behind a flag the
  server names, off; the office gets every flag in its snapshot. Flip one with
  `mise run server:cli -- flag <name> on|off` or `PATCH /api/flags/:name`.
- **recall + forgetting** (`Server.Recall`, `Server.Search`) — the budgeted always-loaded set. A
  superseded fact is demoted: a newer fact supersedes an older one in its scope when it restates it
  (`Server.Recall.Supersede`, exact or cosine ≥ 0.92) or a model judges it restates or corrects it
  (the turn-pass extractor's labels, `Server.Recall.Judge` for every other bank). Judged supersedes
  ship dark behind the `:judged_supersede` flag — off, only `supersede_proposed` events, which the
  librarian decides (`Server.Librarian.decide/4` → `Supersede.apply_proposal/1` /
  `reject_proposal/2`). A stated fact is never judged away;
  a correction of one is an ask to the operator.
- **seed + bootstrap** (`Server.Seed`, `Server.Bootstrap`) — the wipe-proof base knowledge
  (`priv/seed/repo_knowledge.exs` + the machine-appended `promoted_facts.exs`) and the default
  workspace, applied idempotently on every boot.
- **the steering evals** (`Server.Eval`, `evals/`) — scenarios over the briefs and playbooks,
  deterministic ones in the gate, judged ones in `mise run server:eval`.
- **the role bench** (`Server.Bench.Roles`, `../bench/roles/`) — each role's frozen tasks run headless
  through the profile a coworker of it gets (`Harness.aside/2`'s argv, its routed model or `--model`),
  graded (a hidden check, JSON fields, or the eval judge), usage recorded; `mise run bench:roles`.
  The gate tests its pure parts, and that every builder fixture's check is red before any work. The
  `senior` builder set is real merged worklines (`task.json` `source.commit`: the workdir is `git archive <sha>^ server`,
  the hidden check that workline's own tests); `--oracle` proves each green on the real diff.

Still deferred: the engine-credit half of presence (clocked-out from spent credits/rate-limit), the
human-notification path, and the `Sense` collectors. (A mention of a coworker who isn't on the
thread reaches them in their window on the workspace's standing thread; they answer with
`consult_peer`.)

**The life side has no privacy boundary yet.** `routine`/`routine_run`/`quest` rows are plain
Postgres, readable by any coworker holding a `home`-type workspace's MCP tools — same trust
model as everything else on this box, named here before anyone runs a second `home` workspace
that isn't andrew's own.

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

- `mise run server:test` — the ExUnit suite (`mix test`). Each run drops and recreates its own test db
  (`test_helper.exs`), named per checkout: `tlon_test` in the main checkout, `tlon_test_<name>_<hash>`
  in any git worktree wherever it lives (`Server.TestDatabaseName`, `config/support/`).
  `TLON_TEST_DATABASE` overrides it — set it for a second suite in the same checkout.
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
- `mise run release:smoke -- [<sha>]` — the candidate as a scratch release on a pid-picked port and its own db `tlon_smoke_<port>` (never 4040 or `tlon`; the port is printed): `/api/office`, then the office driven headless; torn down after (`TLON_SMOKE_HOLD=1` keeps a passing node up to drive, as QA does). `TLON_NODE` names its node beside `funes@`.
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
  token, print the `export TLON_*` block for a hand-run pane.
- `mise run server:roster` — who's on the clock (live sessions, warm/cold).
- `mise run server:dossier -- <thread-id>` — render a thread's brief (parity with get_dossier).
- `mise run server:post -- <thread-id> <text…>` — post as the operator (parity with post_message); a
  plain post, never an answer: `mise run server:cli -- answer <prompt-id> <key>` answers a prompt.
- `mise run server:cli -- <subcommand>` — everything else the CLI knows (worklines, approve, …).

The `home:switch` that installs the service is the human's (system-mutating); build + verify the
release with `server:release`, and on the home machine with ficciones' `flake:check`.

If a command belongs in the loop, it becomes a task in the root `mise.toml`. Do not invent a second way
to run these.

## Verify

Built test-first (RED before GREEN), and a claim that something works is backed by having run it — the
spec exists because "it works" without running it happened repeatedly in version one. `mise run
server:check` is the gate; `server doctor` against a real db, read back with `psql`, is the 2am proof.
