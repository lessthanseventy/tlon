# funes — specification

Written 2026-08-14, after two weeks of daily use of version one and two fresh-context adversarial
reviews of it. Version one is committed at `workbench-env 3ac8506` and keeps running until this
replaces it piece by piece.

This is not a migration plan. Version one is **evidence**, not a source: its schema, file layout and
vocabulary get no vote. In the owner's words — *"i don't think we need to REPLICATE what we have so
much as the spirit of it... here's what a weaker version of you and I got to, bring it into here."*

Everything below that reads like a rule was paid for by a specific failure. The failures are named,
because a constraint without its incident gets optimised away by the next person who finds it
inconvenient.

**Amended 2026-08-14, on migration to the clean-room machine.** This specification rode over to a second
machine (§8c) and, on landing, three things changed and are recorded here rather than silently:

- **The name is `funes`**, after Borges' *Funes the Memorious* — the man who could not forget and was
  useless for it. A specification whose §4 is a war on total recall earns the joke; "Workbench" was a
  placeholder that travelled with the file. The identifiers `workbench_ledger`, `workbench_mode` and the
  `workbench-env` repo are v1 proper nouns and keep their names.
- **This is now a module, not a repository.** It lives at `modules/funes/` inside a `machine-v2` monorepo
  that is the owner's whole computer — dotfiles, installer, desktop, and this. So every "repository" in
  §8b and §8c — *"a clean repository"*, *"nothing travels except this repository"*, *"THE REPOSITORY MUST
  BE SELF-SUFFICIENT"* — now reads **"the `funes` module"**: the boundary those sections drew at the repo
  edge moves inward to the module edge, and the unit that crosses to another machine is `modules/funes/`
  (a `git subtree` split, or the flake enabling only this module on that host). The self-sufficiency rule
  is not weakened — it is precisely what lets the boundary move without leaking.
- **`AGENTS.md` is now `modules/funes/AGENTS.md`.** §7's "what makes 'knows nothing' safe" is that file
  in its new home; the machine repo has its own root `AGENTS.md` for the layer above.

The reasoning is in `../../docs/plans/2026-08-14-machine-v2-and-funes-design.md`.

**Amended 2026-08-14 again, when the shape coalesced.** funes is not a set of CLIs — it is a TUI Slack for
agents, the cockpit `aleph`, and the coalesced architecture supersedes two things this document implied:

- **Runtime is an Elixir spine, not per-invocation CLIs.** A persistent OTP application (supervision +
  `Phoenix.PubSub`) hosts the collectors, the reactive board, and the switchboard; **SQLite stays the
  truth** (Ecto / `ecto_sqlite3`, the same file, still 2am-repairable — *not* Postgres). Short-lived
  agents and the terminal arbiter sit outside it and speak through the DB.
- **§10, refined not broken.** "The database is the bus" stands exactly. The Elixir app is a **switchboard**
  (delivery, wake, presence) *over* that bus, never the bus itself: kill the BEAM node and no message is
  lost and every agent still reads and writes the DB directly. A supervised, DB-backed switchboard
  *fulfils* §10's intent — §10 bans an *unreliable, ephemeral session* from the delivery path, which
  OTP + SQLite-as-truth is the opposite of. And the terminal is a **capability, not a product**
  (Herdr | tmux) — the §8 rule applied to the one place this document broke it by naming Herdr throughout.
  Elixir orchestrates; the arbiter actuates.
- **The `thread` is first-class.** §5b's "a thread per subject" and the `subject` tag become a `thread`
  row that `fact`, `event`, `issue` and `message` reference; a workspace hangs off a thread as an opaque
  handle, and a **agent** (a persistent named identity with a §8 capability profile) is assigned to it.

**Amended 2026-08-16, when the Tlön machine coworker began cluttering the project surfaces.** A
machine coworker is a funes citizen on a real `thread` (so its facts/issues/checks survive), but it is
meta work — *on the box*, not a project — and its thread must not appear in the Comms chorus or the
Sessions thread list. So `thread` gains a **`scope`** column: a closed `('project' | 'machine')` set,
CHECK-guarded, default `'project'` — the `state` / `event.kind` precedent (§4: a closed set lives in
the DB, widening it is a migration, which is the point). The project surfaces read `scope = 'project'`
only; the machine thread is reached by id (the Tlön space) or via `Channel.machine_thread/0`
(find-or-create, so it is persistent across aleph restarts instead of one-per-boot). `scope`, not
`kind`, because it names *where the thread belongs*, not *what kind of object it is*; `kind` stays
reserved for `fact` / `event`. See `docs/plans/2026-08-16-tlon-isolation.md`.

Full architecture: `../../docs/plans/2026-08-14-aleph-cockpit-and-elixir-spine.md`.

---

## 1 · Who this is for

One person, one machine. He has ADHD and poor eyesight. After two weeks of daily use he could not
remember what his own workspaces were called, and asked three separate times about the naming. **Fewer
things to remember beats more capability, every time.**

Two questions he asked for and did not have:

- *"what do I need to Review PRwise right now"*
- *"What did I do yesterday?"*

followed by the sentence this whole document exists to answer: *"the daily notes are great for you
not so much for me yafeel?"*

A surface that is **complete** is not a surface that **answers a question**. Version one's radar
printed twelve equally-weighted pull requests with URLs inline and one title that was a six-line Ecto
stack trace. It was correct and useless.

---

## 2 · The one architectural decision

**SQLite is the machine's truth. Markdown is the human's surface. Herdr is the terminal's truth.**

Three owners, no overlap:

| Owner | Holds | Never holds |
|---|---|---|
| SQLite | facts, events, issues, signals, what I learned | how the screen is arranged |
| Markdown in `~/notes` | what a person reads | anything the machine needs to query |
| Herdr | workspaces, tabs, panes, focus, agent lifecycle | anything about the work itself |

Corollaries, each with its incident:

- **Machine-written markdown is generated, never authored.** Version one's key map was hand-written
  prose beside the config the program actually read; it was stale within an hour and asserted a rule
  ("Reviews has no chord on purpose") that nothing enforced.
