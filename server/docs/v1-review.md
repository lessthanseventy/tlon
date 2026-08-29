# Workbench deletion plan — vocabulary, mode chords, close path, reducer

Adversarial review of this machine's own workbench, requested 2026-08-13: *"is it worth stepping
back and looking at all this as a whole again kinda adversarially to get some freshish eyes on the
stack?"* Reviewed by a fresh planning space (w4A) with no memory of the reasoning that built it, and
by a cross-family consult before that. Both were asked to say what to DELETE.

This file exists because the reviewing space closed before writing one. Its verdicts arrived as a
report message and would otherwise have survived only in a transcript — which is the same class of
loss as the `/renew` incident below. Recorded here by w25 verbatim where possible.

## Status of the evidence

| Claim | State |
|---|---|
| GO/singleton vocabulary is decoration | Verified in source: `workspace.lua` has no singleton uniqueness mechanism |
| Mode chords are vestigial | Measured: 127 sessions, 54 `anmoore-work-mode` entries in 38 sessions, 35 parented by `workbench_mode`, **zero mode entries or calls in sessions born Aug 11–13** |
| `session_shutdown` can reconcile on close | **REFUTED by experiment** — see below |
| Reducer findings establish harm | Not established. No finding has changed a decision |

## 1 · Delete the human-facing vocabulary, keep the internal predicate

Delete `GO`, `SINGLETON`, `BENCH`, `desk`, `home` from everything a human reads: palette section
labels, `KEYS.md`, prompt text, tool descriptions. One noun — **space** — and one verb — **Open**.

Do NOT erase the internal distinction. `kind` is load-bearing: it drives reconciliation, close
safety, the sidebar and prompt selection. Rename it neutrally rather than deleting it.

Evidence: `workspace.lua:177,357,949`; `workbench-palette.zsh:154-209`; `KEYS.md:13-50`;
`core.ts:848,908,1334-1386`; `workbench.ts:921-932,2407-2413,2516`.

Acceptance test, and it is the whole point: **can the owner, cold, open work, say what a space is
for, close it safely, and find what is waiting on them — without vocabulary coaching?**

## 2 · Delete the five mode-switch chords — DONE 2026-08-14

Delete `prefix+shift+{p,s,d,r,v}`, their palette MODE rows, and the docs that teach them. Retain
`/mode` and the `workbench_mode` tool: a session's work genuinely does cross a boundary sometimes,
and that is the path actually used. Modes are **launch profiles**, not mutable state.

This also removes the collision the owner kept tripping over: `Shift-S` meant "switch to Support
mode", not "go to the Support desk".

Evidence: `config.toml:44,90,96-120`; `switch-mode.lua:95`; the session-corpus counts above.

**Landed.** 17 command chords → 13. `herdr config check` reported `config: ok` and
`server reload-config` reported `applied`. The freed `prefix+shift+r` now opens the glance (see
below), which is the same letter meaning "review" for a question the owner actually asks.

**One deliberate deviation from this verdict:** the palette's eight MODE rows were KEPT. They cost no
memory because the palette is searchable, they are the only *discoverable* human path to `/mode`, and
the collision this verdict was really about (`Shift-S` = "Support mode", not "the Support desk") is
resolved entirely by deleting the chords. Revisit if the rows are observed to mislead.

## 3 · Reconciliation must live on the close path the human already uses — by shadowing it

The owner's own words: *"i kinda have a bad habit of just closing sessions and getting the state file
confused."* A command with its own chord (`/shred-me`, `prefix+shift+z`) is bypassed by exactly that
habit, so the raw close is the required path.

**Two experiments, both run, and they agree that nothing can finish work during a close:**

- Shell level: `herdr workspace close` delivers `HUP`, `HUP`, `TERM` — trappable, not `SIGKILL`. But
  a trap that wrote a timestamp, slept 1s and wrote again got **only its first line out**. No usable
  grace period.
- Pi level: a temporary extension registered `session_start` and `session_shutdown`, each doing a
  **synchronous** `appendFileSync`. `session_start` landed. After `herdr workspace close`, the file
  contained **only** the `session_start` line — no shutdown entry at all.

So `session_shutdown` cannot be relied on, despite the docs promising it on `SIGTERM`. The step is
therefore: **shadow the native `close_workspace`** — set `close_workspace = ""` in `[keys]` and bind
that chord to a script that reconciles first, then closes.

