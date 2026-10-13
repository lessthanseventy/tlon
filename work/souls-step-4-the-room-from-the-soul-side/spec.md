# Souls step 4: the room from the soul; side projects — spec

Ticket #63 · thread #265 · design: `docs/plans/2026-10-08-souls-design.md` §2–3, §6 step 4.
Rule that bounds all of it (§0): a soul shapes what a coworker *does in the room* and *says*. It
never touches a work decision (mandate, stage law, review).

## Decisions (pinned)

1. **People → affinities: regex, not a model call.** Deterministic, free, testable under a seed.
   Cost of the choice: a reworded People section yields no affinity and that seat behaves as today.
   Said on the card (the soul's People section is shown with a one-line note: "read by verb").
2. **Side-project counter persists** as a message on the workspace's standing thread (the suggestion
   box's trick, `Server.Channel.machine_thread/1`), so Daneri's stanza number survives a restart.
   The corkboard itself stays in memory.
3. **No new scheduler, no standing model call.** Side-project notes ride `Server.Office.Corkboard`'s
   lazy writer: due-check at poll (like `ToyPool.refresh_due/2`), cheap tier, under
   `generator_daily_cap`, only while an office is watching.
4. **Side projects come from the soul**, not a hardcoded five: a seat has one iff its soul has a
   non-empty "The side project" section and it is on the bench.

> Decisions 1–2 are yu's recommendation, asked of the operator in #7495; unanswered at commit time.
> If the operator picks otherwise, only §A's parser and §B's persistence change.

## A. Room half (office, TypeScript) — build now

**`office/kit/company.ts`** (new, pure): 
`affinities(name, soul, bench): { admires: string[]; needles: string[]; covers: string[] }` and
`company(a, b, souls, bench): "friend" | "rival" | "none"`.

- Per line of the People section, case-insensitive: `admires` → admires; `needles` → needles;
  `would cover for` → covers. Names matched against `bench` (agent names, case-insensitive,
  whole word); unknown names ignored.
- friend(a,b): a admires or covers b, or b admires or covers a. rival(a,b): either needles the
  other **and** neither is friend of the other. `admires` + `needles` both → friend wins.
- A seat with no soul, or no People section → all empty → `none` with everyone.

**`office/kit/sim.ts`** — diff limited to `idleGoal` and `highFives` (rebase after #255):
- `idleGoal`: when choosing among `waiting` pair spots, a spot whose waiting partner is a *rival* is
  excluded; one whose partner is a *friend* is weighted ×3 (and taken with certainty over the 0.7
  gate's random pick when a friend waits). Free lounge spots are unchanged.
- `highFives`: skip a pair that is `rival`.
- Rivals still share the room, just never a pair spot or a high-five.

**Checks** (`office/test/company.test.ts`, `office/test/sim.test.ts`; Math.random replaced by the
seeded `kit/rng.ts` generator, same seed for every arm):
- rivals: over N=200 idle choices, never pick a pair spot whose waiting partner is their rival;
  never high-five.
- friends: pick the pair spot with a friend waiting in strictly more of the N trials than with a
  stranger waiting.
- a seat with no People section: its picks are identical, tick for tick, to the same room with no
  souls loaded.
- `company.ts` unit cases: three verbs, unknown name, mutual, admires+needles, empty.
- Gate: `mise run office:check`.

## B. Side-projects half (server, Elixir) — after #264 lands

Reuses #264's soul reader; does not add a second one.

- In `Server.Office.Corkboard`: at `notes/1`, for each on-bench seat with a "The side project"
  section whose last side-project note is >24h old (or none), write at most one such note per
  poll, through `Server.Generator` (cheap tier; counts against `generator_daily_cap`; skipped, not
  queued, when capped or banter is off).
- Kind `"side project"`, author the seat, body ≤120 chars, in voice, told the section and the
  previous note so it continues rather than repeats; the prompt carries the counter ("stanza 7").
- Counter: N = count of that seat's side-project messages on the standing thread + 1; each written
  note is also appended there (stored delivered, wakes nobody). The note body is the model's; the
  number is the server's.
- The office needs no change: it already draws corkboard notes by `kind`.

**Checks** (`server/test/server/office/corkboard_test.exs`):
- two polls in a day → one note per seat with the section; none for a seat without it.
- next day (clock injected) → counter is N+1 in the prompt.
- restart (new GenServer, same DB) → counter continues.
- capped generator or banter off → no note, no crash.
- Gate: `mise run server:check`.

## Out of scope
Diary (step 5); voice (step 3, #264); any change to a work decision; per-pair feud *arcs*;
editing souls from the office.

## Open
- Whether a "side project" note should be pinned apart from the 12-note chatter window so it is
  not pushed off by banter (default here: no, same board).
