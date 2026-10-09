# Asks with their answers attached — design

**2026-10-08**, Andrew + Uqbar. Built by Uqbar directly (the office stopped for it), not staffed.

## The problem

The office shows what is true but not what it wants from you. On 2026-10-08 every stall was the
same shape:

- "3 to decide" was a count. Two of the three were tertius's @andrew paragraphs, each bundling
  three decisions into bullets; the office could only offer `r reply`. One decision (ireneo's
  build-grid weather) was lost because a prose answer covered two of three.
- The desks were empty because six threads were parked on the leaf cap. The cause was a
  `⏸ parked` line inside each thread; the room showed only the symptom.
- "1 job failed today" opened the rack, which said a job failed, not which, why, or what to do.
- Items stayed after they were handled: a mention settles only on the operator's own reply.

## The rule

**Every item that wants you arrives as a question with its answers attached — one decision per
item, each answer a key.**

## The pieces

1. **Asks.** `ask_operator(question, options)` — with options, the question is an *ask*: a
   pane-less `prompt` message on the thread (the release gate's shape), payload
   `{summary, options, ask: <asker>}`, one per decision, as many per thread as there are
   decisions. It is its own `Needs` item (`kind: "ask"`, blocking, `ref` = the prompt's id), so the
   inbox shows `1 go · 2 hold` and a key answers it. The answer is posted on the thread as the
   operator, `@asker`-addressed and naming the question, so the switchboard delivers it to the
   asker; the prompt resolves. Answered by id (`POST /api/office/asks/:id`), so several asks on
   one thread never cross. Without options, `ask_operator` is what it was (the thread parks,
   a reply clears it).
2. **The manager asks, never @mentions, for a decision.** tertius's brief: a gate already reaches
   the operator by itself — never relay one; anything else the operator must decide is one
   `ask_operator` per decision with options; never bundle. Every worker's brief names the options.
3. **Seats.** A workspace with threads parked on the leaf cap is an item (`kind: "seats"`,
   decide): who waits, the cap, and `1 raise the cap to N`. The answer is the existing settings
   PATCH.
4. **Failed jobs.** Each job discarded in the last day is an item (`kind: "job_failed"`, decide):
   the worker, its last error (or "no error recorded"), `R retry` / `d dismiss`. Dismissing marks
   the job's meta; the rack's count and this list skip dismissed jobs.
5. **Settling.** An item leaves when its answer exists — an ask when answered (by key, or a
   thread reply that names an option), seats when nothing is parked, a job when retried or
   dismissed.

## Not in this

- Mentions stay for conversation; they still settle on the operator's reply.
- A fire easter egg for a down channel (the crew mills about with nothing to do — a server-closet
  fire, a fire drill, everyone outside with coffee): its own toy ticket.