- **The notes are a machine-owned draft and the machine has full access to them.** "Draft" rather than
  "view", because a view is a pure function of its inputs and the writer-side rule in §6 is what makes
  that true; until every sentence has a row behind it, the file holds information its inputs do not. Corrected by the owner,
  who also pointed out that `how-i-work.md` was written by a session and not by him: *"the ai can and
  should have access to all the human notes... i just want them to be the 'regenerate this when
  something changed, human friendly' view into stuff."* So there is no authored carve-out. The
  consequence, which must be designed for rather than discovered: **a generated file cannot also be an
  input.** Anything the human types must land in the database through a capture path and reappear in
  the next regeneration, and every generated file says at the top that it is generated and when.
- **The one seam, stated so it cannot be widened.** "Subject X is being worked in workspace w4H" is
  both work and screen, and version one stored it in handoff rows. So: **SQLite holds the workspace id
  as an opaque reference and never a cached copy of its properties** — no label, no pane list, no
  status — and **liveness is asked of Herdr within the turn that needs it.** The moment a property of a
  workspace is stored, this document's own §3 has been broken and the drift in §8b starts again.
- **We do not mirror Herdr state.** Version one kept its own idea of which workspaces existed and drifted
  from reality — six records disagreed with the live list on a single afternoon. Ask Herdr. Cache the
  answer for the length of one turn, never longer.
- **When two things can answer the same question, delete one.** Three defects in one day were "two
  sources of truth where the untested one was in the live path": a stale pane-id parser beside a
  tested one, a hand-written key map beside the config, and a field computed at write time
  (`ageMinutes`) read as if it were current.

---

## 3 · Herdr, Pi, the model and the human are one control loop

Banked as a constraint during the spec work, from the owner directly: *"i would honestly like to
expose as many of the actual herdr commands to this whole pi stack"*.

So funes does not wrap a chosen subset of Herdr and hide the rest. It exposes Herdr's own
commands and vocabulary, and it uses Herdr's authoritative channels rather than cosmetic imitations:

- **Blocked state is published through Herdr's lifecycle channel**, not drawn as a status string. When
  a session needs the human, Herdr's own working indicator stops, the workspace is marked blocked, and the
  exact safe pane is focused.
- **Location is Herdr's answer, always.** `herdr pane process-info` tells you what is running in a
  pane; `herdr pane get` and `tab list` tell you what a pane is called. Version one told a human to
  "press Enter in w2V:pJ" — an identifier that appears nowhere on his screen.
- **Vocabulary is Herdr's vocabulary: WORKSPACE, tab, pane** — and this document uses "workspace"
  throughout, including where it previously said "workspace". The earlier review of version one recommended
  collapsing to one noun and chose "workspace"; this overrides that verdict deliberately rather than
  quietly, on this section's own principle: Herdr's word is `workspace`, and an abbreviation is still an
  invented noun. The owner asked about naming three separate times, so the test is whether one word
  survives contact with `herdr workspace list` — and "workspace" does not. Version one invented singletons,
  benches, desks, GO and OPEN, and made "Support" simultaneously a place, a shape and a mode. **Do
  not invent a noun for something another program already names.** A review of version one recommended
  collapsing to one noun and one verb; using Herdr's own is the same answer with nothing left to
  remember.

**Acceptance test for the whole naming question:** can he, cold, open work, say what a workspace is
for, close it safely, and find what is waiting on him — with no coaching?

---

## 4 · The database

One file. WAL. One writer at a time, which SQLite guarantees and the measurement confirms.

**Measured before writing this** (Node 24.19 `node:sqlite`, 10 processes × 100 full-synchronous WAL
inserts):

- 1000/1000 rows committed, **0 failures**, max single insert 147.4ms, 216.3ms wall
- with another connection holding `BEGIN IMMEDIATE` for 600ms, a 75ms `busy_timeout` **failed visibly
  in 89.8ms with no partial write**; a retry after release succeeded in 0.85ms
- abrupt process exit inside an uncommitted transaction left 0 rows; `integrity_check` returned `ok`

**Therefore the write contract is: bounded wait, then an explicit retryable failure.** Durable commit,
zero wait under a held writer lock, and no second log cannot all be guaranteed at once — so we choose
durability and honesty, and give up "never waits".

Concretely:
- `busy_timeout` is small (100ms) and a failed write **returns an error the caller must handle**. A
  handler never blocks a turn on a lock.
- A write that fails is **retried once**, then surfaced. It is never silently dropped and never
  diverted to a spill file: a second log is the thing this whole design exists to remove.
- **Recoverability is a named tool, not a hope**: `wb doctor` runs `integrity_check`, reports schema
  version, and can export every table to JSONL. A nightly copy lands in the existing backup
  convention. The test is: can this be fixed at 2am with `sqlite3` and a text editor?

### Tables, and what each fact *is*

**The rule that decides what gets a table** — drafted as "measure what happens, never ask the worker
to log it" and corrected by review, because that version forbade the one table §7 imports:

> **Never ask for a record that DESCRIBES activity the system can already observe. Do ask for one
> that carries JUDGEMENT the system cannot derive.**

Judgement, not authorship, is the line. The evidence for the correction: the worklog's decay is not
self-reporting failing — 137 of 180 rows, and 6 of 6 on the two densest days, are `Completed task:`
lines emitted by a tool, so the decay is one-task-per-session against a session that lands ten things.
Meanwhile the genuinely agent-chosen record did not decay at all: ledger entries ran 14 and 11 on
those same days against a 13-day mean of 24. And commits are a poor automatic substitute here — zero
on nine of thirteen days, including all four of the densest.

So: `turn` still dies, the worklog is still retired, and `fact` and `issue` survive — for the right
reason.

**The channel with no table, which is the largest gap this specification had.** Measured across every
session file: **1,371 human turns, 516,931 characters** of the owner's own words — against 294 facts.
On 2026-08-12 he wrote 137 messages and 32 facts were banked; on 08-13, 99 and 14; on 08-14, 85 and
12. And in his words: *"99.9% of MY writing is into THIS box right here in pi. I am not hand making
notes almost ever."* So his primary authoring channel is the session itself, and half a megabyte of
intent has been passing through it with no destination.

