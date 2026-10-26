# Cohesion off the happy path — audit and plan

**2026-10-13**, Andrew + Uqbar. Status: partly built; each cause carries its own status line (as of 2026-10-19; PRs marked unmerged are open). Built from four read-only audits of the repo and
the live store on the evening of 2026-10-12 (design docs vs code; the server's lifecycle; the
operator surfaces; the system's own records of friction).

## The diagnosis in one line

The README promises *"they come to your door when something is yours to decide; everything else
stays out of your way."* On the happy path that holds. Off it, the product has **many ways for
work to stop and one way to tell you — and most stops never reach it.**

The measurement that says so, from the live store at 23:50 on 2026-10-12:

- Every "what waits on you" surface read **zero**: `roster` nobody on the clock, `Needs.list() → []`,
  `awaiting: 0`, `health: ok`, suggestions `[]`, `quiet`.
- Meanwhile **three worklines were dead-ended** holding 15 unlanded commits: #242 (QA can't run
  `release:smoke`, the permission classifier refuses it; the ask was answered, the problem stayed,
  the item vanished), #241 (QA's drive tool is text-only and can't reach the room pixels), #209 (a
  builder waiting three days on a lead's "go" across a shift change). Plus four open blockers on the
  sheriff's beat and five high-priority plumbing tickets, all `routed: false`.
- Six weeks of messages: **80 "⚠ stuck after 3 nudges" posts on 30 threads**, 242 nudges, 225
  "server is restarting" notices, 60 "stranded" mentions.
- Three weeks of commits: 1,038, of which **~36% are lifecycle plumbing fixes** (worklines, merge
  queue, wakes, restarts, stranding), 25% office toy, 15% stage-doc commits.

So the feeling "good pieces, not cohesive off the happy path" is exactly right, and it has four
causes. Each is below with its evidence and its fix.

## Cause 1 — one door, many stops, most stops don't reach it

