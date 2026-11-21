# server

**Read `docs/spec.md` before writing anything.** It is the specification this module exists to
implement, every rule in it names the failure that paid for it, and it was reviewed adversarially twice
(`docs/spec-review.md`, `docs/v1-review.md`). If something here contradicts the spec, the spec wins; if
the spec is wrong, say so and change it in the same commit as the code that proves it.

## What is here

The spine of Tlön: Postgres is the truth (a real db reads back under `psql`), Ecto over `postgrex`,
and every layer the spine design's re-laid §9 asked for
(`../../docs/plans/2026-08-14-console-cockpit-and-elixir-spine.md`) is built and gated:

- **db + doctor** — the schema (`priv/repo/migrations/`), `Server.Doctor` (integrity_check, tables, the
  newest crash dump (the tlon root's `erl_crash.dump`, `tlon-cli.sh`'s state dir) read against the service's start, the
  `.worktrees` size as exclusive bytes, pending migrations, JSONL export),
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
  offers the other crews at the front desk, and a taken offer offers the way back at the reset. A
  provider's `Request rejected (429)` usage-limit line (a pane, or a one-shot's stderr through
  `Server.ModelCli`) is a `quota` Need at once, under the same key as the provider's balance poll.
- **pause** (`Server.Pause`) — the office's stop controls, in the settings file's `"pause"` key so a
  restart keeps them: pencils down (intake and continuation nudges off, every live thread told to
  finish its turn, commit and stop, as a notice; only the operator's own posts wake anyone — every
  other wake, a stage brief or a coworker's post, is held undelivered for the drain back at work; the
  calendar's agent and workline schedules wait, firing once back at work, the operator's delegate's
  check-in too; staffing — `staff_child`, `Tickets.start_thread/2` and its API and CLI doors — is
  refused, `Pause.at_work/0`), lights out (that, plus the verify and landing
  queues paused — a boot under it starts them paused — and an Escape into every coworker pane),
  back to work (every still-open thread pencils down stopped woken: a chat @mentioning its lead as it
  is now). `POST /api/office/pause`, `tlon-cli pause`, the office's finder. One thread on its own
  (`Pause.pause_thread/1`, the `thread.paused_at` mark, `POST /api/threads/:id/pause` and `/resume`):
  its lead told the same way, every wake but the operator's held until resume, no continuation,
  stalled Need or wake alert, `staff_child` under it refused; the office's pause and back to work
  leave it alone.
- **agent + session + staffing** (`Server.Staff`) — the durable named identity and its ephemeral
  instance; warmth is measured from `last_active_at`, never a heartbeat.
- **panes roll themselves** (`Server.Sweep`, `Server.Arbiter.Tmux.launch_stamp/2`) — a pane keeps the
  launch it was born with, so spawn stamps its window `@funes_launch` (`Server.Profiles.fingerprint/1`:
  the launch command and env, sandbox, system prompt, tmux.conf) and the minute's staffing pass retires
  one idle pane whose stamp its profile no longer gives (none at all counts), never one mid-turn. A
  stuck seat is rolled the same way before its third continuation (`roll_leaf/1`). Either records
  `pane_retired`, and the next session there opens with `left_off/2`. A release that changes launch
  config needs no `server:stop`.
- **the two "gone quiet" clocks** — they mean different things; never read a third number for either.
  The *stale turn* (`Server.Presence.Thinking.stale_turn_seconds/0`, `config :server,
  :stale_turn_seconds`, 600 s): a turn nothing has been heard from this long (its declare or its
  latest `presence_doing`) is a turn nothing will end; the thinking sweep clears it, and staffing and Needs stop counting it as someone at work. The *quiet
  workline* (the settings knob `quiet_workline_minutes`, 60): a workline that has not moved this long
  gets a Maintain nudge and is a `stalled` Need. Other bands are not "stale": the sweep's boot grace (a
  window still booting) and Maintain's gate/stall bands (`Server.Maintain.Bands`).
