---
name: keep-todos-current
description: Use while working a plan on a funes thread — add_todo as you plan a step, complete_todo the moment it's done, and record_done (with evidence) for outcomes worth judging. The thread's TODOS/NEXT/DONE are how a successor knows where the work stands; a stale plan lies about it.
---

# Keep your todos current

Your plan lives on the **thread**, not in your head. funes derives **NEXT** (the first
open todo), shows **TODOS** (the open steps), and merges **DONE** (finished steps +
shipped outcomes) into the brief every session reads. So the plan is only useful if it's
*current* — an open todo you already finished tells your successor to redo it; a step you
never wrote is a step that vanishes when your session does.

## What to do

- **`add_todo(text)` as you plan.** Break the work into steps and write them down as you
  decide them — one line each, in the order you'll do them. Order *is* insertion order, so
  the first open one is automatically NEXT; you never set a "next" flag.
- **`complete_todo(id)` the moment a step is done.** Not at the end of the session — right
  then. Completing advances NEXT for whoever reads the brief next (including you, after a
  compaction). The id comes from `add_todo` or the brief's TODOS.
- **`record_done(text, evidence)` for outcomes worth judging.** Completing a todo is
  bookkeeping and emits nothing; `record_done` is the separate, evidence-bearing verb for
  "this shipped" — the command you ran, the commit, the check that passed. A claim that
  something works is backed by having run it. Both land in DONE, merged by time.

## What NOT to do

- **Don't let the plan drift.** An open todo you've finished, or finished work with no todo
  and no `record_done`, both make the brief lie about where the work stands. Keep it honest
  as you go, not in a cleanup pass that never comes.
- **Don't complete another thread's todos.** A todo is scoped to its thread; funes refuses a
  cross-thread complete. Work your own plan.
- **Don't fold questions or defects into todos.** "does X support Y?" is a `raise_question`
  (a knowledge gap); a crash in the tooling is a `raise_issue` (the stack's tracker). A todo
  is a step in *this* work — keep the axes distinct or the brief blurs.

The test: if your session died right now, would the thread's NEXT point a fresh session at
the right next action, with nothing already-done still listed as open?