**Status (2026-10-19): mostly built.** On main: a landing is merged only when GitHub says so (#233), `publish_failed` and `release_failed` (#234), `quota` and `no_seat` (#235) are Needs with answers, one stale-turn clock and one quiet-workline clock (#239), and a workline nothing has moved past the quiet window is a stalled Need. Open: the stalled Need's verbs nudge / hand off / close (#446, unmerged); one landed-alert row and wording (#459, unmerged).

**Three mechanisms mean "waiting on the operator"** (`server/lib/server/`): the `thread.awaiting`
column (workline gates, worker questions; `attention.ex:257-386`), `prompt` message rows (pane
dialogs, asks with options, the PM's release gate; `attention.ex:81-335`, `release/pm.ex:282`), and
the sheriff's beat thread (`sheriff.ex:38`). They settle differently, nag differently (gates nag
daily forever and wake the parked lead each time, `maintain/sweep.ex:170`; asks and the release gate
never nag), and `respond/3` answers the *newest* prompt on a thread, so a key meant for the release
gate can land in a pane dialog (`attention.ex:236`).

**Red goes four places depending on where it happened.** A red verify stays at verify; a red merge
gate, QA fail, review changes and red PR checks bounce to build. Sheriff reports go to the beat only
when a sheriff exists; the no-sheriff fallback into Needs exists only for a red verify
(`office/needs.ex:226`). A DIRTY PR is relanded silently, a red one is reported (`jobs/keep_up.ex:35`
vs `:53`).

**Outcomes that matter ride on notices that wake nobody**: a failed release cut (`release/pm.ex:538`),
a failed publish (posted on an already-closed thread, `workline.ex:1287`), seatings.

**"Merged" is claimed before GitHub merges.** The thread closes, the ticket is done, the toast fires
at the local gate (`workline.ex:1269-1278`); `gh pr merge --auto`'s result is ignored
(`workline/publish.ex:25`). Auto-merge refused, BLOCKED, or checks pending forever is not handled;
the only later signal is a "stranded" item after an hour, whose recovery verb deletes the worktree.

**Silent by construction**: Claude usage limit with a single crew (`shifts.ex:196`), an ollama plan
window spent (every wake held, `switchboard.ex:302`), HTTP 429/402 (not detected anywhere), no seat
of a needed kind for planner/builder/qa (`workline.ex:1233`, only reviewer posts), a workline the
maintain sweep already flagged once (unique slug, so once ever, `maintain/sweep.ex:193`), a stuck
workline after the operator replies (nudge budget never resets), follow-ups on a workline that never
closes, a release gate answered "not yet".

**Settling is wrong.** An item leaves when its *answer exists*, not when the *state moved*. #242 is
the incident: Andrew answered the ask, QA was still refused, the item was gone, and nothing has
moved since.

### The fix: Needs is derived from state, and every stop is a Need

The invariant: **a workline (or thread with work) that cannot move without a human is a Need, and
stays one until it moves.** Not "until an item was raised and answered."

1. **Derive, don't raise.** `Server.Office.Needs` becomes a pure function of state — stage, last
   movement, open prompts, job state, PR state, seat availability, quota — and the raise-an-item
   paths (`park_on_operator`, `Sheriff.report`, the stuck post, notices) become *facts the derivation
   reads*, not the thing that makes an item exist. An answered ask whose workline hasn't moved in the
   quiet window is a Need again, with the history attached ("you said allow; QA still refused").
2. **One kind per stop, each with its answers**, the asks-with-answers rule applied to the whole
   table above. New kinds: `publish_failed` (republish / open PR by hand), `pr_blocked` (the
   merged-but-unmerged case: rebase / close and reland / show me), `release_failed` (retry / rollback),
   `quota` (single-crew usage limit, ollama window spent: switch crew / wait until <reset> / clock
   out), `no_seat` (hire <kind> / hand to <who>), `tool_denied` (#242's class: allow / do it by hand /
   send back), `stuck` after nudges whether or not a sheriff exists.
   `pane_stuck`: a spawned pane that registers no session within a few minutes (2026-10-13: six
   windows sat on Claude Code's settings-warning dialog, the board said "at a desk", the roster said
   nobody) — with the screen's last lines and retry / kill.
3. **The sheriff takes a copy, never the item.** Red reaches the sheriff's beat *and* counts in the
   header; the sheriff resolving it is what settles it. No code path's visibility depends on whether
   a seat exists.
4. **"Merged" means merged.** The thread closes and the ticket is done when `gh pr view` says
   MERGED (KeepUp already polls); until then the stage is `landing` and the card says
   "landing · waiting on GitHub's checks". A refused auto-merge, BLOCKED, or an hour of pending is
   `pr_blocked`.
5. **One answer path.** Answer by prompt id everywhere (asks already do); `respond/3` on a thread
   stops guessing the newest prompt. Pane dialogs are typed only after re-reading the screen.
6. **One rule for red, decided:** a red *anywhere after build* bounces to build on the same branch
   with the finding — the build kept, fixed with its original context, never redone (verify joins
   the others; `Jobs.Verify.finish` and `scripts/workline-verify.sh` call `bounce`). The lead is
   woken; the operator sees a count.
7. **One stale clock.** 600 s (`presence/thinking.ex:119`), 3 h (`staffing.ex:48`) and the 60-minute
   quiet band become one named setting with one meaning.

**The check (goal-driven).** A seeded-db test per row of the failure table in
`docs/plans/`'s audit (verify red, verify can't run, gate unanswered, land crash ×3, publish fail,
auto-merge refused, pane died, model hang, usage limit single crew, ollama spent, no seat per kind,
stuck after nudges, stuck after reply, release cut fail, new release won't boot) asserting
`Needs.list()` is non-empty with the right kind and ≥1 action. Plus one invariant test in the gate:
**any open thread holding work with no movement past the quiet window is a Need or a duty.** That
is the test that would have gone red on 2026-10-12 with three stuck worklines and an empty inbox.

## Cause 2 — the vocabulary and the state model forked across surfaces

**Status (2026-10-19): in flight, all unmerged.** Glossary and its gate (#438); `TLON_OPERATOR` is a handle everywhere (#440, #443); one seat status on the server (#461), the office (#474) and the mod's `/thread` crew line (#468); one key table and one meaning per key (#441, #442) and the room / front desk words (#444). The renames (`Server.Crew`, `Server.Staffing`) are `pending:` glossary rows, not done.

One concept, several names or glyphs, each surface choosing its own:

- **`○`** is "nobody at a desk" on the board, "idle" on the crew screen, "warm" in the mod's
  `/thread` pane, "cold" in `tlon-cli roster`. Warmth has four renderings (TUI crew ● ! ○ ◌; card
  "mid-turn / on call / waiting on you / in the lounge"; mod ● ○ ·; CLI ● ○).
- **"lead"** is two people: `Channel.designated_lead` (the manager) and `Coworker.lead/1` (the first
  builder, the tech lead). **"gate"** has four meanings (`mise run check`; a stage parked on the
  operator; the PM's release gate, which is Needs kind `dialog`, not `gate`; hard limits).
  **"crew"** is the whole cast, a named shift, and `Server.Crew` the tmux spawn backend.
  **"staffing"** is tertius assigning a thread and the per-minute tmux pass. **"triage"** is
  blockers/failed checks/unled in the TUI and "what awaits the operator" on the web.
  **"calendar"** is Oban schedules in the TUI and `.ics` meetings in `Server.Calendar`.
- **Stages**: the reader shows the full ring `intent…verify…review→landed`; the board folds intent
  into SPEC and verify into BUILD (`kit/crew.ts:106-108`); the mod band shows the raw stage.
- **`verify_failed`** is blocking in Needs and sticky in alerts (`alerts.ex:98`).
- **"Waiting on you" has two sources**: header/inbox read `/api/office/needs`; the home card reads
  thread flags only (`kit/crew.ts:34`, `main.ts:853`), so stranded, job_failed, issue, seats and ask
  items show in the header and not on home.
- **`TLON_OPERATOR`** is your handle in the server, the TUI and the README, and a boolean in the mod
  (`tasks/claude.toml:29`, `mod.ts:391`). `"andrew"` is hardcoded in `park_on_operator`
  (`workline.ex:918`) and `graded/2` (`:668`) against `Application.get_env(:server, :operator)`
  elsewhere — **auto-land after grading never fires under any other operator name.**
- **Keys**: `R` = reload / review branch / restart server / retry job; `S` = settings / next crew /
  save Nina / start ticket / raise cap; `d` = docs / dismiss / delete ticket / delete schedule / forget
  fact / throw out idea; `x`, `c`, `f`, `p` likewise. The hint says `tab crew`; `c` is crew.
- **Persona vs soul**: two stores for one concept (`Server.Persona` in Postgres, `SOUL.md` per machine).
  **Whimsy**: the toy doc's `office.json` mode/whimsy became a server-side `wackiness` 0–3.

### The fix: one glossary, one renderer per concept, a gate that holds it

1. **`docs/glossary.md`**: the nouns, one meaning each, with the renames decided here: *lead* (a
   thread's) vs *tech lead* (the bench's); *gate* only for a stage parked on the operator (the
   release gate becomes kind `gate` with `scope: release`; `mise run check` is *the check*); *bench*
   = everyone seated, *crew* = a named shift only (`Server.Crew` → `Server.Spawn`); *staffing* =
   assigning a thread, the tmux pass is *the sweep*; *triage* one meaning; the TUI's `a` is
   *schedules*, *calendar* stays for meetings.
2. **One seat-status enum rendered by one function.** `Server.Coworker.status/1` →
   `working | waiting | idle | off | cold` (or fewer), and `kit/crew.ts` renders it once for the TUI;
   the mod band, CLI roster and web call the same mapping. `○` means one thing.
3. **One workline-stage renderer.** Either the board grows INTENT and VERIFY columns or the fold is
   named in the glossary and the reader's ring folds the same way. The mod band uses the same words.
4. **Needs is the one source for "waiting on you"** — the home card, the header, the mailbox, the
   desktop alerts and the operator band all read it; alerts derive their level from the kind.
5. **`TLON_OPERATOR` is a handle everywhere**; the mod's flag becomes `TLON_OPERATOR_MODE=1`; the
   two literal `"andrew"`s go.
6. **A key map with one meaning per key**, mode-specific exceptions declared in one table
   (`tui/keys.ts`) that `detail()` and the foot render from — then `test/keys.test.ts` fails on a
   collision not in the table. Hints come from the same table.

**The check.** `check:names` grows a glossary pass (every term in the glossary resolves to its one
module/field; a doc or comment using a retired name fails); `test/keys.test.ts`; the status-enum test
asserts each surface's rendering comes from the one function.

## Cause 3 — degraded states are drawn as nothing, or as the toy

**Status (2026-10-19): half built.** On main: a down channel is a held, dimmed snapshot with its age and the verb, never the fire drill. Unmerged: tmux not up is an error, not an empty office (#450), and a tmux down past the stale clock settles open prompts (#460); the toy answers every card's read and a failed read says why (#463), kept per card (#471).

- **A real outage looks like a fire drill.** Channel down 10 s burns the rack, the crew screams and
  the floor reads FIRE DRILL (`office/kit/sim.ts:603-617`, `rooms/wide.ts:411`) — the same art as
  the sandbox's `f`. The only true signal is a red `channel down` in the header, which names nothing
  to run.
- **Two sources for "someone is on it".** `Server.Office.status`'s `live` reads tmux windows; the
  roster reads registered sessions. A window with no session draws a coworker at a desk.
- **Room and pane disagree when down.** The room holds the last good snapshot (`Sim.held`); the pane
  renders `view()` over the *empty* one (`data.ts:39`, `main.ts:190`): home says "nothing waits on
  you", the crew screen is empty, a person card says "not in this office any more"; `needs()`
  returns `[]` on error (`data.ts:94`) so the header's flag disappears mid-outage. No surface shows a
  snapshot age.
- **Empty results read as truth**, against the server's own law: `Tmux.list_windows` returns `[]`
  on error (`tmux.ex:76`) so every pane prompt resolves "window closed", sessions end, and every
  mid-turn thread gets "the machine restarted"; the `gh` readers return `[]` (`publish.ex:41-95`) so
  PR trouble is unseen; KeepUp swallows exceptions into a log line. The mod: `get_dossier` fails
  before the first good one → no brief and no notice (`mod.ts:104-110`); a thrown call logs nothing;
  the brief's staleness line measures last activity, not fetch age; `prompt.submit` awaits
  `get_dossier` with no client timeout (`mod.ts:460`) under a header that says "a slow or down
  server never holds a prompt."
- **Refresh has no in-flight guard** (`main.ts:2053`): a slow server stacks refreshes.

### The fix: stale and honest beats fresh and absent (spec §6)

1. **Errors propagate as errors.** `Tmux.list_windows`, the `gh` readers, `data.needs()` return
   `{:error, why}` / throw; callers either keep the last good value *and say its age* or skip the
   action. No code path turns "couldn't ask" into "nothing there".
2. **The held snapshot is held everywhere**, with age: header `as of 2m ago`, the pane renders the
   held view with a dim rule, cards keep content. One `held` flag on the data layer, not two
   behaviours.
3. **An outage has its own look and its own line.** Keep the held room, dim it, and put the fact and
   the verb in the header: `channel down 2m · mise run server:restart`. The drill stays a play key
   and a *long* outage's easter egg if wanted, never the first signal.
4. **The mod**: a timeout on `get_dossier` in `prompt.submit` (keep the last brief, say "brief as of
   …"); a one-line notice when there is no brief; a thrown call logs.
5. **One refresh in flight** at a time.

**The check.** `office/test/down.test.ts` runs the TUI against a data layer that fails: the header
carries the age and the verb, the pane keeps the held content, the needs flag does not vanish.
Server tests for the tmux and gh readers on error assert `{:error, _}` and that no prompt is resolved
and no session ended. An adapters test for the mod with a slow `get_dossier` asserts the prompt
returns within the timeout.

## Cause 4 — off the happy path the office hands you to a shell

**Status (2026-10-19): mostly open.** Only the stalled Need's verbs exist (#446, unmerged). The recovery routes (`send_back`, `republish`, `reopen`, `skip_qa`, `/api/release*`, `bench/hire`, `clock_out`) and the release card are not built.

Operator verbs that exist only in `tlon-cli`/mise/gh: release cut, status, rollback, smoke (no
`/api/release*` route at all; the office shows a cut as a pizza); `send-back`, `track`, `approve
--skip-qa`, `reopen`, republish (doesn't exist anywhere), `record-verify`, `hire` for a missing
kind, `flag`, epic create/link, ticket body/status, coworker effort, clock-out (iex only),
force-restart, and PR/CI state. The Needs kinds that do exist carry verbs; the stops in Cause 1
don't, so each one ends in `mise run …`.

### The fix: no Need without a verb; the verbs get routes

1. **Rule: every Needs kind carries ≥1 action**, enforced by a test over `needActions`
   (`office/tui/main.ts:534`) × `Needs` kinds. When the recovery genuinely is shell-only, the item
   *says the command* (as `launch.sh` already does for a down server).
2. **Routes for the recovery verbs the Needs above need**: `POST /api/worklines/:id/send_back`,
   `/republish`, `/reopen`, `/skip_qa`; `POST /api/release/cut|rollback`, `GET /api/release`;
   `POST /api/bench/hire`; `POST /api/presence/clock_out`. The TUI gets a release card (live sha,
   unreleased count, releasable and why not, cut / rollback) — the operator band already has the
   numbers.
3. **The three plumbing tickets that break QA itself go first**, or every QA'd workline dead-ends
   again: #176 (a sandboxed session can't run `release:smoke`), #162 (`office:drive` can't reach the
   wide room), #204/#159 (concurrent gates share `~/.hex`).

**The check.** The `needActions` × kinds test; a route test per verb; the live check is
`mise run release:status` and the office's release card agreeing.

## Cause 5 — the docs lie about what's built

**Status (2026-10-19): in progress.** Status lines on the stale design docs and the office `AGENTS.md` souls line are the D1 pass (#479, unmerged, plus the plan docs in this change); the glossary gate (#438, unmerged) is the start of the cite check.

Not a UX cause by itself, but the thing a weaker model trusts: five design docs still say
"proposed" / "nothing built" for shipped work (home-space, toy, souls, uqbar, git-toolbox); the PM
doc's body says `refs/heads/release` and `Release.Pointer` (it is `refs/heads/live`, no module); the
TUI handoff says `tlon` opens the TUI (the README and the build: `tlon` serves, `tlon office`); seven
design docs cited from moduledocs don't exist in `docs/plans/` (the 08-17/08-19/08-27/09-08/09-17
ones, probably still in ficciones); the roster's temperament/voice disagree with `Persona`;
`server:spawn`'s help still says "pi pane"; `adapters/{pi,footer,consult,reload}` are empty
`node_modules` husks.

**The fix**: one docs pass in the same change as each phase above (status lines, the two
contradictions, the dangling cites moved or dropped, the husks deleted), and `check:names` extended
to fail on a `docs/plans/` cite that doesn't resolve.

## Cause 6 — the operator's own delegate lives outside the office

**Status (2026-10-19): built.** On main: Uqbar is a pane the server spawns on its own study (#222), kept warm by a 50-minute check-in (#223) and one memory with its study's facts (#225), and drivable from its entry in the office (#224).

Uqbar (`docs/plans/2026-10-08-uqbar-design.md`) is a citizen, not a seat: a Claude Code session in
Andrew's own terminal, posting with `tlon-cli post --as uqbar`, drawn as a book on the shelf. Its
delegate loop (releases, the inbox, health, fixes; the 10-08 handoff §3) runs only while that
terminal is open and restarts from nothing in each new session. So the one agent that stands in for
the operator is the one agent the office can't see working, zoom into, talk to with `m`, restart,
or pause with pencils down — and its evening's context is gone the next morning.

### The fix: Uqbar runs in the app

Decided 2026-10-13 (Andrew: "move the Uqbar session into the app"). Tickets to file, one each:

1. **Uqbar is a pane the server spawns**, like a coworker's, with its own launcher profile (the
   Claude plan, the operator's Claude Code settings, the `uqbar` identity), and reachable from the
   office: zoom (`t`), talk (`m`), the activity timeline, clear context. Still a citizen — no desk,
   no leaf, no intake — but a *window* the staffing pass knows, so pencils down and lights out reach
   it and `server:stop` takes it down.
2. **The delegate loop is a standing duty**, not a `/loop` in a terminal: a schedule the server
   fires (`Server.Schedules`, like the sheriff's beat), so it survives the session and the office
   shows its last run on the calendar. Its brief is the handoff's §3, kept in the role file.
3. **Andrew drives it from the office.** The `U` entry grows the verbs that today need a terminal:
   ask Uqbar (an `m` that wakes it), hand it a thread, see what it is on. The book on the shelf is
   where it lives; its posts stay paper aeroplanes.
4. **Its memory is the server's.** What the session banks (`~/.claude/projects/…/memory`) that is
   about tlon becomes stated/derived facts on the machine thread, so a fresh Uqbar wakes knowing it.

**The check.** `server:roster` lists uqbar with a window; `tlon-cli pause pencils_down` reaches it;
the delegate schedule shows a run after a restart with nobody's terminal open.

## Order, and why

| # | Phase | Why this order | Shape |
|---|---|---|---|
| 0 | **Unstick the live three** (#242 by hand-running smoke or `--skip-qa <why>`; #241 the same; #209 a decision from hronir/yu or a hand-off), route the five high plumbing tickets, `scratch:prune` | 15 commits are rotting now; this is also the test corpus for phase 1 | An evening, by hand |
| 1 | **Needs derived from state** (Cause 1) | The biggest change in how it *feels*: the inbox stops lying. Everything else renders what this produces | An epic; one workline per Needs kind after the derivation lands |
| 2 | **Honest degraded states** (Cause 3) | Cheap, high-feel, independent of 1 | 3–4 small worklines (office down-mode; tmux/gh readers; the mod's timeout) |
| 3 | **One glossary, one renderer** (Cause 2) | A steady sweep; do the `TLON_OPERATOR` bug and the status enum first, the key map second, the renames last | The glossary doc + ~6 worklines |
| 4 | **Verbs for every Need** (Cause 4) | Needs each kind from 1 to know which verbs; the release card can go any time | One workline per route group |
| 5 | **Docs** (Cause 5) | In the same commit as each piece above | — |
| 6 | **Uqbar in the app** (Cause 6) | After 1 and 2 land, so the thing it drives is honest; its tickets are filed at phase 0 | 4 tickets, one epic |

**Decisions taken 2026-10-13 (Andrew):** red after build bounces to build on the same branch, the
build kept, to be fixed with its original context — never redone from the start (so verify red joins
the others). The office is stopped (pencils down) and the foundation is built directly by Uqbar from
a better place, then released, then back to work; the later phases go through the office as
worklines once it is honest again.

Phases 1 and 2 can run in parallel on different seats. The QA-blocking tickets (#176, #162,
#204) must land before phase 1's worklines reach QA, or they dead-end exactly as #241/#242 did.

## Not in this

- New toy. The door, the drill, the pets and the planes stay as they are; this plan only stops the
  toy standing in for an operational signal.
- A second surface. The office remains the one surface; the web UI and the desktop alerts read what
  phase 1 produces and nothing more.
- Renaming for its own sake. Every rename in phase 3 traces to a collision in Cause 2.