- **outside citizens** (`Server.Outside`) — agents seated on no bench, like `uqbar`, the operator's
  delegate: they post as themselves. Uqbar leads one thread of its own, its study (`Outside.study/1`),
  where a post spawns its pane on its citizen profile (`Profiles.citizen_profile/2`: the Claude plan,
  unsandboxed, started in the repo's main checkout); the study is a duty, so it takes no coworker's seat.
  Every boot ensures its check-in (`Outside.ensure_checkin/1`), so the study exists from the first boot
  with uqbar registered, before anyone has talked to it; a closed study is reopened, never replaced.
  Every boot seeds each citizen with a profile (`Outside.ensure_citizens/0`). **The Aleph**
  (`Server.Aleph`, on Fable) is the other: called in, never seated. An `@aleph` on a thread from the
  operator, the manager or the tech lead spawns it there (`Aleph.called?/2`) in a window named for it,
  untagged so it is never taken for the thread's leaf; it answers once, and the staffing pass dismisses
  it when idle after posting. The office draws it as a sphere over the card (`office/kit/aleph.ts`);
  `:` on a thread card calls it.
  The operator hands it an ask (`Attention.hand_to_uqbar/2`, `POST /api/office/prompts/:id/uqbar`, `u` on
  an ask in the office): one post as the operator on its study, the ask resolved `handed to uqbar`; Uqbar's own ask is refused (`:own_ask`) and not offered.
- **the dossier** (`Server.Dossier`) — `fact` (provenance stated | derived, CHECKed by the db;
  `check_cmd` as a separate reproducibility axis; `supersedes`; `forgotten_at` tombstones), append-only
  `event` with a closed `kind`, `issue`, `todo`, `question`, `habit`. Read capped-and-counted.
- **the container tier** — `Server.Workspaces` (roster + paths), `Server.Projects` (repos),
  `Server.Tickets`, `Server.Notes`.
- **blocked on a ticket** (`Server.Blocked`, the `blocked_on` tool) — a seat stopped by a fault an open
  ticket already covers says so instead of asking the operator: a `blocked_on` tie
  (`Server.TicketThread`), the sighting appended to the ticket. Its thread gets no continuation nudge and
  is never `stalled`; the ticket is one `blocked` Need however many threads wait. The block clears, and
  the lead is woken to retry, when the ticket is closed and `Server.Release.PM.note_live/1` sees a
  release go live (a fix reaches seats at a cut).
- **a lead's hold** (`Server.Pause.pause_thread/2`, the `hold_thread` tool) — a deliberate stand-by is
  not a stall: the thread's lead, the lead above it or the manager pauses it with a `why` (in the pause
  notice) and releases it with `release: true`. It is the operator's per-thread pause, no new state; a
  turn ending never clears it.