Verification is available and must be used: `herdr config check` reports
`kept keys.X, disabled keys.command[N].key` on a collision, and `wiring.test.sh` fails on the word
`disabled` as well as on the exit status. Proven by deliberately colliding on `prefix+shift+x`.

## 4 · Cut the reducer down to what needs a person

Delete from `ai-orchestrate`: unread-broadcast reporting (broadcasts are *mechanically* unread — a
session drains its mailbox only when it starts or reloads, so a message asking a session to reload
can only be read by one that already did), the message-exchange ratios, and generic drift.

Keep live unowned work. Keep directed unanswered questions **only** after routed-answer correlation:
`w44→w45` is a confirmed false positive because the answer travelled through `w25`. The rule "did the
recipient ever reply to the asker" was chosen because it was a fact rather than a word-overlap guess,
but it assumes replies are direct and on this machine they are frequently relayed by the parent.
Options, in order: correlate on the handoff id (now minted per attempt and carried in the opening
record, the child's `PI_HANDOFF_ID` and the closing record); accept a reply from any space on the
same subject; or delete the section.

Evidence: `orchestrate.mjs:105-195,210-247`; `mail.jsonl:193-198`.

## 5 · The key map is generated, not written — DONE 2026-08-14

`prefix+shift+h` ran `less -R KEYS.md`: hand-written prose beside the config Herdr actually reads. It
was stale within an hour of the last chord being added and carried "Reviews has no chord on purpose",
a decision recorded where nothing enforced it. Replaced by `keymap.zsh`, which generates the map from
`config.toml` and groups chords by the question they answer (`ASK`) versus the thing they do (`DO`).
`KEYS.md` deleted; the palette's help arm repointed.

## 6 · One place for the two questions the owner actually asks — DONE 2026-08-14

*"i still don't really have a place that makes 'what do I need to Review PRwise right now' or 'What
did I do yesterday?' very easy... the daily notes are great for you not so much for me."*

`ai-glance` on `prefix+shift+r`. It collects nothing: it reads the `prs.json` the radar already writes
and the worklog the journal already reads, and throws most of it away. Bots, drafts, already-approved
and anything untouched for 30 days become counts rather than lines. Real data corrected two mistakes
during the build — a fixture that invented `buildDay`'s shape, and an "oldest first" ranking that put
a 213-day-old pull request at the top of "what needs me right now".

## Three bugs of one shape, found while this review ran

The first two conflate **"nothing is open"** with **"nothing was done"**. They are opposite situations with
opposite correct answers, and `openWork()` cannot tell them apart because it only reports what is
*active*.

1. **`/renew` blanked a 112-entry transcript** and reported "nothing was open to carry forward". The
   space had no task and no queue because it was mid-analysis, so its entire value was the prose.
   The owner read the blank pane as a crash: *"it crashed and now i can't get it back to /renew it."*
   Fixed as `renewSafety()`: carry something → renew; land something → renew clean; bank nothing →
   **refuse**, naming `/reset` as the command that means discard.
2. **`/shred-me` recorded this very review as `abandoned`** — `closed with 0 of 0 step(s) unfinished`
   — because it never used the queue. It had in fact delivered its whole report. Same discriminator
   needed: a session that banked nothing is not the same as one that abandoned something.

## What is NOT recommended

- Do not build a meta-orchestrator session. The two append-only logs are the bus; a session is a
  context window with a lifetime and must not be in the delivery path.
- Do not merge `/shred-me` into `/wipe-me`. Machine-wide reconciliation stays separate; per-space
  reconciliation moves onto the close path.
- Do not treat the test count as evidence of need. 380+ tests validate implemented contracts,
  including contracts this plan deletes.

3. **`workbench_herdr prepare` could not resolve the pane it had just created**, so a Support session
   doing live production work was told "the tab was created, but its pane ID could not be resolved"
   twice, and had to find the pane and type in it by hand. `workbench.ts` kept its own parser reading
   only `result.pane_id` and `result.pane.pane_id`, while `core.ts` already had a tested resolver that
   knew `herdr tab create` answers with `result.root_pane`. Two sources of truth for one payload, and
   the untested one was in the live path. Fixed by moving `herdrIds` into the tested core as the union
   of every shape and deleting the local copy. Found by a `/wipe-me` harvest, not by a test.
