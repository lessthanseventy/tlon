# Handoff — the 2026-10-08 orchestrator session (Uqbar) → the next one

**Written:** 2026-10-08, late evening, by the Claude Code session that ran the evening (it calls
itself **Uqbar**; see `2026-10-08-uqbar-design.md`). Andrew handed it the delegate role ("you can be
me for awhile"). Read this, then `AGENTS.md`, then the memory index
(`~/.claude/projects/-home-andrew-projects-tlon/memory/MEMORY.md`).

## 1 · Where things stand

- **Live release:** `7b54006`, then a cut of main once #191 lands (check `git rev-parse --short
  live`). Every cut tonight ran `mise run check:main` on the exact tip first. After a cut, the
  operator's TUI needs `R` (its header says "office updated · R reloads").
- **Nothing is in flight on the board.** Tickets #70 (speech balloons) and #74 (KeepUp: one drifted
  note per repo) are routed to tertius ("2 to staff" on his desk); intake starts them itself after
  30 minutes. #85 (epics: guard the parent law in the db; an epic's status is derived only) is in
  the backlog.
- **In flight as PRs (four agents, launched together):** ficciones — the desktop renders tlon's ask
  answers and `info` toasts, and pi's `models.json` matches what ollama.com serves; tlon — the
  suggestion box leaves the inbox (it is banter, not a request), QA can record a verdict for a
  workline its session isn't bound to, and "it took effect" toasts for a landing and a release.
  Merge, gate main, cut, and `machine:update` for the ficciones half.

## 2 · What changed tonight (all on main)

- **Asks with their answers attached** (`docs/plans/2026-10-08-asks-with-answers-design.md`):
  `ask_operator(question, options)` is one inbox item per decision, answered by key; seats (threads
  parked on the leaf cap) and failed jobs are inbox items with their answers; the desktop alert for
  an ask carries its answers as actions; a parked thread getting its seat is an `info` toast.
- **The tech lead** (`docs/plans/2026-10-08-tech-lead-design.md`): tertius owns the flow (who,
  when); the bench's lead (hronir) owns coherence (on main already? overlaps? grade? spec first?)
  and answers builders' technical questions before Andrew; tertius asks him before staffing. The
  manager can never lead a workline (a manager-only bench leaves it unled).
- **The honest board:** a card is ▶ at a desk, ⏸ parked, ○ idle; DOING means someone is at a desk;
  standing duties (schedules, the sheriff's beat) are off the board and take no seat under the cap.
  A warm session counts only with a window to wake in. The room no longer shrinks for the home annex.
- **Staffing:** the switchboard spawns only bench coworkers (a pane once posted as "uqbar" — not this
  session); every git worktree gets its own test database; the test db is force-dropped per run.
- **Suggestions are saved** as `suggestion` messages on the lobby (survive restarts, searchable).
- **Models:** the server's ring has every plan model ollama.com serves (flash, glm-5.3(-flash),
  kimi-k2.6, minimax-m3/m2.7; kimi-k3 stays out — per-token). The bench: tertius, reviewers,
  planners, scharlach on Sonnet; hronir and lonnrot (greybeards) on Fable; junior builders, nolan,
  beatriz on Haiku 5.5; emma, ireneo, ashe on `deepseek-v4.1-flash` (pi). Cap: `max_leaves` 8,
  `max_worklines` 3. `mise run ollama:usage` reads ollama's `/api/balance` (this account is still
  on the legacy session/weekly meters).
- **Tasks:** `mise run server:stop` (service + every coworker pane). The inbox sweep (schedule #3)
  no longer @mentions Andrew or relays what the inbox already shows.

## 3 · The delegate loop

Andrew asked this session to stand in for him. It ran a self-paced `/loop`: releases (gate main's
tip, then cut — the cut restarts only when quiet), the inbox (answer as Andrew where it's his call,
approve gates only after reading the diff and the review, settle stale items), health (service,
`/tmp`, stray worktrees), fixes via PRs. Posts as `uqbar`; as `andrew` only when answering for him.
Never: publish outside tlon, rewrite pushed history, delete data, decide scope he hasn't delegated,
push to an auto-merge-armed PR, @mention a coworker on a thread they don't lead. **A new session
restarts it** if Andrew wants it (the loop doesn't carry over).

## 4 · Gotchas learned tonight (each also in memory where it lasts)

- **`.git/config.lock` is Claude Code's sandbox**, not a stale lock: bwrap's mount target for a
  protected path, held as long as any sandboxed command runs. Don't `rm` it. Work in a detached
  worktree and `git push origin HEAD:refs/heads/<branch>`; `gh pr create --head <branch>`.
- **A Monitor runs sandboxed** and can't reach the node (rpc returns nothing): watch GitHub
  (`git ls-remote`, `gh pr view`) instead.
- **Smoke builds leaked** 22 GB of the RAM-backed `/tmp` when restarts SIGKILLed held smokes; each
  smoke now sweeps abandoned builds first. Check `df -h /tmp` after a busy day.
- **A gate approval can come back:** a workline owing QA returns to review after QA and needs a
  second approve.
- **Merging fast moves main under a builder** mid-verify (hronir rebased #197 twice tonight).
- **zsh**: `$b:server/…` is a history modifier — write `"$b:server/…"` or `${b}`. And never `pkill -f`
  a pattern your own command line contains.
- **Corkboard suggestions are banter** written in a coworker's voice; until the PR above lands they
  still reach the inbox. Don't staff one without a real ask behind it (#198 was).

## 5 · Waiting on Andrew

- The drafted Claude Code bug report about the sandbox lock (review it with `/feedback`).
- The desktop half of the alert changes needs `mise run machine:update` once its ficciones PR merges.
- Packaging for Jude and Robyn (sandbox mode, #52) is still the next topic; see the previous
  version of this file in git history for the notes.
