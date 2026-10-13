# Souls step 4 — plan

Spec: `spec.md` (operator picked A+P: regex affinities, counter persisted on the standing thread).
Two halves. **Room half (R1–R4) builds now, office only. Server half (S0–S3) starts only after
#264 lands its soul reader.** Each task is one commit; test first, red then green.
Gates: `mise run office:check` (run unsandboxed), `mise run server:check`; whole thing `mise run check`.
Bound: nothing here may touch a work decision — only `idleGoal`, `highFives`, and the corkboard.

## R1 · `affinities` — parse a People section  (office/kit/company.ts, new)

Test first: `office/test/company.test.ts`

```ts
import { describe, expect, test } from "bun:test"
import { affinities } from "../kit/company"

const bench = ["scharlach", "tertius", "lonnrot", "nolan", "daneri"]
describe("affinities", () => {
  test("the three verbs, names matched against the bench", () => {
    const people = "admires tertius (won't admit it), needles Lönnrot who reviews his fixes, would cover for nolan."
    expect(affinities(people, bench)).toEqual({ admires: ["tertius"], needles: ["lonnrot"], covers: ["nolan"] })
  })
  test("accents and case fold; a name off the bench is ignored", () => {
    expect(affinities("Needles LÖNNROT and Beatriz", bench).needles).toEqual(["lonnrot"])
  })
  test("no People section, or no verbs → nothing", () => {
    expect(affinities("", bench)).toEqual({ admires: [], needles: [], covers: [] })
    expect(affinities("gets along with everyone", bench)).toEqual({ admires: [], needles: [], covers: [] })
  })
  test("each clause is its own: the verb applies up to the next verb or period", () => {
    const a = affinities("admires daneri; needles nolan.", bench)
    expect(a).toEqual({ admires: ["daneri"], needles: ["nolan"], covers: [] })
  })
})
```

Code:

```ts
export type Affinities = { admires: string[]; needles: string[]; covers: string[] }
const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
const VERBS: [keyof Affinities, RegExp][] = [["covers", /would cover for/g], ["admires", /\badmires\b/g], ["needles", /\bneedles\b/g]]

/** the People section → who they admire / needle / would cover for, by verb; names off the bench are ignored */
export function affinities(people: string, bench: string[]): Affinities {
  const text = fold(people), out: Affinities = { admires: [], needles: [], covers: [] }
  const marks = VERBS.flatMap(([k, re]) => [...text.matchAll(re)].map((m) => ({ k, at: m.index!, end: m.index! + m[0].length })))
    .sort((a, b) => a.at - b.at)
  marks.forEach((m, i) => {
    // a clause runs to the next verb or the next period, whichever is first
    const rest = text.slice(m.end, marks[i + 1]?.at ?? text.length)
    const clause = rest.split(".")[0]!
    for (const n of bench) if (new RegExp(`\\b${fold(n)}\\b`).test(clause) && !out[m.k].includes(fold(n))) out[m.k].push(fold(n))
  })
  return out
}
```
Done: `bun test office/test/company.test.ts` green. Commit "company: parse People into affinities".

## R2 · `relation` — friend / rival / none  (same file)

Test (append to `company.test.ts`):

```ts
import { relation } from "../kit/company"
const soulOf = (people: string) => ({ sections: { People: people }, raw: "" })
const souls = { scharlach: soulOf("admires tertius, needles lonnrot"), lonnrot: soulOf(""), tertius: soulOf(""), daneri: soulOf("needles tertius and admires tertius") }
test("friend, rival, none — symmetric", () => {
  expect(relation("scharlach", "tertius", souls, bench)).toBe("friend")
  expect(relation("tertius", "scharlach", souls, bench)).toBe("friend")
  expect(relation("scharlach", "lonnrot", souls, bench)).toBe("rival")
  expect(relation("lonnrot", "scharlach", souls, bench)).toBe("rival")
  expect(relation("nolan", "scharlach", souls, bench)).toBe("none")
})
test("admires wins over needles; a seat with no soul is none with everyone", () => {
  expect(relation("daneri", "tertius", souls, bench)).toBe("friend")
  expect(relation("nolan", "daneri", souls, bench)).toBe("none")
})
```

Code:

```ts
export type Relation = "friend" | "rival" | "none"
type SoulLike = { sections: Record<string, string> }
export function relation(a: string, b: string, souls: Record<string, SoulLike | undefined>, bench: string[]): Relation {
  const ab = affinities(souls[a]?.sections.People ?? "", bench), ba = affinities(souls[b]?.sections.People ?? "", bench)
  const likes = (x: Affinities, who: string) => x.admires.includes(who) || x.covers.includes(who)
  if (likes(ab, b) || likes(ba, a)) return "friend"
  if (ab.needles.includes(b) || ba.needles.includes(a)) return "rival"
  return "none"
}
```
Names are lowercase agent names (`seat.agent`, same key `soulFor` takes). Done: test green; commit.

## R3 · rivals never pair, friends are drawn  (office/kit/sim.ts — `idleGoal` only)

Test first (`office/test/sim.test.ts`, new `describe("company")`). Use the `warmth` block's helpers
(`new WideRoom(560)`, `viewOf(office(), 1)`, `actor(room,name)`); load souls with `useSouls`; seed
`Math.random` with `mulberry32` from `office/kit/rng.ts` and restore it in `afterEach`.
Build a helper `pairChoices(room, who, waiter, n)`: put `waiter` at a pair spot (a lounge spot with
`with`, e.g. foosball) via `actor(room, waiter)` spot fields, then call the private `idleGoal`
(cast `room as unknown as { idleGoal(a: unknown, held: Set<string>, l: unknown): Spot }`) `n=200` times
for `who` with a fresh `until=0`, returning how many picked the waiter's partner spot.

```ts
test("rivals never take the pair spot beside each other", () => {
  useSouls({ scharlach: parse("needles lonnrot"), lonnrot: parse("") })
  expect(pairChoices(room, "lonnrot", "scharlach", 200)).toBe(0)
})
test("friends take it more often than strangers do", () => {
  useSouls({ scharlach: parse("admires nolan"), nolan: parse("") })
  const friend = pairChoices(room, "nolan", "scharlach", 200)
  useSouls({})
  expect(friend).toBeGreaterThan(pairChoices(room, "nolan", "scharlach", 200))
})
test("no People section: picks are identical to a room with no souls", () => {
  useSouls({}); const bare = trace(room)           // list of goal spotKeys over 300 ticks, same seed
  useSouls({ ashe: parse("") }); expect(trace(room)).toEqual(bare)
})
```
(`parse` = `parseSoul("## People\n" + text)`; remember `useSouls({})` in `afterEach`.)

Code, in `idleGoal`, where `waiting` is built: find the actor holding each waiting spot's partner and
filter / weight by `relation(actor.seat.agent, holder.seat.agent, <souls>, bench)`:

```ts
import { relation } from "./company"
import { soulFor } from "./souls"
...
const bench = [...this.actors.values()].map((x) => x.seat.agent)
const souls = Object.fromEntries(bench.map((n) => [n, soulFor(n)]))
const holder = (s: Spot) => [...this.actors.values()].find((x) => x.spotKey === spotKey({ ...s, ...s.with! }))
const rel = (s: Spot) => relation(actor.seat.agent, holder(s)?.seat.agent ?? "", souls, bench)
const waiting = free.filter((s) => s.with && held.has(spotKey({ ...s, ...s.with })) && rel(s) !== "rival")
const friends = waiting.filter((s) => rel(s) === "friend")
if (friends.length && Math.random() < 0.9) return friends[Math.floor(Math.random() * friends.length)]!
if (waiting.length && Math.random() < 0.7) return waiting[Math.floor(Math.random() * waiting.length)]!
```
Also drop rival-held pair spots from `free` before the weighted roll, so a rival never lands there
by the weighted path: `const ok = free.filter((s) => !(s.with && held.has(...) && rel(s) === "rival"))`.
Keep the rest of the function (favourite ×3, hour) untouched. Done: the three tests green and the
whole of `office/test/sim.test.ts` still green. Commit "sim: rivals avoid the pair spot, friends are drawn to it".

## R4 · rivals don't high-five  (office/kit/sim.ts — `highFives` only)

Test: two actors passing with `finished` just set (as the existing high-five test does), souls say
`needles` → no `five` set; same pair with `admires` or no souls → five set.

Code: in the inner loop, before the `key` line:
`if (relation(a.seat.agent, b.seat.agent, souls, bench) === "rival") continue`, with `souls`/`bench`
computed once at the top of `highFives` the same way as R3 (extract a private `companyOf()` returning
`{ bench, souls }` and use it in both; that is the one shared helper). Done: tests green;
`mise run office:check` green. Commit. **Then rebase onto main/#255 and re-run `office:check`.**