This session proved it while the specification was being written. In one hour he stated three durable
things — that the machine may own the daily note, that determinism does not matter but checkpoints do,
and that he does not hand-write notes — and every one changed a section of this document. None of them
existed anywhere but a transcript until a session chose to bank one.

So `fact` rows may be **attributed to him**, and the rule is explicit because there is no automatic
moment for it:

> **The moment is a turn in which he states a constraint, a correction, or a preference. A session
> that hears one banks it before doing anything else.**

This is the measure-don't-log rule seen from the other side. Agent self-description decays, and the
human's own words are captured by the same failing mechanism — agent discretion — with no observable
event to fall back on. An attributed fact is judgement the system cannot derive, which is exactly what
§4's rule says to ask for.

- **`fact`** — durable things learned, the successor to the ledger. `kind` (decision, constraint,
  learned), text, `at`, source session, and the incident that produced it. 297 entries exist today and
  they are the only thing that imports (§7).

  **`provenance`, two values, and a nullable `check`.** Settled between two sessions after a dissent.
  `stated` means the owner said it; `derived` means we produced it. Attribution stays OUT of `kind`,
  because a second dimension inside a discriminator is the dumping-ground failure in miniature — and it
  is already a field today, just an unqueryable one: 28 of 297 rows name him in their prose and 22 carry
  a verbatim quote.

  A third value, `measured`, was proposed and rejected, on the evidence of the session proposing it: its
  first parse of the session corpus was every bit as measured as its second and returned a **false
  zero**, because it keyed on `entry.type` where the shape is `customType`. So "measured" never carried
  the property anyone wanted. That property is REPRODUCIBILITY, which is a second axis and gets its own
  nullable column: **`check` holds the command that re-runs the claim.** The resulting order is total
  rather than implied:

  > `stated`  >  `derived` WITH a check  >  `derived` WITHOUT a check

  and `provenance = 'derived' AND check IS NULL` finally names the set that must rank lowest — our
  unverifiable opinions — which today cannot be named at all. A false measurement cannot hide behind a
  label when the label is a command a later reader can run.

  **A stated fact quotes him verbatim**, which codifies what 22 of those 28 already do. The reason is
  not tidiness: his constraints outrank our conclusions by construction, so an agent's paraphrase being
  laundered into his instruction is the one abuse this ordering makes possible.

  **One fact, one claim, one provenance.** Somewhere between a quarter and a half of the current corpus
  is multi-claim — two independent heuristics disagree, 27% against 45%, and the conclusion does not
  turn on which — with a median of 515 characters, a p90 of 2390 and a longest of 4220. Provenance
  cannot be a property of a row until a row is a single claim. The cost is real and belongs here rather
  than in a later discovery: more rows, and a session must split what it learned instead of appending a
  paragraph at the end of a turn.

  **Expect tens of rows, not hundreds.** Two thirds of what version one banked as facts belongs in
  `issue` or in a skill, so the steady-state table is much smaller than 297. A table expected to hold
  300 rows and one expected to hold 30 justify different surfaces, and the smaller answer means `orient`
  can afford to be generous rather than clever.

  **Why this is what makes `orient` possible at all.** The corpus is 277KB across 297 rows, so loading
  it at session start would spend a real fraction of a context window before the first turn. The
  always-loaded set is `provenance = 'stated' AND kind = 'constraint'`: **32 rows, 11KB, median 312
  characters** — a 24x reduction, and short enough to use at the point of use, which a 4220-character
  fact is not even once loaded. Everything else is queried when its subject comes up.

  **Two stated facts can conflict, and one did today.** The two-value ordering says nothing about it, so:
  among stated facts on the same subject, **the most recent wins, and superseding is EXPLICIT** — a
  `supersedes` reference or a retired state, never inferred from recency alone, because recency lets a
  narrow clarification silently retire a broad rule. This is not hypothetical. §2 of this document said
  "his own notes stay authored by him"; he has since stated the opposite, and both are `stated`
  constraints. The always-loaded set is the one place a contradiction is guaranteed to be read, by every
  session, every time.
- **`event`** — append-only, what happened, **for happenings that have no other home.** Its kinds are the
  outcomes and judgements a surface cannot reconstruct from another table: **work landed, a command
  approved, a check passed, a handoff opened.** Everything version one scattered across a handoff log, a
  worklog and three signal files is one table with a `kind`.

  Four decisions, made here because leaving them open is what turns one table into a dumping ground:
  - **`kind` is a CLOSED set with a database CHECK.** An open string is the wide-discriminator failure
    this document rejects twice elsewhere; adding a kind should require a migration, which is the point.
  - **No event for a happening that is already a row.** *Amended 2026-08-15, when the wiring was settled
    in code.* An earlier draft of this list read "a session started, a message was sent" — but a message
    already leaves a `message` row, and a session a `session` row, each with its own timestamp. A
    `message_sent` event would be a **second source for "when it happened"** (§2) and a **dual write**
    (§10) — the exact defect that retired the `turn` table, whose absence this list forgot. So the "what
    happened" timeline is **DERIVED**: the message/session/issue rows are merged, by their own timestamps,
    with the `event` table — never copied into it. `event` carries only what no other table records.
    (One gap this exposed: `issue` has no `closed_at`, so a resolution is not yet timestamped for the
    timeline — a deferred fix, recorded rather than lost.)
  - **Typed columns for what a surface queries; a JSON `detail` only for what a human reads.** If a
    query needs it, it is a column. Version one's mail file holds 111 messages and 102 acks of shape
    `{ack, at, by}` in one file, so an ack is a different KIND, not a message with fields missing.
  - **`correlation` is an explicit column**, holding the id of the thing a multi-row lifecycle belongs
    to — a handoff, an issue. Never inferred from subject text: version one has 75 handoff rows of which
    **5 carry an id**, uses `state` as a second discriminator, and its reducer had to hand-join them.
- **`issue`** — a finding that outlives the session that found it (§5).
- **`signal`** — commits, calendar events, sampled focus, pull-request snapshots. External
  observations, each with its own `source`, each rewriting only its own rows.
