# Handoff — the 2026-10-08 orchestrator session (Uqbar) → the next one

**Written:** 2026-10-08, late evening, by the Claude Code session that ran the evening (it calls
itself **Uqbar**; see `2026-10-08-uqbar-design.md`). Andrew handed it the delegate role ("you can be
me for awhile"). Read this, then `AGENTS.md`, then the memory index
(`~/.claude/projects/-home-andrew-projects-tlon/memory/MEMORY.md`).

## 1 · Where things stand (2026-10-09, early morning)

- **Live release:** `2d7766f` (check `git rev-parse --short live`); the operator's TUI needs `R`.
- **In flight:** #202 speech balloons, #203 sandbox mode (step 1 of the toy for Jude and Robyn) and
  #204 Uqbar's volume at review/QA; #205 (memory pass banks junk `...` facts) in review; #206 (facts
  about code carry a recheck) in verify. Ticket #90 (a senior-builder bench from real merged
  worklines; hronir picks the tasks) is with intake.
- **The bench:** a second QA, **treviranus** (Haiku), beside nolan, who was the bottleneck.
  **quain**, the librarian (`Server.Librarian`, flash), sweeps daily at 07:00 (schedule #7) and
  reports on the office's knowledge Mondays 07:30 (#8). The nightly role-bench canary is schedule #9
  (04:30). Senior builders stay on Sonnet: on the current fixtures Sonnet and flash both score 4/4,
  so the bench can't tell them apart until #90 lands. ashe (researcher) stays on flash.

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

- **After midnight:** the db hunt (undeliverable messages settle, close clears `awaiting`, an index
  on `message.created_at`); stale sessions end and missing embeddings fill in the sweep; the
  structured activity feed (`office/tui/timeline.ts`); toasts for a landing and a release; the brief
  carries what the office knows (`Recall.thread_knowledge/2`) and reading a fact cites it;
  supersede (cosine ≥ 0.92, backfilled: 26 superseded) and the correction judge (dark behind
  `:judged_supersede`; quain reviews its proposals); the role bench (`mise run bench:roles`).
- **A lead woken on the lobby** can act on the workline it leads: `advance_stage`, `push_branch` and
  `submit_review` take `thread_id`, honoured only for the caller's own thread
  (`Server.MCP.Tool.acting_thread/2`). `switch_thread` can't help a Claude Code pane — its MCP auth
  is fixed at launch.

## 3 · The delegate loop

Andrew asked this session to stand in for him. It ran a self-paced `/loop`: releases (gate main's
tip, then cut — the cut restarts only when quiet), the inbox (answer as Andrew where it's his call,
approve gates only after reading the diff and the review, settle stale items), health (service,
`/tmp`, stray worktrees), fixes via PRs. Posts as `uqbar`; as `andrew` only when answering for him.
Never: publish outside tlon, rewrite pushed history, delete data, decide scope he hasn't delegated,
push to an auto-merge-armed PR, @mention a coworker on a thread they don't lead. **A new session
restarts it** if Andrew wants it (the loop doesn't carry over).

## 4 · Gotchas, and the rule for them

A quirk seen twice gets root-caused before it is worked around again (Andrew, 2026-10-09). The
ones that recurred tonight, each with its cause:

- **`.git/config.lock` is Claude Code's sandbox**, not a stale lock: bwrap's mount target for a
  protected path. Don't `rm` it. Work in a detached worktree, `git push origin HEAD:refs/heads/<b>`,
  `gh pr create --head <b>`.
- **A Monitor runs sandboxed:** `gh` there has no credentials (HTTP 401 on every call) and rpc to the
  node returns nothing. Watch with `git ls-remote origin`, and print any error — a watch that treats
  an error as "not yet" looks like silence for 30 minutes.
- **Auto-merge armed after every check passed never fires** (it waits for a next check). Re-check a
  PR after arming; CLEAN and still OPEN means merge it directly.
- **Merging fast moves main under a builder** mid-verify; its rebase-and-gate restarts. Hold merges
  while a workline verifies, unless it is the one landing.
- **Smoke builds** sweep abandoned `/tmp/tlon-smoke-*` first; still check `df -h /tmp` after a busy day.
- **A gate approval can come back:** a workline owing QA returns to review and needs a second approve.
- **zsh**: `$b:server/…` is a history modifier — write `${b}`. Never `pkill -f` a pattern your own
  command line contains.

## 5 · Waiting on Andrew

- The drafted Claude Code bug report about the sandbox lock (review it with `/feedback`).
- The auto-hired seat `planner-4485`: keep or let go.
- Whether flash is fit for any senior role — waits on #90's numbers.