## S0 · confirm #264's soul reader  (no code)

Read `server/lib/server/soul.ex` on main once #264 has landed: note the function that returns a
seat's soul sections (below called `Server.Soul.section(ws, name, "The side project")`). Use it as
is. If #264 hasn't landed, stop and tell the lead — do not write a second reader.

## S1 · is a side-project note due?  (server/lib/server/office/corkboard.ex)

Test first (`server/test/server/office/corkboard_test.exs`), pure function:

```elixir
test "a side project is due once a day, only for a seat that has the section" do
  now = ~U[2026-10-14 10:00:00Z]
  assert Corkboard.side_due?(%{section: "The Earth", last: nil}, now)
  assert Corkboard.side_due?(%{section: "The Earth", last: ~U[2026-10-13 09:00:00Z]}, now)
  refute Corkboard.side_due?(%{section: "The Earth", last: ~U[2026-10-14 01:00:00Z]}, now)
  refute Corkboard.side_due?(%{section: "", last: nil}, now)
end
```

Code: `def side_due?(%{section: s, last: last}, now), do: String.trim(s) != "" and (last == nil or DateTime.diff(now, last) >= 86_400)`.
Done: `mise run server:test -- server/test/server/office/corkboard_test.exs` green. Commit.

## S2 · the per-seat counter lives on the standing thread

Test: write two `kind: "side project"` messages for `daneri` on `Server.Channel.machine_thread(ws)`,
assert `Corkboard.side_state(ws, "daneri") == %{n: 2, last: <created_at of the newer>}`; a seat with
none → `%{n: 0, last: nil}`; and after `GenServer.stop`+restart of the Corkboard the answer is the
same (state is the db's).

Code: `side_state/2` — `from(m in Message, where: m.thread_id == ^thread.id and m.kind == "side project" and m.author == ^name, select: {count(m.id), max(m.created_at)})`.
Persist with `post_side_project/4` modelled exactly on `suggest/4` (stored delivered, `payload: %{"note" => body, "n" => n}`; wakes nobody). Done: tests green; commit.

## S3 · write it — ride the lazy writer, no scheduler

Test: with `Server.Generator` stood in by `config :server, banter_cmd:` (as `writer_test.exs` does)
and banter on, a `notes/1` poll for a workspace with a bench seat whose soul has the section pins one
`kind == "side project"` note authored by that seat with its body; a second poll the same day pins
none; a seat without the section pins none; generator capped (`generator_daily_cap: 0`) or banter off
→ `notes/1` still answers and no note appears; the prompt handed to the writer contains "number 3"
when two earlier messages exist.

Code: in `handle_call({:notes, ws}, …)`, beside the existing `@every_s` branch, start one more
`Task.Supervisor` child that calls `side_write(ws)`: for the first on-bench seat (via
`Banter.context(ws).crew`) with `Server.Soul.section(...)` non-empty and `side_due?(side_state(...), now)`,
build the prompt `@side_voice <> "\n\nTHE SIDE PROJECT: " <> section <> "\nThis is number " <> n <> "; continue it, do not repeat. Previous: " <> last_body`, call
`Server.Office.Writer.write/2` (counts against `generator_daily_cap` through `Server.Generator`),
`parse/1` the body, `post_side_project/4`, then `GenServer.cast(me, {:pinned, ws, %{author: name, kind: "side project", body: body, re: nil}})`.
One seat per poll, so a cap or a slow model never fans out. `@side_voice` = `@voice` minus the
"never a ticket number" line, plus "this is an ongoing personal project: one small step of it".
Done: tests green; `mise run server:check` green. Commit.

## Wrap-up (any engineer)
1. `mise run check` green.
2. Drive it: `office:drive` the wide room with two souls where one `needles` the other; watch they never share foosball. (Headless draws only the rail room: wide-room check needs a kitty-graphics terminal.)
3. Report: tests added, anything deferred and where it was filed.

## Notes
- `sim.ts` uses `Math.random` directly (25 sites). Do **not** refactor it to an injected rng here;
  tests stub `Math.random` with `mulberry32`.
- Out of scope per spec: diary (step 5), voice (#264), per-pair feud arcs, side-project strip.