- **`collection`** — one row per source, holding `last_attempt`, `last_success` and `last_error`.
  Without it "the world is empty" cannot be told from "this collector has failed three times", which is
  precisely the incident §6 cites: three network-denied runs once overwrote a good briefing with
  "nothing is asking for you". A surface reads this to say how old its data is and whether the silence
  is real — and it is the table that makes §6's honesty rule mechanical rather than aspirational.
- **No `turn` table.** Pi's session files already hold every turn, and copying them is the
  two-sources-of-truth pattern this document exists to remove. Where turn detail is genuinely wanted,
  derive it — and deriving IS a view rather than a second store, because the format is **published**
  at pi's `docs/session-format.md` with a `version` field and a migration history (v3 renamed
  `hookMessage` to `custom`). The contract for reading it: **assert the version, and fail loudly on a
  zero result.** A silent zero from a wrong key produced the false measurement in §10, and is the same
  failure as §6's empty-world cache.

Human surfaces are **views**, not tables. A day page, a week review, a glance, a briefing — every one
of them is a query with formatting, and none of them is a stored artifact that can drift.

---

## 5 · Issues, because three things nearly evaporated in one day

**The measured argument, which is stronger than the anecdotes below it.** All 33 of version one's
constraints were read individually, one row at a time. **22 of them have expired** — every one scoped
to a named ticket, order, pull request, branch or incident: "do not retry order 1149702", "defer the
`:new_design_system_customer` hook to the first customer PR", "those `/private/tmp` review artifact
paths are dead".

Those were never facts. **A constraint that expires is an issue**: it has a subject, a state, and a
moment when it stops being true. `kind=constraint` had become a scratchpad for in-flight product work
because version one had nowhere else to put it — so two thirds of what it banked as durable knowledge
was **mis-filed for want of the table this section adds.** One of them, "merging #329 without raising
raising the follow-up ticket leaves the same silent-give-up defect class that the merged PR shipped with", is still live today and
is an open issue rather than a fact.

That is the case for `issue`, and it was measured rather than argued. The three near-losses below are
the same hole seen from the other side:

1. A fresh-context review delivered four verdicts as a chat message and closed itself before writing a
   file. The file exists only because another session hand-copied it out of a transcript.
2. A production playbook correction was reasoned out in full and still exists only in a transcript.
3. A defect in the pane-control tool was found by a teardown harvest, not by anyone querying "what is
   broken" — because there was nowhere to ask.

An issue is: what was found, where the evidence is, what would settle it, who found it, and its state.
Deliberately ticket-shaped and deliberately **local** — it is about this machine and its own defects,
never about product work. Where a machine has a real tracker for product work, this does not compete
with it; where it has none, this needs none to exist.

**The acceptance test, and the feature is not built without it: a session reads open issues at start,
unprompted.** If `orient` does not surface them, an issue table is a second Jira nobody reads and must
not exist.

**Scoped and capped, or it reproduces the failure §1 opens with.** Across 137 sessions in 32
directories, "all open issues" is the radar's complete-and-useless list again. A session loads open
issues **for its own subject and repository**, at most five lines, with the rest as a count — the same
rank-and-cut rule every other surface obeys. An issue nobody has scoped to anything is visible only in
the coordination surface, which is where an unowned finding belongs.

---

## 5b · The channel

The owner: *"we genuinely need to bake in 'slack for agents'… the missing bit is the
metacommunication/alignment layer. I would like to see quite literally a slack-like TUI thing that all
the agents can use to talk to each other."* And on scope, when an earlier draft of this section tried to
justify it failure by failure: *"this is a build it and they will come sort of thing. Agents can ask
questions, post threads, findings, whatever. It's another communication channel for me as well."*

He is right and the earlier draft was wrong. **A channel is not a feature and must not be specified like
one.** Its value is that the uses are not enumerable in advance — gating it on the message types someone
could think of first is how you get a mailbox nobody posts in. So: **any participant may post anything.**
Questions, threads, findings, a status, a half-formed doubt, a correction, a link to a diff. No taxonomy,
no required fields beyond a thread and a body, and no permission model on a single-human machine.

**He is a participant, not an audience.** He posts, asks, and answers in the same threads, and that is
the second reason this ships early: §4 needs a capture path for the 516,931 characters he writes into a
session box with no destination, and **a message he writes is already a row.** The channel and the
attributed fact are one mechanism rather than two, so his intent becomes durable as a side effect of him
talking — the only thing that has ever worked.

### What must be true mechanically

Generality is the point; these are the three things that make it a channel rather than a folder, and each
was measured failing in version one on the day this was written:

1. **A thread per subject.** Two sessions exchanged 18 messages while this document was written and it
   was one argument, not 18 deliveries. That argument produced seven corrections, four of them defects.
2. **Delivery WAKES the recipient.** A message reaching a mailbox is not delivery: version one's mailbox
   drains on start or reload, `orient` did not drain it, a reload did not surface it, and
   `herdr agent prompt` did — because it causes a turn. A post that no one is prompted to read is a file.
3. **`delivered` and `read` are different columns, and a receipt the sender writes may only ever mean
   delivered.** 118 of 121 acks in version one land within two seconds of send because the sender writes
   them, so a session sat idle believing it was waiting while the other believed it had been read. If
   nothing can prove a message was read, the column does not exist rather than lying.

Everything else is emergent and should be left that way until a real use appears.

### Names, roles and voices

**Names attach to roles, not to workspaces.** He has raised the naming problem four separate times and
cannot remember what `w2V`, `w4F` or `w4H` are — and today two workspaces closed mid-conversation, taking
their only identity with them. A name that outlives the workspace is the fix, and `Carl reviewed it`
survives where `w4H said so` does not.

**A role is specifiable: a model, a mandate, and the facts scoped to it.** What made today's reviewer
valuable was a fresh context, a different model family and an adversarial brief — all three are role, and
all three are worth encoding. *Carl is good at reviewing pull requests* is a real claim about a role.