- **the switchboard** (`Server.Switchboard` + `Server.Bus` + `Server.Arbiter`) — delivery WAKES the
  addressee (§5b.2): a posted message is a durable row first, then broadcast over `Phoenix.PubSub`, and
  the switchboard pokes the thread's lead / the @mentioned coworker / a reply's author through the
  arbiter behaviour (`Server.Arbiter.Tmux`). Coalesced (a backlog is one
  nudge), warmth-gated (a cold session is rotated onto a fresh, brief-seeded one, never poked), and
  `drain/0` re-delivers on restart, so killing the BEAM loses nothing. A wake its addressee never
  acted on (no call to the server since) is offered again for 30 minutes (`redeliver_unheard/1`).
  One seat, one session: spawning a window (a coworker's or a crew role's) first SIGTERMs, then after a grace SIGKILLs, any process still holding that
  (thread, handle) identity in its environment (`Server.Orphans`, saying so on the thread), so a killed window's survivor
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
  the landing (`Server.Jobs.Land`, one at a time, rebased onto origin's main and gated there — red bounces to build; green posts the commit status `tlon/check`, the record of the check, on the sha it gated (`Workline.Publish.publish/5`) and the PR merged at once at that head (`--match-head-commit`), and only then,
  read by `Server.Jobs.KeepUp`, does its thread close and its ticket count as done: `Workline.merged/2`;
  one GitHub holds `BEHIND` or `BLOCKED` with no check running goes back into the merge queue on its
  own, once per PR head (`Workline.requeue_blocked/3`); one GitHub still isn't merging — the merge
  refused, held again at a head already requeued, the requeued landing red or conflicting, an hour
  gone — is a `pr_blocked` Need, answered by rebase (back into the merge queue, `Workline.reland_queued/2`: rebased, gated, `tlon/check` posted and merged at that head — never GitHub's own update-branch, whose head no gate ran on), close and reland, or a look at the PR).
  `KeepUp` also warms each main checkout's `_build` for test once per tip (`warm_test_builds/2`): a mix project with a locked dependency and no `deps/` is skipped (never fetched), as is a compile that says its dependencies are unavailable; each skip or failure is one keyed rollout note `keep_up:warm:<dir>`, and the tried tip is kept in `Server.Home.Keep`, so a restart does not recompile it, and its note is posted again while the condition holds.
  An approved review of a change Andrew sees (`office/`, the operator API) goes to the bench's `qa`
  seat first: it drives the branch on a scratch release the service holds for it (`start_smoke`, `drive_smoke`, `stop_smoke`: `Server.Smoke`, `Server.Jobs.Smoke` — a seat's sandboxed Bash can't run `release:smoke` or reach its port; `start_smoke`'s `fixtures` seed named sets (a spec is `name` or `name:key=value,key=value`, no spaces; a value that cannot travel, such as a backtick, is a named shape: `tool_denied_need:shape=backtick`; a new case is a catalog entry, not a new door) from the candidate's `Server.Smoke.Fixtures` on the smoke's own `tlon_smoke_*` db, refused on any other) and files `submit_qa` (with the workline's
  `thread_id`, which only a `qa` seat on its bench may name — its session may be bound elsewhere); a fail bounces it to
  build with the finding, and nothing lands past an owed QA (`Server.Workline.qa_verdict/5`) but the
  operator's `approve <id> --skip-qa <why>` (API `{"skip_qa"}`), recorded as its QA verdict.
  The operator reviews a branch from the office (`Server.Workline.OperatorReview`): its diff as
  files, hunks and numbered lines, and notes on lines or files submitted with a verdict — comment,
  request changes (`send_back/5` to build, the notes its why) or approve — reaching the lead as one
  post in revdiff's shape (`## path:line (+) note`).
  A workline moves backwards on its own thread and branch, the build kept to improve, never redone
  (`Server.Workline.send_back/5`, the `send_back` tool, `tlon-cli send-back`): back to build by its
  lead, or by Uqbar at a gate parked on the operator whose grade hit no limit; back to plan or spec only by the tech lead (a coherence call) or the operator; an open one
  only, never while its verify is queued or running or its landing is running; a landing still
  waiting in the merge queue is pulled with the move by `unqueue` (the tool's and the API's field,
  the cli's `--unqueue`), cancelled in the same transaction so nothing finds the thread at review to
  requeue it. A reviewer's or QA's non-blocking
  findings are `follow_ups` on `submit_review`/`submit_qa`: one post on the workline, made after the
  verdict for the lead it hands to (the builder on a bounce, the qa seat when QA is owed, the operator
  at their gate — the author's own session ended with the verdict), who fixes what sits in the
  change's lines, drops the rest or defers one with `file_ticket`; a `held` follow-up ticket goes to
  intake when its thread closes (one closed unmerged says so in the ticket).
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
  `ToyPool` holds doorbell visitors, per-seat reaction lines per event, and puns, read as
  `[]` until generated so callers use their handwritten lines, and refilled daily on the ollama model
  by a script schedule, `mise run toys:refresh` (`ToyPool.refresh_cli/0` over each staffed workspace; a hung model stops it after 3 timeouts in a row). `Server.Soul` writes a seat's first-draft
  SOUL.md (design §5–6 step 2) to the souls dir the office polls, at hire (`after_hire/2`, off the hire's path and best-effort: a name the guard refuses is refused before the seat is made) or by `tlon-cli soul <ws> [name]`:
  the three §5 samples verbatim, else `Generator`, else a template; created exclusively, so an existing
  file (edited or not) is never touched. Step 3: it is also read (`read/1`, `voice/1`,
  `tone/1`) — by `Server.Office.Banter` on every line, by `Profiles.instantiate/2` at spawn, by the
  diary and by the corkboard's side projects (`Server.Office.Corkboard`), and by nothing else (`soul_callers_test.exs`): a soul shapes talk and tone, never a work decision.
- **the PM** (`Server.Release.PM`, bench archetype `pm`) — what ships: `release_status`,
  `propose_release` (graded commit by commit with `Grade.assess/2`, the max per axis; under
  `auto_land_risk` it cuts, else one gate on the root thread — a window-less `prompt` answered by its
  id through `Attention.answer_prompt/3`, as every prompt is: a plain post on its thread answers
  nothing), the changelog posted and recorded as event `release:<sha>`, and
  `set_urgency` on the backlog. Work runs in `Server.Jobs.Release`; tests hand it a repo (`:release_root`).
  The service's boot says `release <sha> is live` once per new pointer (`note_live/1`), which the
  desktop toasts. It also records the pointer it came up on (`boot/1`): a scripts-only cut over a
  server behind that pointer restarts it instead of saying live.
- **the librarian** (`Server.Librarian`, bench archetype `librarian`, the default bench's `quain`) —
  the office's memory: it decides the correction judge's `supersede_proposed` events
  (`review_proposals`/`decide_proposal`, through `Server.Recall.Supersede.apply_proposal/1` and
  `reject_proposal/2` — absent, it says the judge isn't installed), retires or tombstones facts
  (`supersede_fact`/`forget_fact`, the reason recorded as a `superseded`/`forgotten` event; a landed
  workline's in-flight state forgotten, its lessons kept — `landed_facts`; a
  `stated` fact is refused), and posts the weekly counts at the front desk (`knowledge_report`). Its
  sweep (daily 07:00) and report (Mondays 07:30) are standing schedules, `ensure_schedules/2`.
- **review marks** (`Server.ReviewMarks`, swept each minute) — each tmux pane on a checkout of this
  repo carries `@arena_review` (`reviewed`, `changes`, `queued`, `landed`, or unset), the state of the
  branch it is on, for arena's rail; a commit after the review clears it.
- **the home's inbox** (`Server.Home.Inbox`, `Server.Jot`) — what the operator texts a messenger bot
  from their phone (a voice note heard on this machine by whisper.cpp, `Server.Home.Ear`, when
  `TLON_WHISPER_MODEL` names a model), kept raw as a `jot`, then read by one small model call (`Server.Home.Reader`: a
  reminder with its time and whether it repeats, a to-do with a rough size, a note, a project of up to five
  steps, or a waiting-on) and the reading said back, with what it assumed and the one question it may have
  (its answer amends the jot). A
  message can also ask the helper for something and is then kept as nothing: that things are done,
  what is open, what to do now (`Server.Home.Now`), what is on someday, that a thing is to be deleted, or a question its notes and today's and tomorrow's meetings (`Server.Home.Day`, from `Server.Calendar`) answer. The house's calendar view reads any run of dates from `GET /api/home/meetings` (`Day.between/3`).
  A form puts things in and changes them with no model call (`Server.Home.Form`, `POST /api/home/add|:id/edit|:id/plan|:id/revive`).
  `POST /api/home {text}` reads a text as the chat does and answers `{reply, row}` (`Server.Home.say_row/2`): `row` the thing it made, in `GET /api/home`'s shape, null when it made none.
  An **agenda** (`Server.Agenda`, `Server.Home.Agendas`) is a named standing pile of notes for a recurring occasion ("retro",
  "1:1 with Sam"), with or without a rhythm (`every`, `next_at`): the reader files "for retro: …" on it (a new name starts
  one, and the reply says so; it is shown the existing names to match loosely), sets its rhythm, and answers what is on it, what
  was on it, and "retro's done" (archives the notes as done). Its notes (`jot.agenda_id`) are in no plain list. The pile is told
  once, 15 minutes before `next_at` (in the chat, and as an info `home_agenda` alert on the desktop, as reminders are), and the time moves on an hour after it.
  The same pile (`home_agenda.kind`, `agenda | person | door`) holds two more things, never told ahead and in none of `agendas`: a
  **person** (`name`, an optional `birthday` `MM-DD` or `YYYY-MM-DD`, notes as gift ideas; `GET /api/home` `people`, each with its
  `next_birthday` and the open to-dos, reminders and waiting-ons that name them as a whole word) and **the door**, one pile per `via` made by
  its first note (`door`; `POST /api/home/door/add`): what to take along and errands for next time out. A note on any pile comes off
  by `POST /api/home/:id/drop` (`/done` is for reminders and to-dos). The reader files "by the door: umbrella" (`door`), answers "heading
  out" (`door_show`), makes a person from "Sam's birthday is March 3" (`person`) and files "gift idea for Sam: a kettle" (`person_note`).
  Birthdays are said in the morning message alone, a week ahead and on the day, with the notes as ideas: no nudge, no alarm.
  A **proposal** (`Server.Proposal`, `Server.Home.Proposals`; table `home_proposal`) is what an outside source suggests he might
  want: `{source, key}` unique, `text`, `why`, `kind` todo or waiting, `url`, `state` open/taken/dismissed. Nothing a source offers
  is filed by itself except a `waiting` one from a source that is trusted for it (`Proposal.offer/5`'s `auto`): a waiting-on is a fact,
  a to-do is an ask and waits for his yes. Offering a known key changes nothing, whatever its state; a dismissed key is final; a key
  the source says is gone (`Proposal.resolve/3`) withdraws an open proposal silently, leaves a taken to-do, and marks a taken
  waiting-on done, said once in the next list as its `done_text` (`Proposal.settled/1`): recorded told by the teller that says it
  (the chat's message when it goes out, or with no chat the inbox tick at the slot), never by a desktop read, which shows what
  was told since the slot opened. Nothing is said when one arrives: they
  are listed in the morning message and the daily list, on ask ("what's proposed?", "take the first", "dismiss all": reader kinds
  `proposals`, `take`, `dismiss`, shown the first five open ones as PROPOSED numbered as the chat numbers them, and answering
  those positions), and by Add/No buttons (`p:<id>:take|no`). `GET /api/home` has
  `proposals`; `POST /api/home/proposals/:id/take|dismiss`. A **source** is a module behind `Server.Home.Source` (`name/0`,
  `fetch/0` → `{:ok, proposals, resolved_keys} | {:error, why}`, `auto/0` the kinds it may file itself); `Server.Home.Sources` polls
  the ones in `home_sources` (comma list, default `""`: none), where `mail` is the first source: `Server.Home.Source.Mail`, the personal inbox over read-only IMAP (`EXAMINE`, `BODY.PEEK`; settings `home_mail_host`, `home_mail_user`, password from env `ZOHO_MAIL_PASSWORD` or the agenix secret `zoho-mail-password`), one home-reader model call over what arrived since the mark in `home_keep` `home_mail_mark` (the oldest 40 after a mark, so a backlog is worked off poll by poll; the mark moves in the optional source callback `kept/0`, after the proposals are filed; a reply with no list, and a batch whose filing failed so `kept/0` never ran, are counted per batch, a batch being what is read from one mark (so mail arriving meanwhile does not reset the count; a retry reads only up to the batch's top as first tried, later mail waits for the poll after), and the third skips it, the mark moving to that top, with one warning; message text is made valid UTF-8 first), proposing only a bill, appointment, package or renewal as a to-do keyed by `mid:` and the SHA-256 of its Message-ID (else `uid:<validity>:<uid>`; never the raw text), never filing one itself; every 15 minutes, started with the inbox
  (`TLON_START_HOME_INBOX=1`), logging a failure once per distinct reason and leaving the proposals alone; a name with no
  module is logged once as no such source. `bank` is the other: `Server.Home.Source.Bank`, the operator's bank through Plaid
  (`Server.Home.Bank.Plaid`, **read-only**: only `/link/token/create`, `/item/public_token/exchange`, `/transactions/sync`,
  `/accounts/get`, listed in `Plaid.paths/0` and pinned by a test; never the paid balance call, a refresh, auth or a transfer), on
  when `home_sources` names it and an access token is present (env `PLAID_ACCESS_TOKEN` or the agenix secret `plaid-access-token`,
  with `PLAID_CLIENT_ID`/`PLAID_SECRET` or `plaid-client-id`/`plaid-secret`; never kept or logged). It syncs the last 800 days of transactions (Plaid is asked for 730 at the link, its most, so a yearly charge shows) into
  the table `home_bank_transactions` (`Server.Home.Bank.Transaction`, upserted by `transaction_id`) and the cursor, accounts, `as_of` and the summary's dated part into the `home_keep` value `home_bank`, all in one database transaction per sync; a `home_bank` still holding a `transactions` list is moved into the table by the first read or refresh that sees it. The summary is worked out once per refresh and stored with the local day it is for, recomputed from the rows when read on another day. And
  `Server.Home.Bank.Recurring` (pure, in cents) finds the steady charges and deposits (three posted charges, a weekly,
  fortnightly, monthly or yearly rhythm, a yearly one needing two charges, amounts within 10%; transfers between its own
  accounts, equal and opposite within a day, are neither). It proposes only to-dos: a charge due within five days with whether
  the available balance covers it, two equal charges within two days that are not a habit, a merchant that just became recurring,
  a recurring one whose price changed (keys `bank:due|double|new|price|relink:…`, never filed by itself); `ITEM_LOGIN_REQUIRED` is one proposal that the bank needs linking
  again. `Server.Home.Bank.summary/1` (nil when off) gives the morning message its one `Money:` line and `GET /api/home` its `money`;
  spendable is the checking accounts alone. `Server.Home.Bank.Projection` (pure, in cents, no clock: `today` is passed in) is the
  money engine behind `Bank.forecast/2`, `afford/3`, `what_if/3`, `history/1` and `subscriptions/1`: the checking balance day by
  day (low, expected, high) from the recurring series repeated at their rhythms plus an everyday estimate (the last 90 days of
  posted outflows on checking that are in no series and no transfer, spread evenly; the low and high lines are the 25th and 75th
  percentile of rolling 30-day totals), capped at 180 days. Every number is computed there and none comes from a model, and none
  is an opinion on the spending. An expected charge or deposit that has not posted (today or earlier) stays on tomorrow as
  `overdue` (with `expected_on`) for half its rhythm, then is named in `basis.skipped`. `GET /api/home/money/forecast?until=` is the forecast and the subscriptions as JSON (null when
  off). The **money chat** (`Server.Home.Money`, `POST /api/home/money/ask {text, thread?}` → `{reply, figures, thread}`, read-only) answers a question about his money from that engine: the home reader's model
  (`:home_reader_cmd`/`:home_reader_model`, no tools; tests pass a `:model` function) plans up to four asks (`Server.Home.Money.Plan`, parsed strictly: a bad shape is a "rephrase" reply), the
  `Server.Home.Bank` wrappers compute them, the model phrases the results (amounts as `*_cents_text` strings) after the sentences code writes itself (a purchase's verdict with its date and amount, a series not found: `Say.leads/1`), and `Server.Home.Money.Say.check/2` requires every dollar amount in that phrasing to be one of
  the results' and `Say.contradicts?/2` (a word list) that it not say the opposite of a verdict; when there is a code-written sentence a third call, a judge given only the verdict facts and the text as JSON data, must answer exactly `{"agrees": true}` (a purchase costs three model calls, other questions two, one whose every ask is beyond the 180-day horizon one (the plan alone); the judge is a model too and guarantees nothing, the code-written verdict leads the reply regardless), else the reply is `Say.render/1`, the plain wording of the results (also when the model is down). The check sees dollar amounts only: dates, counts, percentages and numbers in words are not checked. Bank-sourced names reach the model only as JSON in a data block it is told is never instruction.
  Nothing there writes the bank tables, calls Plaid or files a proposal; its only write is the thread's last ten turns for two hours (`Server.Home.Money.Thread`, in `home_keep`; writing one deletes the threads gone stale, `Keep.expire/2`). `mise run home:bank:link` links once (`Server.Home.Bank.Link`, a loopback page,
  the token printed once and kept nowhere; refused with a token present, `-- --allow-another-link` overrides: the account allows ten
  links for ever).
  The home also does the upkeep itself (`Server.Home.Organize`, `Server.Home.Helper`): a project always has one
  open next step or a question about it, a waiting-on is asked about after three days, a weekly review
  (`home_review_on`, at `home_list_at`) offers stale things Keep / Later / Drop and moves anything stale for 28
  days to someday (said at the first waking moment when its time went by asleep), and a to-do that sat a week is offered a two-minute
  start after the daily list (written in the background; never at night). Each
  question is a `jot` row with an `ask`, said in the chat and raised on the desktop
  (`Server.Home.asked/0`, a sticky `home_ask` alert whose buttons call `POST /api/home/:id/answer`), so it
  works with no messenger. Its two model calls (next step, a start) go through the reader's provider
  and `:home_helper`. What is open is also said once a day at the
  `home_list_at` setting, each thing with a button that ticks it off, then the waiting-ons a source settled; the open proposals
  follow as a message of their own (an Add and a No each; the chat's morning message has no buttons, and its proposals follow the
  same way). Once a day at `home_morning_at` (08:30; `""` never; same slot record and quiet hours as the list,
  `Server.Home.Inbox.morning/6`) the morning message is said (`Server.Home.Morning`): today's meetings (`Server.Home.Day.meetings/1`,
  today's only: times local, "all day", a tentative one marked), what to start with, agendas due today with a pile, birthdays today and a week ahead, one
  `Money:` line when the bank source is on, the settled waiting-ons and the proposals (five shown, "and N more"); it is skipped when there is nothing to say, and the desktop
  gets it as a `home_morning` info alert for ten minutes after its time (`Server.Home.morning/1`), and the daily list as a
  `home_list` one, each carrying the settled waiting-ons and recording them told the first time it is raised, so a desktop with no chat says them too. A message that corrects the jot before it
  changes that jot's reading, and a reminder is said in the chat when it comes due, with done / in an
  hour / tomorrow / delete under it, and again if left unanswered (never at night, six times at most). No
  reading, and the answer is "got it". Times are the machine's zone (`Server.Home.Clock`). The
  messenger is a module (`Server.Home.Telegram`: outbound long polling, so no port is opened; its token
  is the machine's, `TELEGRAM_BOT_TOKEN` or agenix `telegram-bot-token`). Only the `home_chat` setting's
  chat is kept; unset, a chat that writes is told its id. Opt-in, `TLON_START_HOME_INBOX=1`, set by the
  service alone: a dev boot, an eval or a smoke node that polled would take the operator's messages
  from the service. No token, no poller.
- **the calendar** (`Server.Schedules`) — agent runs, worklines and scripts on a cron or once, fired by
  a per-minute dispatcher (`Server.Jobs.Dispatch`, OSS Oban having no dynamic cron); each firing a
  `schedule_run` row (the automation board); a script's `ran-on: <check> <sha>` line records the commit
  it checked, which `Server.Release.Candidate` reads. Crons read the server's local clock.
- **branch reviews** (`Server.BranchReview`) — a review on tlon of a branch that is not a workline: a
  reviewer's `review_branch` (branch, the full sha it read, approve | request_changes, the review) is an
  event correlated `branch:<name>:review`; the newest is the branch's verdict (`tlon-cli branch-review <branch>`).
  A verdict by a builder of the branch is refused (`BranchReview.builders/3`), and so is an approval by
  the PR's author at landing. Every review — a workline's `submit_review` or a branch's `review_branch` —
  runs in a throwaway session on its own thread, ended by its verdict (`Server.Sweep.end_review/1`:
  the thread's sessions ended, its leaf window closed — a workline's from `Server.Jobs.EndReview`, once
  the verdict has parked or bounced the thread, since the window closing cancels the request on the
  server); `review_branch` from the standing thread is refused. A workline's reviewer reads the branch,
  the diff, the spec/plan and the checklist, never the builder's conversation: its `get_brief` hides
  OPENING, RECENT, DONE and LEARNINGS, counts kept
  (`Server.Board.brief/2` with `viewer:`); the round-2 pointer `last_reviewed` stays in the stage brief.
  A PR lands only on it (`Server.PRLanding`: an approving `review_branch` queues the branch's open PR onto
  main itself, `request_branch/3`; `mise run land -- <pr>` and `land_pr` queue one by number): queued in the
  same merge queue as worklines (`Server.Jobs.Land`, args `%{pr, branch, on_thread}`) when the verdict
  approves its head (or a pure rebase of it, `BranchReview.approves/4`), checked again at its turn, rebased onto main on a private
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
  A workline whose diff edits a persona (`Server.Workline.Grade.steering/1`: `profiles.ex`, `soul.ex`)
  gets a canary A/B on verify (`mix server.bench_contrast`, `Server.Bench.Contrast`): the roles whose
  prompt hash moved (`--fingerprint`, both checkouts) run the canary suite from a throwaway worktree
  of origin/main (never the root checkout) and the branch's rebased checkout (`--out`, so neither
  tree's results are touched), at most 3 roles under one 15-minute wall that kills a side's whole
  process group; each contrast is a `bench_contrast` CHECKS row and a thread note, a regression named for
  the reviewer, never a red. A skill or AGENTS.md edit is recorded `unmeasurable`: the bench never
  loads them.

Still deferred: the engine-credit half of presence (clocked-out from spent credits/rate-limit), the
human-notification path, and the `Sense` collectors. (A mention of a coworker who isn't on the
thread reaches them in their window on the workspace's standing thread; the mention is the
invitation — they answer there with `post_message thread_id: N`, `Server.MCP.Tool.may_post?/2`. A need
routed to Uqbar is the same invitation onto its thread, lapsing with the item.)

**The life side has a boundary.** `routine`/`routine_run`/`quest` rows and the status answer only to the
operator's own sessions and to an `assistant` seat on a `home`/`life` workspace (`Server.Life.authorize/2`,
applied by every life tool through `Server.MCP.Tool.life/3`); any other seat, a builder on the same
workspace included, gets `not_yours`. The operator's HTTP door (`/api/life`) is the operator's already.

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
  in any git worktree wherever it lives (`Server.TestDatabaseName`); `Server.Worktree.retire/2` drops a retired checkout's db.
  `TLON_TEST_DATABASE` overrides it — set it for a second suite in the same checkout.
- `mise run server:check` — the **precommit gate**: `mix precommit` = format-check + warnings-as-errors +
  `credo --strict` + the suite (runs in `:test`). `mise run server:eval-det` — the deterministic evals
  (their own `tlon_eval_<pid>` db, in the full check beside it).
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
- `mise run release:smoke -- [<sha>]` — the candidate as a scratch release on a pid-picked port and its own db `tlon_smoke_<port>` (never 4040 or `tlon`; the port is printed): `/api/office`, then the office driven headless; torn down after (`TLON_SMOKE_HOLD=1` keeps a passing node up to drive, as QA does, until stopped or `TLON_SMOKE_HOLD_TTL` seconds pass, default 7200). A sandboxed Bash is refused up front: it can't reach Postgres, and its network namespace is blind to the port a hold serves on — run it unsandboxed. `TLON_NODE` names its node beside `funes@`.
- `mise run server:restart` — rebuild + restart the service (redeploy a server change). It refuses
  while a restart would cut work off (a coworker mid-turn, a verify, landing, smoke or scheduled run running —
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
- `mise run server:roster` — who's on the clock (live sessions, each with its `Server.Coworker.status/1`: working, waiting, idle, cold or off).
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
server:check` is the module's gate (babylon runs it for a session's change; a session runs `menard run test <files>`); `server doctor` against a real db, read back with `psql`, is the 2am proof.
