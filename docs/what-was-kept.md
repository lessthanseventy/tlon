# What was kept

tlon is being archived. It began as an office for a crew of AI coworkers, and its good parts now
live in other repos:
- **babylon**: tickets, the gate, review and landing;
- **arena**: the terminal surface;
- **menard**: Elixir editing;
- **ficciones**: the machine, the rules and the agent wiring;
- **asterion**: the house.

This is one row per part of tlon, sorted three ways:
- **kept**: it's already somewhere else, and the row says where;
- **port**: it's worth having and isn't anywhere yet, so the row names a ticket in the repo it belongs in;
- **drop**: not wanted, with why.

Written 2026-11-27 for babylon #1224. Archiving is #1231, which waits on every port ticket and on
ficciones' unwiring (#1230).

## The pipeline

| Part of tlon | Sort | Where now, or why not |
|---|---|---|
| Worklines' stage machine (`Server.Workline`): `intent → spec → plan → build → verify → review → landed`, an artifact owed at each stage | drop | babylon's ticket body is the intent and spec, the claiming Claude plans in its own session, and the stages that matter (gate, review, land) are babylon's pipeline. Separate spec and plan artifacts were the office's ceremony. Epics planned by `plan_idea` cover the big-change case. |
| The server verifies, not the builder: the full gate run on the branch, its evidence recorded (`workline-verify.sh`, `Server.VerifyTrain`) | kept | babylon runs the repo's `mise run check` itself in a warm worktree. Its log is kept in `~/.cache/babylon/logs`, and `babylon gate N` shows it. |
| Which gates a diff can break (`Server.CheckScope`) | drop | babylon runs the repo's whole gate every time, which is simpler. Narrowing it only paid off on tlon's minutes-long suite. |
| Merge queue and verify train: rebase onto main, gate again, land (`Server.Jobs.Land`, `Workline.Merge`, `land_train`) | kept | babylon's pipeline rebases onto `origin/main`, gates it and fast-forwards, and runs up to four of one repo's tickets as a merge train that splits in half when red. |
| PRs opened and merged at the gated head (`Workline.Publish`, `Server.PRLanding`, `mise run land`) | drop | babylon has no PRs. Main moves only by a gated fast-forward. |
| Reviewer on a different model from the builder's (`:branch_reviewers`, trailers) | **port** | babylon's reviewer is always `claude-sonnet-5-5`, so a Sonnet-built ticket is reviewed by its own model. **babylon #1228.** |
| Verdict tied to the commit it read; a later commit goes back to build | kept | babylon reviews, gates and lands one head in one run. A review `fix` is gated again, and a branch that moved means a new run. |
| Risk grade by a model that didn't write the change; low risk lands under a standing approval (`Workline.Grade`, `auto_land_risk`) | **port** (the limits); drop (the scores) | babylon lands whatever its review approves, so it already acts as if every change had a standing approval. What it lacks is the scripted **limits**: a migration, a dependency, the gate or CI, the law, a deleted test, or a change too big always waits for the human. **babylon #1227.** The model-scored axes cost a model call per landing and their thresholds were never tuned, so they're dropped. |
| Send back to an earlier stage, keeping the build (`Workline.SendBack`) | kept | babylon sends a ticket back to `doing` on the same branch, with why in `stage_note`. |
| A reviewer's non-blocking findings become follow-up tickets | kept | babylon's review files `follow-up` tickets, triaged by the orchestrator. |
| Release pointer, cut, hot load, nightly auto-cut (`Server.Release.*`, `release:cut`, the PM) | kept | babylon runs a repo's `install` task after each landing. Each repo says what restarts (`babylon: restart NAME`). |
| Smoke of main's tip after a landing (`Server.Smoke`, `release:smoke`) | drop | It was tlon's own release, built as a scratch copy. No other repo needs it. |
| Checks queue, one full suite at a time on the shared test db (`checks-queue.sh`) | kept | babylon runs at most two gates at once (`gates`), one per repo. |
| `tlon/check` commit status posted to GitHub | drop | There's no PR to show it on. babylon's run record is the evidence. |
| Review marks on panes (`Server.ReviewMarks` sets `@arena_review`) | **port** | arena still draws the mark, but nothing else sets it. **babylon #1229.** |
| Commit as who you are: the `Tlon-Model` trailer stamped by `prepare-commit-msg` | kept | `Co-Authored-By` is the rule in `~/.claude/CLAUDE.md` (ficciones' `how-to-work.md`), and Claude Code's attribution writes it. #1228 reads it. |

## The crew and the office

| Part of tlon | Sort | Where now, or why not |
|---|---|---|
| The manager (tertius): triage, intake, staffing, the roster (`Server.Triage`, `Intake`, `Roster`, `Staff`) | kept | babylon's orchestrator, `plan_next` and auto mode, which starts Claudes from next up to a cap. |
| Builders, the tech lead, planners | kept | Any Claude session claims a ticket, and `plan_idea` plans an epic. |
| Sheriff, who owns red | kept | babylon sends a red gate back to its ticket, and the nightly retro groups recurring causes into tickets. |
| PM: what ships, held-ticket review (`Server.Release.PM`, `HeldReview`) | kept | babylon's install-on-landing ships, and the digest says what landed and what waits. |
| Asks with answers, the desk, needs (`Server.Office.Needs`, asks) | kept | babylon's `ask_human` and `needs_you`, drawn in arena as Your move. |
| Attention: a seat waiting on a prompt is a first-class state (`Server.Attention`) | kept | arena's `▲` mark and Your move, plus babylon's `stalled`. |
| Consult between agents (`Server.Consult`, `consult_peer`) | kept | Claude Code's `SendMessage`, and messages to the orchestrator. |
| Handoff to a fresh session | kept | babylon's `handoff`. |
| Epics and initiatives, ticket links | kept | babylon's epics, ideas and `link_tickets`. |
| Tickets (`Server.Tickets`) | kept | babylon. |
| Pencils down, pause one thread (`Server.Pause`) | kept | babylon's `hold`, and `auto off` or a repo cap of 0. |
| Schedules: an agent run, a workline or a script on a cron (`Server.Schedules`) | kept | Claude Code's routines and cron (the `schedule` skill), and babylon's own 03:00 retro and 09:00 digest. |
| A fault seen twice is one item (`Server.Recurrence`) | kept | babylon's retro adds the evidence to the open ticket and raises it. |
| Threads, channels, workspaces, projects, the switchboard, wakes, presence (`Server.Channel`, `Switchboard`, `Workspaces`, `Presence`) | drop | This was the office's chat and seating. A Claude session plus a babylon ticket is the unit now. babylon's projects (#1207) are a new design, not a port. |
| Shifts, trust, the diary, policy per seat (`Server.Shifts`, `Trust`, `Diary`, `Policy`) | drop | These are about seats and a bench. Nothing seats agents any more. |
| Souls, personas, banter, pets, toys, generated sprite parts, weather and celebrations in the room (`Server.Soul`, `Persona`, `Office.Banter`, `Office.Pets`, `ToyPool`, `GeneratedParts`) | drop | The office's whimsy. The house's version of it went with asterion. |
| The office TUI and the web UI (`Server.Office`, `Server.Web`, LiveView on :4042) | drop | arena is the surface, as the human asked. |
| The Aleph and outside citizens (`Server.Aleph`, `Server.Outside`) | drop | A Claude session on any model is already outside any bench. |
| The Claude plan's usage meter (`Server.Usage`) | drop | Claude Code's `/usage` and status line show it. |
| Life: routines, quests, XP, streaks; notes; the GitHub contribution canvas; calendar alerts (`Server.Life`, `Notes`, `Canvas`, `Calendar`, `Alerts`) | drop | Personal-assistant features. asterion has its own calendar and chores, and ficciones' shell has calendar and weather panes. Nothing here is used outside the office. |
| The home (Telegram, mail, bank) | kept | It already moved to asterion (`telegram.gd`, `bank_plaid.gd`), and tlon has none of it left. |

## Memory

| Part of tlon | Sort | Where now, or why not |
|---|---|---|
| Facts with provenance, banked by coworkers, recalled into every brief (`Server.Fact`, `Server.Recall`, the `bank-what-you-learn` skill) | kept, in a simpler form | Claude Code's auto-memory: one Markdown file per fact under `~/.claude/projects/<project>/memory/`, indexed by `MEMORY.md` and loaded each session. It has no provenance field. A memory states its *why* in prose instead. |
| The librarian, who retires stale facts and judges corrections; a newer fact supersedes an older one (`Server.Librarian`, `Recall.Supersede`, `Dossier.Corrections`) | drop | Auto-memory is plain files that the human reads and edits. Its own rule ("update rather than duplicate; delete what turns out wrong") does the librarian's job at write time, and a server-side judge has no server to run on. |
| Code-naming facts rechecked on a schedule (`Recall.CodeRefs`, `Recall.Recheck`) | drop | The harness's rule is to verify a memory that names a file or function before acting on it. That checks at read time, which is when it matters. A scheduled recheck would need something to own the memory files across every project, and nothing does. **The human may flip this** to a ficciones port. |
| Habits, playbooks, questions, issues, todos on a thread (`Server.Habit`, `Playbooks`, `Question`, `Issue`, `Todo`) | kept / drop | Habits are `feedback` memories plus `CLAUDE.md`. Playbooks are skills. Todos are Claude Code's own task list. Questions and issues are babylon tickets. |
| Total recall over past messages, embeddings, the memory pass on each turn (`Server.Search`, `Recall.Vectors`, `Memory.TurnPass`) | drop | It searched the office's own channel, which goes with it. |
| Seed knowledge and import of Claude sessions or memory (`Server.Seed`, `Import.*`) | drop | Imports into the store being archived. |
| The secret scanner on the write path (`Server.Secrets`) | drop | It guarded the server's store. Claude Code's memory rules already forbid storing secrets. |
| `bench:longmemeval`, tlon's recall against LongMemEval | drop | It measured the recall engine that goes. |

## Models and measurement

| Part of tlon | Sort | Where now, or why not |
|---|---|---|
| `mise run bench:roles`: can each role do its job on its routed model, and at what cost (`Server.Bench.Roles`, `bench/roles/`) | drop | It measured office roles (manager, librarian, sheriff…) on a ring of mostly ollama models. Those roles are gone, and babylon runs only Claude models, set per ticket. Its frozen tasks and results stay readable in the archived repo, if a benchmark of babylon's builder and reviewer is ever wanted. |
| Ollama routing: seats on glm/deepseek/kimi through Claude Code's gateway (`gateway.sh`, `claude:balanced`…`claude:local`, `Server.Profiles`) | drop | babylon refuses a model that isn't a Claude model id. Putting cheap ollama seats back is a new direction, the human's to choose, not a port. The ollama key stays in ficciones for dbx. **The human may flip this.** |
| One-shot model calls for titles, the judge and banter (`Server.ModelCli`, `Generator`, `oneshot_model`) | drop | Their callers are the office's. arena asks Haiku for its own topic line. |
| The steering-config eval harness (`Server.Eval`) | drop | It tested tlon's briefs and triage routing. |

## The adapters and the loop

| Part of tlon | Sort | Where now, or why not |
|---|---|---|
| The tlon-citizen Claude Code mod: presence, brief, capture, wakes, band (`adapters/claude-code/mod.ts`) | drop | It made a session a citizen of the office. babylon's plugin hooks (inbox, ask gate, handoff nudge) are what a session needs now. |
| The citizen skills (`coordinate-via-tlon`, `keep-todos-current`, `verify-with-evidence`, `bank-what-you-learn`) | kept | Their discipline is in `~/.claude/CLAUDE.md`'s four rules: rule 4 is verify-with-evidence. The rest is babylon's instructions and auto-memory. |
| LSP tools as MCP (`adapters/lsp`, `adapters/lspd`) | kept | Claude Code's own LSP tool, and menard's plugin brings an Elixir language server. |
| `cap`, `watch`, the names gate, the generated manual | kept | ficciones has its own `scripts/cap.sh`, `watch.sh`, `check-names.sh` and `manual-gen.sh`, and each repo keeps its own gate. |
| Scratch worktrees (`scratch:new`) | kept | `wt` (worktrunk) and babylon's `t<id>` branches. |
| Menard verbs and tools | kept | menard. |
| The bwrap argument budget and tmux sweeps (`Server.SandboxBudget`, `tmux-sweep.sh`, `Server.Orphans`) | drop | They kept tlon's own seats under the sandbox's limits. babylon's sweep ends idle Claudes. |
| The standalone binary (`Server.Standalone`, Burrito) | drop | The product it shipped is being archived. babylon builds its own release. |

## Ficciones' side

ficciones still runs tlon. **ficciones #1230** lists each place to unwire, found by a read-only
survey on 2026-11-27:
- the `tlon` systemd user service, its slice, cookie and seed;
- the `machine:update` restart step;
- the shell's alerts (polling `:4040/api/alerts`) and the launcher's jot (`:4040/api/home`);
- the `TLON_*` env lines and git-hook fences;
- the `asterion` wrappers that still point into tlon's tree;
- babylon's offer list;
- the secrets' comments;
- the manual's tlon pages.

Nothing is unwired yet. One decision there is the human's: re-point the shell's alerts at babylon's
`needs_you`, or remove them.