**A voice is presentation, and that is fine.** Its job is that a reader can tell who is speaking in a
shared thread without parsing a prefix, and if a distinguishable register makes the channel a place he
actually wants to read, that is a real function rather than decoration. Two things to hold onto anyway,
because both are cheap: a voice must not cost the reader lines — he has already said *"too verbose, it
shouldn't need any action from me"* — and an agent whose register includes opinions will bank opinions as
facts, which §4's provenance ranks last but does not prevent.

### The one real risk, named once

The failure mode of a general channel is **noise**, not wrong message types. That is the same problem
every surface in this document already solves and the same rule applies: rank and cut, cap what is shown,
count the rest. A channel where everything is posted and the unread count is 400 is version one's org
radar with a nicer frame. So a participant sees their own threads and their own mentions first, capped,
and the rest is a number — and the moment "catch up" costs more than skipping it, the ranking is wrong
rather than the posting.

## 6 · Surfaces, one question each

| Surface | The question | Shape |
|---|---|---|
| glance | what needs me right now, and what did I do yesterday | ≤5 pull requests, ≤4 lines of yesterday, everything else a count |
| day / week | where did the time go | a timeline that never invents a duration |
| orient | what is this session for, and what is open | the objective, the queue, open issues |
| coordination | who owes whom, what died on arrival | a query, not a hand-join — **deferred past day one** |

The coordination surface does not ship until answers can be correlated. Version one's review already
said so, and the numbers say why: 102 of 213 mail rows are acks of shape `{ack, at, by}`, and **an ack
is not an answer**, so a naive "did they reply" query under-reports what is owed. Correlate on the
handoff id — noting that only 5 of 75 handoff rows carry one today, and 8 of 35 subjects have only a
"handed off" row and no terminal state.

### The daily note, which is the whole point

Specified by the owner directly, and it is the surface everything else feeds: *"my daily note should
just keep regenerating itself as my day goes, instead of reading like a row in a database — I did this
stuff that was important, this stuff that the rest of the team doesn't need to know about but that I
should probably remember, this stuff's open, I had these meetings."*

So it is **prose in four sections, regenerated in place**, never a table and never a log:

| Section | The question | Source |
|---|---|---|
| What mattered | what would I say at standup | `event` rows meaning work landed, plus commits and merged pull requests |
| Worth remembering | what should I not have to rediscover | `fact` rows written today — the judgement half, which is exactly the half a system cannot derive |
| Still open | what is unfinished or waiting | open `issue` rows, unfinished queue steps, anything blocked on a person |
| Meetings | where did the fixed time go | calendar `signal` rows, which are the only records that carry a real end |

Rules for it, each following from something already in this document:

- **Regenerated wholesale on change, debounced.** Written when an `event` lands and not more often than
  every few minutes. No timer for its own sake: the file changes when the day changes.
- **It says at the top that it is generated, and when.** A generated file cannot also be an input, so
  anything the human types must reach the database through a capture path and appear in the next
  regeneration. Losing a hand-edit silently is the one failure this surface cannot have.
- **Nothing may exist only in the prose.** A session that writes a sentence into a day page writes the
  `event`, `fact` or `issue` it came from FIRST. Without this every regeneration silently deletes
  whatever the last one happened to say well — and the existing pages prove the failure is real, not
  theoretical: "Noted LiveView 1.1 colocated hooks as a possible cleanup" and "Fine as an advisor,
  unusable as an authority" appear in no event and no fact, so no renderer could reproduce them. They
  were written by an agent that wrote the prose without writing the fact behind it. With this rule the
  page is genuinely disposable; without it, ownership is a licence to destroy.
- **Sentences, not rows.** "Fixed the context gate that had been compacting sessions in silence" is the
  output; `{"kind":"win","text":"..."}` is the input. If a section has nothing in it, it is omitted
  rather than rendered empty — a heading with nothing under it teaches the reader to skim.
- **It never invents a duration**, and it never claims a day was quiet because nothing was recorded.
  Unrecorded time is named as unrecorded.

The week view is the same query over seven days, and the standup view is the first section alone.

Rules learned the expensive way:

- **Rank and cut; never list everything.** Bots, drafts, already-approved and anything untouched for
  30 days are counts, not lines. Sorting oldest-first put a 213-day-old pull request at the top of
  "what needs me right now" on the first real run.
- **Render from disk instantly; refresh behind the human.** Putting a network fetch in front of the
  output produced an empty popup for as long as the radar took. Stale and honest beats fresh and
  absent, so every surface states the age of what it read.
- **A cache that reports an empty world is a lie.** Three network-denied collector runs once overwrote
  a good briefing with "nothing is asking for you". A collector that cannot collect writes nothing and
  says so.
- **Never invent a duration.** A log entry is a stamp, not a clock-in. Only a calendar event or a
  sampled block carries a real end.
- **A field computed at write time is not a fact at read time.** Compute age, staleness and counts in
  the query.

---

## 7 · Nothing imports, and why that is not a clean-slate gesture

The owner: *"2.0 shouldn't import any facts, we're building a new system that will learn new things…
take what 1.0 learned and build a 2.0 that's better but knows nothing."*

An earlier draft of this section called the 297 ledger entries "the most valuable bytes on the disk"
and imported them. That was wrong, and the reason is sharper than starting clean: **those facts have
already been spent.** They were the design input that produced this document. Its second paragraph
says so — *everything below that reads like a rule was paid for by a specific failure* — and §2's
corollaries, §6's rules and §8's boundaries ARE those facts, promoted from rows into rules. Importing
them afterwards keeps the raw material after the part has been machined, and §2's own test says delete
one of the two.

Measured: 23 of 33 constraints already have more than 30% of their distinctive terms present in
`AGENTS.md` or in this document, 6 of them above 50%. The promotion has largely happened.

**What makes "knows nothing" safe is `AGENTS.md`, not the ledger**, and that is load-bearing enough to
state. It is 17 lines, it loads into every session's prompt independently of any database, and it
verifiably carries the ones that would hurt: the human presses Enter in production, the sandbox EPERM
trap that reports as "not owner", 1Password, Okta, Firefox for staging, the Atlassian MCP and the
`acli` prohibition. Day one's `orient` shows an empty constraint set, and that is acceptable **only**
because that file exists.

