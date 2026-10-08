# Handoff — the 2026-10-08 orchestrator session (Uqbar) → the next one

**Written:** 2026-10-08, ~13:55, by the Claude Code session that ran the day (it calls itself
**Uqbar**; see `2026-10-08-uqbar-design.md`); brought up to date ~15:30, before Andrew's reboot.
Read this, then `AGENTS.md`, then the memory index
(`~/.claude/projects/-home-andrew-projects-tlon/memory/MEMORY.md`).

## 1 · Where things stand

- **Live release:** `live` = `e2029d5` (cut 14:26, gate + smoke green): the strobe fix (#159), the
  grade fix (#156), the birthdays. main is ahead only by docs. The office was restarted fresh on
  the fixed code; R is safe.
- **Talking in the office:** design `2026-10-08-office-talk-design.md`; tickets #70 (balloons
  bigger, never overflowing) → #71 → #72 → #73, each blocked by the one before.
- **#74:** KeepUp's drifted-main note — one per repo (it duplicated per count), routed to the
  repo's workspace instead of the operator.
- **Epics:** design `2026-10-08-epics-and-initiatives-design.md` (PR #163); tickets #77 (server,
  high) → #78 → #79, and #80 (Uqbar backfills the six epics once #78 lands). Priorities set
  2026-10-08: #75, #74, #70, #52, #47 high.
- **Thread #1:** uqbar asked Andrew a Funes question (post #3886: what should tlon blur on
  purpose?). His reply is still to come; answer it as uqbar there.

## 2 · What runs on its own (schedules on the live service)

| # | Title | When | Notes |
|---|---|---|---|
| 1 | nightly gate on main | 03:00 | `mise run check:main`; records `ran-on: gate <sha>` |
| 4 | nightly smoke on main | 03:30 | created by the PM's `check_candidate` today |
| 2 | overnight summary | 08:00 weekdays | tertius |
| 3 | inbox sweep | every 2h 08–20 | tertius, `operator_inbox`, digest-only (never answers as Andrew) |
| 5 | canvas | 07:30 | Sonny draws a 7×52 picture on thread #191 (holidays, puns) |
| 6 | paint the canvas | 08:00 | `scripts/tlon-cli.sh canvas` → force-push `lessthanseventy/canvas` |

The canvas is live: today's picture is Sonny's four jack-o'-lanterns, 1,632 backdated commits.

## 3 · The delegate loop

Andrew asked this session to be his eyes and his stand-in. It ran a self-paced `/loop` doing: the
inbox (answer, approve gates **after reading the doc/diff**, hand off misroutes, check a blocked
chain advanced when its blocker landed), releases (gate + smoke on main's tip, then cut), health, and fixes via PRs.
Posts as `uqbar` (`tlon-cli post --as uqbar`); as `andrew` only when answering for him. Never:
publish outside tlon (the canvas excepted), rewrite pushed history, delete data, merge another
agent's PR without reviewing it, or decide scope/priority. **A new session should restart it**
(the loop doesn't carry over).

## 4 · Today's designs and the crew's queue

Specs on main: `2026-10-08-uqbar-design.md`, `…-office-as-a-toy-design.md`, `…-souls-design.md`.
Tickets with full briefs. Step order is `blocks` links (intake skips a ticket while a blocker is
open, so a chain advances by itself); `held` is left only on #80, Uqbar's own backfill task:

| Tickets | What |
|---|---|
| #46 | Andrew's GitHub profile — a **draft for his approval**, never published by the crew |
| #47–51 | Uqbar steps 2–6 (the book on the shelf, torn pages, marginalia, the `U` entry, small joys) — 48–51 blocked by 47 |
| #52–59 | the toy: sandbox mode, voices + **Scharlach the Dwight**, bathroom (Nina's wet pawprints), doorbell, events, the **wackiness dial** (#57: business → business casual → office party → rimworld), reactions, generators (#59, ollama flash by default) |
| #60–64 | souls (SOUL.md per coworker from their Borges story, diaries) — 61–64 blocked in step order |
| #65–68 | hiring hall (swipe on generated people), cast editor (god view), parts library (accessories first — **Jude loves them** — plus procedural and model-invented parts), pet store (Borges' imaginary beings) |
| #69 | **Gary the Dumpster Gremlin** (Jude: "murder trash hobo slappage") — a cartoon creature, blocked by #56 |

## 5 · Waiting on Andrew

- The four drifted repos are level with origin: menard's were already upstream; excessibility
  (#201) and ex_riverside (#1) were reviewed and merged; ficciones landed its own (workbench
  #8–#11). Before ex_riverside's next `mise run deploy`, check prod's `~/riverside/start.sh` for
  server-only edits — the deploy now overwrites it.
- **Packaging for Jude and Robyn** (his next topic, not started) — see §7.

## 6 · Gotchas learned today (each also in memory)

- **`bin/server rpc` code runs inside the live service.** `System.halt` there halts the server
  (#152 removed 15 from `tlon-cli`; a test keeps them out). To fail, `raise`. Never probe a refusal
  path against prod.
- **`/tmp` is RAM (tmpfs).** Scratch worktrees with copied `deps`/`_build` filled it once and
  killed task output. Remove each worktree when its PR is up.
- **`.git/config.lock` keeps reappearing** as an empty read-only file — likely pi-sandbox
  placeholder leakage (Claude Code's sandbox mounts `/dev/null` there and leaves nothing). Safe to
  `rm` when no git process runs. Reported to the ficciones session.
- **The sandbox's auto-mode check** blocks some actions (merging another agent's PR, removing many
  worktrees, a public push). Don't route around a denial; ask Andrew.
- Never push to a PR with auto-merge armed; never `@mention` a coworker on a thread it doesn't lead;
  never switch branches in `~/projects/tlon` (the service reads its checkout).
- **The engine holes closed today** (so a symptom recurring means a regression): stranded work
  during landings (#124, #140, #143, #146), approvals recorded and surviving doc commits (#126,
  #140), QA hand-off from an advance (#141), gates you can't approve (#133), tickets done only on
  merge (#139), held tickets (#136), a coworker pushes only via `push_branch` (#134). **Still
  open:** QA's session can be bound to the lobby, so `submit_qa` refuses on the real thread (#174
  today; filed by hand for nolan).

## 7 · Packaging (the next topic)

- **Windows:** no build yet — `office:build` compiles linux/darwin only. Bun can compile
  `--target=bun-windows-x64`. The wide room needs the **kitty graphics protocol**: Windows Terminal
  doesn't speak it; **WezTerm** does (on Windows too). The full office also needs tmux and a server
  (Postgres, Elixir), which Windows doesn't have.
- **So for the kids, ship sandbox mode (#52):** one `.exe`, no server, no tmux, every toy key live
  (plus Gary, the doorbell, the pet store as they land). Recommended first packaging target.
- **Models on their machine:** the toy needs no harness — only the generators (#59) call a model,
  through `Server.ModelCli`/its office equivalent, pointable straight at ollama.com. A shared ollama
  account fits. Claude Code *can* be pointed at another backend (`ANTHROPIC_BASE_URL` and friends),
  but whether ollama.com serves the API it expects is **unverified** — check before relying on it.
- **pi vs Claude Code:** keep both. `AGENTS.md`'s routing is two buckets on purpose (pi = the flat
  ollama workhorse with the model ring; Claude Code = the scarce Claude plan). Neither is needed for
  the kids' toy.