### So this section is a verification pass, not a migration

Once, before the old ledger is frozen, walk the 33 constraints and put each in exactly one bucket:

| Bucket | Roughly | What happens |
|---|---|---|
| Already a rule here or in `AGENTS.md` | ~23 | Nothing. It is spent. |
| Version-one specific and dead | 5 | Written off, named in the review so the write-off is deliberate |
| Still true and restated nowhere | 5, of which 2 are 2.0's | **The only risk.** Promote, or write off on purpose |

**The pass is done, by hand, one row at a time — and only TWO rows move.** "Knows nothing" is safer
than either the owner or the reviewer argued:

1. **His review scope**, and it is the highest-value single row in the corpus. *No review responsibility
   for one repository his organisation owns — that is a different team, even though team review requests
   land on him. His scope is the five repositories named in the work machine's `review-scope.json`.* This is durable, it is about HIM rather than any system, and it is load-bearing for
   §1's first question: without it the glance ranks another team's work as his. Measured in version one
   the day this was written — **four of the five pull requests it showed as "waiting on your call" were
   another team's** — so it is promoted into version one as well as specified here. It is a `stated`
   fact, never derived: version one's ownership collector tries to derive scope from GitHub team
   permissions, wrote `repos: []` after a connection reset, and that empty result was read as "no
   filtering". **An unproven scope is not a licence to show everything.**
2. **In Herdr, new things open in TABS, not splits**, with its incident: a split silently narrows the
   pane the agent is running in, which is also how a latent width bug in the status bar became a crash.
   §3 discusses Herdr's vocabulary and never says this.

Three more are real and belong elsewhere rather than here: the Excessibility CI knowledge (a review call
silently skips snapshots whose baseline is absent; the behavioural layer must be advisory because it has
no baseline while the exit helper treats any serious finding as blocking; the reusable workflow sets up
neither Elixir nor Playwright) goes to the accessibility skill, one domain rule goes to its project, and
one clause about handing over exact read-only AWS commands joins the production boundary in `AGENTS.md`.
Routing is not importing.

The same pass covers a population no earlier draft mentioned: **environment truths.** TCC and Apple
event refusals under the sandbox, the Calendar `sqlitedb` path and its WAL behaviour, `op` and the
Group Containers layout, the measured SQLite numbers in §4. These are facts about **this machine**,
not about version one. They stay true after 2.0 ships, they are not rules in this document, and
several of them cost hours to discover. They are not imports either — they are candidates for
promotion, and each is promoted or written off in the same pass.

Everything else needs no decision at all: pull-request snapshots, signals and briefings regenerate in
minutes; the worklog's rows are produced natively by `event` (§4); and the 13 existing daily pages are
handled by §6's draft rule rather than by an import.

### The cutover, because "nothing imports" otherwise produces two fact stores

`entries.jsonl` does not stop existing on its own. It is live — it took an entry eleven minutes before
this section was written — and `workbench_ledger` is still bound in the running extension. If `fact`
starts empty while version one keeps writing that file, this machine has **two fact stores** for the
whole length of a transition described as "piece by piece": §10's own "no second log, no dual write",
arrived at by accident rather than by decision.

So the rule is a cutover rather than an import:

> **On the day `fact` accepts its first write, the version-one ledger is frozen read-only, archived
> beside the backups, and `workbench_ledger` is retired.** Frozen, not deleted — a reader may still be
> pointed at it; nothing may still write to it.

`wb doctor` reports the count of constraints with nothing pointing at them (§4's `taught`) in the same
breath as `integrity_check ok` — on a corpus 2.0 grows itself, which is the only corpus it will have.

## 8 · Boundaries that do not move

- **In production, the human presses Enter.** For any production console or remote write, the exact
  reviewed text is prefilled into a visible pane and nothing submits it. An approval dialog does not
  authorise submission; no trailing newline, no `send-keys enter`, no shell substitute.
- **Typing is only inert where it is provably inert.** "No Enter" means nothing in `nvim`, `less`,
  `psql` or a REPL, where a keystroke acts immediately. Prove it with `herdr pane process-info`: the
  foreground process must be a shell, and must *be* the shell rather than something the shell
  launched. Refuse text containing a newline, a tab, or any control byte. Fail closed.
- **Wait, do not poll.** `herdr pane wait-output` searches the existing snapshot and returned a match
  in 0.02s. Always send a timeout — Herdr's own help says it waits indefinitely without one, which for
  an agent is a turn that never ends. Wait for what a command PRINTS, never for a prompt: this
  machine's prompt is Powerlevel10k and `user@host` appears only in the terminal title.
- **Ask the arbiter, not your own bookkeeping.** A test that reads my own config files proves only
  that I was consistent. `herdr config check` is what proves the program agreed — and its *output*
  matters as well as its exit status, because it reports "kept keys.X, disabled keys.command[N]" while
  exiting 0.
- **Route through the model only when the decision needs what the model knows.** A relay is not a
  decision. A teardown command that asked a model to hand a one-line command to the human earned the
  verdict *"too verbose it shouldn't need any action from me"*.
- **A gate that can only fire once has not fired.** A context-pressure check latched the highest rung
  it ever reported, so the second time any session filled up it compacted in silence. Every rung
  re-arms when the pressure drops.
- **Reconciliation cannot depend on a clean exit.** Measured twice: `herdr workspace close` delivers
  `HUP, HUP, TERM`, a shell trap got only its first line out, and a Pi `session_shutdown` handler
  doing a *synchronous* write never ran at all. So state must be consistent **before** a close, and
  the close path must be the one the human already presses.
- **No provider, model or vendor is part of the design.** They are configuration, and the second machine
  is the proof of why: at home he uses Claude and a local Ollama endpoint, and there is no Okta, no SSO,
  no corporate secret manager and no ticketing system on it at all. Nothing in this document names a
  model, and nothing built from it may branch on one.

  So a role (§5b) states a **capability requirement**, never a product: *not the weights that wrote the
  thing under review*, *long enough context for a whole file*, *cheap enough to run every turn*. The
  mapping from a requirement to an actual endpoint lives in local configuration on the machine that has
  those endpoints, and a machine with fewer of them runs the same design with fewer options.

  **Local models are first-class, which has a consequence worth stating.** Anything that assumes
  frontier capability must **degrade honestly rather than break**: a review by a small local model is
  still a different reader with no sunk cost, which is most of where the value came from — and §4
  already ranks its output correctly, because a derived fact without a check is a derived fact without a
  check whoever produced it. What must not happen is a surface that silently does nothing when the
  configured model cannot do the job. Say it could not, the way a collector that cannot collect says so.

  **The same applies to credentials.** How a machine authenticates to anything is local configuration —
  an environment variable, a keychain, a file, a human typing it — and no part of this design may know
  which. Version one's boundaries about a specific identity provider, a specific secret manager and a
  specific browser for staging describe **that machine's work**, not this architecture, and they stayed
  behind with it (§8c).
- **Never blank a transcript you cannot carry.** A planning session with 112 entries of analysis was
  replaced with an empty one reading "nothing was open to carry forward", because the check asked
  whether anything was *active* rather than whether anything had been *banked*. Those are opposite
  situations.

---

## 8b · One repository, three pointers

2.0 is a clean repository with this document as its first commit. Version one had no repository
boundary because its code lives wherever another program insists on loading from — and the review
found that this is smaller than it sounds, because **all three loaders take a pointer**:

- **Pi** already loads a local-path package: `settings.json` carries
  `{"source": "~/.pi/agent/packages/elixir-pi", "extensions": [...]}`. So `pi install /path/to/repo`
  needs no symlink, and `pi list` is its arbiter.
- **Herdr** is nine absolute `command=` paths plus `plugin_root` in `config.toml`. Repoint them.
- **The `ai-*` CLIs are already pointers** — 95 to 274 byte wrappers, one `exec` line each — and
  `briefing/*.mjs` is loaded by nothing except those wrappers.

So: one repo with a `bin/`, and an install target that writes three pointers. Four roots was never
four components; it is one component seen through three loaders.

**And the deploy check is not optional, because drift is already happening in version one and both
arbiters report success.** `herdr-plugin.toml` is version 0.7.0 with 22 actions; the registry cache at
`~/.config/herdr/plugins.json` still holds version 0.1.0 with 3 actions from nine days earlier, and
still names a mode that was renamed. Two chords are bound to plugin actions
(`anmoore.ai-workspaces.triage` and `.notes`) that **do not exist in the registry at all** — and
`herdr config check` says `config: ok`, while `herdr plugin list` prints neither the version nor the
action list. So §8's "ask the arbiter" is necessary and **not sufficient**: this divergence lives in a
field no arbiter prints.

`wb doctor` therefore compares, and **fails on mismatch even when everything works**: manifest version
and action ids against the registry cache; the Pi packages entry against the repo's extension list;
every wrapper's target against a real file.

That "even when everything works" is the point, and it was settled by experiment rather than argument.
The owner pressed both chords and **both work** — Herdr resolves `plugin_action` against the manifest at
runtime, so the stale cache breaks nothing. Which is precisely why it has survived seven days: *a drift
that breaks something gets fixed within the hour.*

The real defect is that the cache is a **mixed-truth file with nothing on its face marking which half is
which.** `plugin_root`, `manifest_path` and `enabled` are load-bearing — they are how Herdr finds the
plugin at all — while `version`, `description` and `actions` are a nine-day-old snapshot. And the harm
lands on a **reader**: two separate sessions read it, concluded two chords were probably dead, and one
of them needed a human keystroke to be disproved. A future session asking "what can this plugin do?"
gets three actions instead of 22 and a noun that was retired.

So §8's rule needs its caveat: **an arbiter that answers "ok" while a cached copy disagrees is worse
than no arbiter**, because §8 has taught the reader to trust it. Both arbiters were asked here —
`herdr config check` said `config: ok` and `herdr plugin list` printed neither the version nor the
action list. The one that would have answered, `herdr plugin action list`, reports all 22. **When you
ask an arbiter, ask the one whose output contains the field you care about.**

Checked and cleared while writing this: `[update] manifest_check` in Herdr's config governs the
agent-detection manifest fetched from `herdr.dev/agent-detection/index.toml`, not the plugin registry,
so the stale version feeds no update or compatibility check.

## 8c · The clean room

He is rebuilding this from scratch on a second machine — a personal Linux box, not the work laptop —
and in his words: *"if I send this whole repo over to a clean room kind of environment on my personal
machine then there's nothing to bring across. I am rebuilding the whole stack over there."*

That deletes a design rather than adding one. Earlier drafts of this section worked out how two
workbenches would share state: two databases with `fact` authoritative on one, then a work-versus-
personal partition once it became clear that **51% of version one's facts name work systems, tickets,
orders or customers** and must never land on a personal machine. None of that is needed. **Nothing
travels except this repository.** No sync, no merge, no partition, no export format, and no SQLite file
on a shared filesystem — which was a known corruption path anyway.

Two consequences, and the first is the reason this section still exists:

**THE REPOSITORY MUST BE SELF-SUFFICIENT.** If it is the entire transfer, then anything a builder needs
must be in it. That is a much sharper requirement than "portable", and it is what retired the work
references this document used to carry: five internal repository names, a ticket key and two pull
request numbers, which were evidence for claims a clean-room builder cannot check and has no use for.
They are gone; the claims they supported are stated without them. `AGENTS.md` at the root of this repo
carries the general boundaries — §7's "what makes knows nothing safe" is THAT file, not the work
machine's, whose Okta, staging, ticketing and CLI prohibitions are about work that does not exist on the
other side.

**A signal source is still a plugin**, and now for a plainer reason than portability: the other machine
has no work calendar, no work repositories and no reason to sample which application had the screen at
14:05 on a Tuesday. It will grow its own sources. Nothing in the core may branch on platform, and a
missing source is an absent signal rather than a broken surface — `collection` already records
`last_attempt`, `last_success` and `last_error` per source (§4), so a day with no screen track says so.

**What actually crosses**, in full: this specification, its two reviews, the issue list, `AGENTS.md`,
and the README. Four commits and 59KB. Everything else the other machine will learn for itself, which
is the point of §7 — and it starts with the advantage version one never had, which is that it knows
what it is building before it starts.

## 9 · Day one

The smallest thing worth using, because this gets re-dogfooded and a design that only pays off when
complete will not survive contact:

1. **The database and `wb doctor`.** Schema, migrations, integrity check, JSONL export. Nothing else
   ships until this can be repaired.
2. **`fact`, empty**, with `provenance`, `check`, `supersedes` and `taught`, surfaced in `orient`. Its
   first write is the cutover moment: the version-one ledger is frozen read-only and
   `workbench_ledger` is retired the same day (§7). An empty constraint set on day one is safe because
   `AGENTS.md` carries the boundaries that would hurt.
3. **A signal writer, before anything reads signals.** The original ordering shipped `glance` "from
   signal rows" while the collectors were deferred past day one, so day one would have rendered an
   empty glance. At least the pull-request collector ships here.
4. **`glance`.** The two questions, ranked and cut, with the age of the data. Its second question needs
   a source: **`event` must carry a kind that means "work landed"**, or nothing answers "what did I do
   yesterday" once the worklog is retired. That is the gap review found — every `event` kind proposed
   in §4 describes mechanism, not outcome.
5. **`event`, written by the pieces that already exist** — but only for happenings with no other home:
   a handoff opened, an approval, a verification result, work landed. Session start/end and a message are
   NOT events; they are their own rows, and the timeline derives them (§4, amended 2026-08-15).
6. **The channel (§5b)**, at its smallest: a thread per subject, delivery that wakes the recipient, and
   `delivered` separate from `read`. It ships this early for one reason — it is also §4's capture path,
   so a message the owner writes becomes an attributed fact without him doing anything else.
7. **`issue`, with `orient` reading it at start.** If this acceptance test fails, stop and delete
   the table rather than shipping a tracker nobody opens.

Then, and only with evidence that each is wanted: the day and week views, the coordination query, the
signal collectors.

---

## 10 · What 2.0 does not do

- **No meta-orchestrator session.** The database is the bus. A session is a context window with a
  lifetime — it compacts, forgets, goes idle and dies — and must never be in the delivery path of
  another session's message.
- **No mode-switch keybindings.** The five chords go because `Shift-S` meant "switch this Pi to Support
  mode" while the Support desk sat next to it, and the owner kept tripping over the collision.
  **Mid-session mode change stays**, including `workbench_mode` and `/mode`.

  The number this originally cited was wrong, and the correction matters more than the conclusion. A
  recount of all 137 session files found 56 `anmoore-work-mode` entries in 40 sessions — 29%, not the
  claimed near-zero — and **45 of them mid-session** rather than at launch. "Zero in any session born
  in the last three days" was false twice over: a project session born 2026-08-13 switched at
  19:51:35Z, and the session born into planning at 2026-08-14T17:34:32Z switched to workbench **seven
  seconds later** — that was this specification's own drafting session, mutating its mode while the
  document asserted that a mode is not mutable state.

  How the false number happened, which is the durable part: the first parse looked for
  `entry.type == "anmoore-work-mode"` and returned a silent zero, because the real shape is
  `{"type":"custom","customType":"anmoore-work-mode"}`. A zero from a wrong key is indistinguishable
  from a zero that means something. It was caught only by doubting the zero. **A measurement that
  returns nothing must be proven capable of returning something.**
- **No second log, no spill file, no dual write.** See §2 — and note the one that would arrive by
  accident rather than by decision: version one's ledger stays live until it is explicitly frozen, so
  "nothing imports" without §7's cutover sentence produces exactly the thing this line forbids.
- **No mirrored Herdr state.** See §3.
- **No metrics that never changed a decision.** Unread broadcasts, message-exchange ratios and generic
  drift are all deleted before they are written: a broadcast is *mechanically* unread, because a
  session drains its mailbox only when it starts.
- **No taxonomy on the channel.** Any participant posts anything (§5b). The thing 2.0 does NOT do is
  gate posting on enumerated message types, which is how a channel becomes a mailbox nobody uses. What
  is ranked is the reading, never the writing.
- **No hand-authored machine documentation.** If a document describes something the machine knows,
  the machine generates it.

---

## Settled, and by whom

Every question this document opened has an answer, and three of them were settled by a fresh review
arguing with the session that wrote it rather than by either alone.

1. **Which markdown does the machine write into** — all of it. The notes are a machine-owned draft with
   full access (§2, §6). His correction: *"the ai can and should have access to all the human notes… I
   am not hand making notes almost ever"* — 99.9% of his writing goes into the Pi box, which is why §4
   grew an attributed fact instead.
2. **Its own repository** — yes, with this document as the first commit (§8b). Settled by him, and the
   mechanical argument arrived the same day: the commit named for this specification did not contain
   it, because `/.config/*` had swallowed `docs/` and nothing said so.
3. **A `turn` table** — no (§4). It would duplicate Pi's session files and put a write on the hottest
   path, and turn geometry does not answer "what did I do" anyway.
4. **Provenance** — two values, not three, plus a nullable `check`. The third value was rejected on the
   evidence of the session that proposed it: its own first parse of the corpus was every bit as
   "measured" as its second and returned a false zero.
5. **Edges** — `supersedes` and `taught` only, both with a reader today, and no general
   `edge(from, to, type)` table. `subject` survives as a discovery tag and is explicitly **not**
   load-bearing for precedence, because version one already proved that free-text subject matching
   fails silently: `priorPlan` needed three shared words and still matched the wrong plan, which is why
   `handoffId` exists.
6. **What imports** — nothing (§7), because the facts were the design input rather than data. What
   remains is a bounded verification pass and a cutover.

What is left is not a question but a decision with a deadline: the 13 existing daily pages have no
database behind them, so §6's first render destroys them. Mine them, move them aside, or write off the
loss — on the day the renderer ships, not after.
