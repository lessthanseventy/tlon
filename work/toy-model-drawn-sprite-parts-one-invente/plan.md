# Plan — model-drawn sprite parts, one invented accessory a day (#97)

Spec: `work/toy-model-drawn-sprite-parts-one-invente/spec.md` (final). Seven tasks, each its own commit,
red test first. Server tasks 1-3, office tasks 4-7. Every task ends green on its own verify command; the
last gate is `mise run check` (unsandboxed; a coworker seat runs `menard run check --in server` and the
office tests, and verify runs the full gate).

Commands used below
- server test: `~/projects/menard/bin/menard run test --in server <file>` (one JSON line; read failures there, never re-run to see more)
- office test: `cd office && bun test test/<file>.test.ts`
- office types: `cd office && bunx tsc --noEmit`
- Elixir edits go through `menard edit`; TypeScript through the Edit tool.
- Commit trailer: `Co-Authored-By: <your model> <noreply@anthropic.com>`.

Shared vocabulary. A **part payload** (what the model returns, what the db stores, what the feed
serves) is `{slot, front, side, back}`; each view is `{"<row 0..17>": "<12 chars>"}`. The id is
`gen:<YYYY-MM-DD>` of the day it was invented. Legal letters: `. _ y c g e w r o`.

---

## Task 1 — `Server.PartCheck` (pure validator)

Files: create `server/lib/server/part_check.ex`, `server/test/server/part_check_test.exs`.

Test first (`part_check_test.exs`):

```elixir
defmodule Server.PartCheckTest do
  use ExUnit.Case, async: true

  alias Server.PartCheck

  @row "..yyyyyy...."
  defp good, do: %{"slot" => "head", "front" => %{"2" => @row}, "side" => %{"2" => @row}, "back" => %{"2" => @row}}

  test "a well-formed part passes and comes back keyed by atoms" do
    assert {:ok, %{slot: "head", front: %{"2" => @row}, side: %{"2" => @row}, back: %{"2" => @row}}} =
             PartCheck.validate(good())
  end

  test "neck and hand are allowed, eyes mouth and back are not" do
    for s <- ~w(neck hand), do: assert({:ok, _} = PartCheck.validate(%{good() | "slot" => s}))
    for s <- ~w(eyes mouth back nope), do: assert({:error, :slot} = PartCheck.validate(%{good() | "slot" => s}))
  end

  test "all three views must be present and non-empty" do
    for v <- ~w(front side back) do
      assert {:error, {_, :missing}} = PartCheck.validate(Map.delete(good(), v))
      assert {:error, {_, :missing}} = PartCheck.validate(%{good() | v => %{}})
    end
  end

  test "rows are exactly 12 wide" do
    assert {:error, {:front, {:row, "2"}}} = PartCheck.validate(%{good() | "front" => %{"2" => "..yy"}})
    assert {:error, {:front, {:row, "2"}}} = PartCheck.validate(%{good() | "front" => %{"2" => @row <> "."}})
  end

  test "row index is 0 to 17" do
    assert {:ok, _} = PartCheck.validate(%{good() | "front" => %{"17" => @row}})
    assert {:error, {:front, {:row, "18"}}} = PartCheck.validate(%{good() | "front" => %{"18" => @row}})
    assert {:error, {:front, {:row, "x"}}} = PartCheck.validate(%{good() | "front" => %{"x" => @row}})
  end

  test "only the gear colours are legal; the body colours are refused" do
    assert {:ok, _} = PartCheck.validate(%{good() | "front" => %{"2" => "._ycgewro..."}})
    for bad <- ~w(k f s p b h), do: assert({:error, {:front, {:row, "2"}}} = PartCheck.validate(%{good() | "front" => %{"2" => "..#{bad}.........."}}))
  end

  test "garbage is a shape error, never a crash" do
    for junk <- [nil, [], "x", %{}, %{"slot" => "head", "front" => "no"}], do: assert({:error, _} = PartCheck.validate(junk))
  end
end
```

Implementation (`part_check.ex`):

```elixir
defmodule Server.PartCheck do
  @moduledoc """
  The one gate a model-drawn sprite part passes before it is kept (`Server.GeneratedParts`): a slot the
  office can dress (head, neck, hand), all three views, each a map of row index (0..17) to a row of exactly
  12 characters, and only the gear colours. The colour list must stay in step with `office/test/wcag.test.ts`
  (LEGAL), which proves each reads at 3:1 on the room's backgrounds; the body colours (k f s p b h) are refused.
  """

  @slots ~w(head neck hand)
  @views [{"front", :front}, {"side", :side}, {"back", :back}]
  @width 12
  @rows 0..17
  @legal ~c"._ycgewro"

  @spec validate(term()) :: {:ok, %{slot: String.t(), front: map(), side: map(), back: map()}} | {:error, term()}
  def validate(%{"slot" => slot} = part) when slot in @slots do
    Enum.reduce_while(@views, {:ok, %{slot: slot}}, fn {key, atom}, {:ok, acc} ->
      case view(part[key]) do
        :ok -> {:cont, {:ok, Map.put(acc, atom, part[key])}}
        {:error, why} -> {:halt, {:error, {atom, why}}}
      end
    end)
  end

  def validate(%{"slot" => _}), do: {:error, :slot}
  def validate(_), do: {:error, :shape}

  defp view(rows) when is_map(rows) and map_size(rows) > 0 do
    Enum.find_value(rows, :ok, fn {k, row} -> unless row_ok?(k, row), do: {:error, {:row, k}} end)
  end

  defp view(_), do: {:error, :missing}

  defp row_ok?(k, row) when is_binary(k) and is_binary(row) do
    case Integer.parse(k) do
      {i, ""} when i in @rows -> byte_size(row) == @width and row |> String.to_charlist() |> Enum.all?(&(&1 in @legal))
      _ -> false
    end
  end

  defp row_ok?(_, _), do: false
end
```

Done when: `menard run test --in server server/test/server/part_check_test.exs` is `ok`.
Commit: `server: PartCheck, the validator for model-drawn sprite parts (#97)`.

---

## Task 2 — table, `Server.GeneratedParts`, the daily job

Files: create `server/priv/repo/migrations/20261022030000_generated_part.exs`,
`server/lib/server/generated_parts.ex`, `server/test/server/generated_parts_test.exs`; edit
`server/lib/server/toy_pool.ex` (`refresh_all_due/1`).

Migration:

```elixir
defmodule Server.Repo.Migrations.GeneratedPart do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:generated_part) do
      add :workspace_id, :integer, null: false
      add :day, :date, null: false
      add :slot, :string, null: false
      add :front, :map, null: false
      add :side, :map, null: false
      add :back, :map, null: false
    end

    create unique_index(:generated_part, [:workspace_id, :day])
  end
end
```

Check `Server.TestDB.clean!/0` (server/test/support) truncates tables by listing: if it names tables, add
`generated_part`; if it truncates all, nothing to do.

Test first (`generated_parts_test.exs`). Copy the `setup` block of `server/test/server/toy_pool_test.exs`
(lines 11-33: stand-in model CLI that prints `@reply`, counts calls, resets env on exit) and the `count/1`
helper; change `@reply` to:

```elixir
@good ~s({"part": {"slot": "hand", "front": {"11": "..........yy"}, "side": {"11": ".yy........."}, "back": {"11": "..........yy"}}})
```

Tests (set `@reply` per test by writing the cli with the reply under test — give `setup` a
`reply` tag default of `@good`, or write a second cli file inside the test; keep it the simplest that reads):

```elixir
test "a day with no part invents one, validates it and keeps it", %{ws: ws, calls: calls} do
  day = ~D[2026-10-22]
  assert {:ok, %{id: "gen:2026-10-22", slot: "hand"}} = GeneratedParts.refresh_due(ws.id, day)
  assert [%{id: "gen:2026-10-22", day: "2026-10-22", slot: "hand", front: %{"11" => "..........yy"}}] = GeneratedParts.library(ws.id)
  assert count(calls) == 1
end

test "a second run the same day makes no call", %{ws: ws, calls: calls} do
  GeneratedParts.refresh_due(ws.id, ~D[2026-10-22])
  assert {:ok, :fresh} = GeneratedParts.refresh_due(ws.id, ~D[2026-10-22])
  assert count(calls) == 1
end

test "a part the validator rejects is not kept, the call still counts, and there is no retry", ctx do
  # reply: same shape with a body colour in a row, e.g. "..kk........"
  assert {:error, {:rejected, {:front, {:row, "11"}}}} = GeneratedParts.refresh_due(ctx.ws.id, ~D[2026-10-22])
  assert GeneratedParts.library(ctx.ws.id) == []
  assert count(ctx.calls) == 1
end

test "unparseable output is {:error, :unparsed}; banter off is {:error, :off}; the cap is {:error, :capped}, and none keeps a row", ctx do
  # three small cases; for :off use the same OperatorConfig switch toy_pool_test.exs uses, for :capped
  # Application.put_env(:server, :generator_daily_cap, 0)
end

test "library is oldest first and per workspace", %{ws: ws} do
  # refresh_due on two days, then assert the ids come back in day order and another workspace's library is []
end
```

Fill the last two bodies by copying how `toy_pool_test.exs` already proves `:off` and `:capped`
(grep it for `:capped` / `banter`).

Implementation (`generated_parts.ex`):

```elixir
defmodule Server.GeneratedParts do
  @moduledoc """
  One invented accessory a day per workspace, drawn by `Server.Generator` in the sprite row format and kept
  in `generated_part` (the library; nothing prunes it). `refresh_due/2` makes at most one model call a day:
  the output is parsed, checked by `Server.PartCheck`, and stored, or rejected and logged. A reject still
  counted against the generator's cap and is not retried. Off, capped or rejected means no row that day; the
  office wears nothing and shows no error. `library/1` is what `Server.ToyPool.day/1` serves.
  """
  use Ecto.Schema

  import Ecto.Query

  require Logger

  alias Server.{Generator, JsonBlob, PartCheck, Repo}

  schema "generated_part" do
    field :workspace_id, :integer
    field :day, :date
    field :slot, :string
    field :front, :map
    field :side, :map
    field :back, :map
  end

  @doc "Every kept part of `ws`, oldest first: `[%{id, day, slot, front, side, back}]` (views are row-index → 12-char row)."
  def library(ws) do
    Repo.all(from(p in __MODULE__, where: p.workspace_id == ^ws, order_by: p.day))
    |> Enum.map(fn p ->
      %{id: id(p.day), day: Date.to_iso8601(p.day), slot: p.slot, front: p.front, side: p.side, back: p.back}
    end)
  end

  @doc "Invent and keep `day`'s part unless one is kept already: `{:ok, part}`, `{:ok, :fresh}` or `{:error, why}`."
  def refresh_due(ws, day \\ Date.utc_today()) do
    if Repo.exists?(from(p in __MODULE__, where: p.workspace_id == ^ws and p.day == ^day)) do
      {:ok, :fresh}
    else
      with {:ok, out} <- Generator.run(prompt(day)),
           %{} = raw <- JsonBlob.first_valid(out, &part/1) || {:error, :unparsed},
           {:ok, checked} <- check(raw, day) do
        row = struct!(__MODULE__, Map.merge(checked, %{workspace_id: ws, day: day}))
        Repo.insert!(row, on_conflict: :nothing, conflict_target: [:workspace_id, :day])
        {:ok, Map.merge(checked, %{id: id(day), day: Date.to_iso8601(day)})}
      end
    end
  end

  defp part(%{"part" => %{} = p}), do: p
  defp part(_), do: nil

  defp check(raw, day) do
    case PartCheck.validate(raw) do
      {:ok, _} = ok ->
        ok

      {:error, why} ->
        Logger.warning("generated part for #{day} rejected: #{inspect(why)}")
        {:error, {:rejected, why}}
    end
  end

  defp id(day), do: "gen:" <> Date.to_iso8601(day)

  defp prompt(day) do
    "You draw accessories for a pixel-art office of AI coworkers. Invent ONE new accessory for #{day}: a hat, a scarf or necklace, or a thing held in the hand. " <>
      "Each figure is a 12-wide grid. Give the accessory in three views (front, side, back) as rows, row numbers 0-17 (hats sit on rows 0-3, the neck is rows 9-10, the hand is rows 11-12), " <>
      "every row exactly 12 characters. Letters: . leaves the pixel alone, _ clears it, and y c g e w r o are colours (y yellow, c grey, g green, e teal, w white, r red, o orange). Use no other letter. " <>
      ~s(Reply with ONLY JSON: {"part": {"slot": "head"|"neck"|"hand", "front": {"3": "..yyyyyy...."}, "side": {…}, "back": {…}}})
  end
end
```

(`%{} = raw <- … || {:error, :unparsed}` mis-matches the tuple: the `with` then returns `{:error, :unparsed}`
unchanged, which is what we want. If the formatter or compiler objects, split it into a `case`.)

In `toy_pool.ex`, change `refresh_all_due/1` to add the part, and update its doc line:

```elixir
for kind <- [:visitors, :puns | seats], do: {kind, refresh_due(ws, kind)}
```
becomes
```elixir
pools = for kind <- [:visitors, :puns | seats], do: {kind, refresh_due(ws, kind)}
pools ++ [{:part, Server.GeneratedParts.refresh_due(ws)}]
```

`scripts/tlon-cli.sh toys` already counts `{:ok, _}` as fresh and prints `{:error, why}` other than `:off`, so
it needs no change; a rejected part shows as `#<ws> :part: {:rejected, …}` and fails that run on purpose (the
reject is worth seeing). Update the `toys:refresh` description in `tasks/server.toml` to say "…and the day's
invented accessory".

Done when: `menard run test --in server server/test/server/generated_parts_test.exs` is `ok` and
`menard run test --in server server/test/server/toy_pool_test.exs` is `ok` (its pool-count assertions, if any
count `refresh_all_due` entries, gain one `:part` entry — update them).
Commit: `server: GeneratedParts, one model-drawn accessory a day through the generator (#97)`.

---

## Task 3 — serve the library on `ToyPool.day`

Files: edit `server/lib/server/toy_pool.ex`, `server/test/server/toy_pool_test.exs`,
`server/lib/server/mcp/operator_api.ex` (route doc line 40 only).

Test first, in `toy_pool_test.exs`: the existing empty-day assertion (line ~154) becomes

```elixir
assert ToyPool.day(ws.id) == %{visitors: [], puns: [], reactions: %{}, parts: []}
```

and add one test: after `Server.GeneratedParts.refresh_due(ws.id, ~D[2026-10-22])` with a stand-in reply
containing a valid part (reuse the CLI approach of the generated_parts test, or insert the row with
`Server.Repo.insert!(struct!(Server.GeneratedParts, …))`), `ToyPool.day(ws.id).parts` is
`[%{id: "gen:2026-10-22", slot: "hand", …}]`. Red first.

Implementation: in `ToyPool.day/1` return `%{visitors: …, puns: …, reactions: reactions, parts: Server.GeneratedParts.library(ws)}`;
update the `day/1` doc (`%{visitors, puns, reactions, parts}`) and the moduledoc's one sentence listing what
the pool holds. In `operator_api.ex` line 40 add `"parts": [{id, day, slot, front, side, back}]` to the
endpoint's description.

Done when: `menard run test --in server server/test/server/toy_pool_test.exs` is `ok`, then
`menard run check --in server` is `ok` (compiles with warnings-as-errors; all three server tasks in).
Commit: `server: the toys feed carries the part library (#97)`.

---

## Task 4 — office: data parts beside code parts, without shifting any look

Files: edit `office/kit/parts.ts`, `office/kit/door.ts`, `office/kit/sim.ts` (only the empty-pool literal);
create `office/test/data-parts.test.ts`; edit `office/test/door.test.ts`.

Test first (`data-parts.test.ts`):

```ts
import { afterEach, describe, expect, test } from "bun:test"
import { gearOf, idsIn, nextPart, useDataParts, type DataPart } from "../kit/parts"
import { lookOf, rollLook } from "../kit/sprites"

const part: DataPart = { id: "gen:2026-10-22", day: "2026-10-22", slot: "hand", front: { 11: "..........yy" }, side: { 11: ".yy........." }, back: { 11: "..........yy" } }
afterEach(() => useDataParts([]))

describe("data parts", () => {
  test("gearOf draws a gen: id from the loaded library, and nothing once it is gone", () => {
    expect(gearOf({ id: part.id })).toBeUndefined()
    useDataParts([part])
    expect(gearOf({ id: part.id })!.front[11]).toBe("..........yy")
  })
  test("they stay out of the roll: idsIn is code-only and every fixed name keeps its look", () => {
    const names = ["yu", "lonnrot", "tzinacan", "hronir", "uqbar", "daneri", "runeberg", "ulrikke"]
    const snap = () => JSON.stringify(names.map((n) => [lookOf(n), rollLook(n)]))
    const before = snap(), ids = idsIn("hand")
    useDataParts([part])
    expect(snap()).toBe(before)
    expect(idsIn("hand")).toEqual(ids)
  })
  test("nextPart offers them after the code parts of their slot, then none", () => {
    useDataParts([part])
    const codes = idsIn("hand"), seen: string[] = []
    let cur = nextPart("hand", undefined)
    for (let i = 0; i < 20 && cur; i++) { seen.push(cur.id); cur = nextPart("hand", cur) }
    expect(seen).toEqual([...codes, part.id])
  })
})
```

Implementation. In `parts.ts` (after `idsIn`):

```ts
/** a part the server's model drew: fixed rows per view, in one slot, id `gen:<day>`; kept out of PARTS/idsIn so rollLook's modulus (and every look) never moves */
export type DataPart = { id: string; day: string; slot: Slot; front: View; side: View; back: View }
let dataParts: DataPart[] = []
export function useDataParts(list: DataPart[]) { dataParts = list }
const dataIdsIn = (slot: Slot) => dataParts.filter((p) => p.slot === slot).map((p) => p.id)
```

`gearOf`: replace `if (!p) return undefined` with

```ts
if (!p) {
  const d = dataParts.find((x) => x.id === spec.id)
  return d && { front: d.front, side: d.side, back: d.back }
}
```

`nextPart`: `const ids = idsIn(slot)` → `const ids = [...idsIn(slot), ...dataIdsIn(slot)]`.

`door.ts`: `Toys` gains `parts: DataPart[]` (import the type from `./parts`); `toysOf` narrows it and returns it:

```ts
const rowsOf = (x: unknown): View | null => {
  if (!x || typeof x !== "object") return null
  const v: View = {}
  for (const [k, r] of Object.entries(x)) if (/^\d+$/.test(k) && typeof r === "string" && r.length === 12) v[Number(k)] = r
  return Object.keys(v).length ? v : null
}
const parts = (Array.isArray(o.parts) ? o.parts : []).flatMap((p): DataPart[] => {
  const q = p as Record<string, unknown> | null
  const front = rowsOf(q?.front), side = rowsOf(q?.side), back = rowsOf(q?.back)
  const ok = q && typeof q.id === "string" && q.id.startsWith("gen:") && typeof q.day === "string" && (SLOTS as readonly unknown[]).includes(q.slot)
  return ok && front && side && back ? [{ id: q.id as string, day: q.day as string, slot: q.slot as Slot, front, side, back }] : []
})
return { visitors, puns: strs(o.puns), reactions, parts }
```

(import `SLOTS`, `Slot`, `View`, `DataPart` from `./parts`.) In `sim.ts` the empty-pool literal in `pooled()`
gains `parts: []`. Run `bunx tsc --noEmit` and fix every other `Toys` literal it flags (tests included).

`door.test.ts`: add a `toysOf` test — a payload with one good part, one with a 5-char row, one with slot
`"eyes"`, one with id `"tophat"` → only the good one survives; an old payload with no `parts` gives `parts: []`.

Done when: `cd office && bun test test/data-parts.test.ts test/door.test.ts test/parts.test.ts` is green and
`bunx tsc --noEmit` is clean.
Commit: `office: data parts beside code parts, out of rollLook's pool (#97)`.

---

## Task 5 — office: wearer rule, pure

Files: edit `office/kit/looks.ts`; create `office/test/day-part.test.ts`.

Test first:

```ts
import { describe, expect, test } from "bun:test"
import { baseLook, wearerOf, wearing } from "../kit/looks"
import type { DataPart } from "../kit/parts"

const part: DataPart = { id: "gen:2026-10-22", day: "2026-10-22", slot: "head", front: { 2: "..yyyyyy...." }, side: { 2: "..yyyyyy...." }, back: { 2: "..yyyyyy...." } }
const bench = ["yu", "lonnrot", "tzinacan", "hronir"]

describe("the day's wearer", () => {
  test("one of the bench, the same whatever order they are listed in", () => {
    const w = wearerOf("2026-10-22", bench)
    expect(bench).toContain(w!)
    expect(wearerOf("2026-10-22", [...bench].reverse())).toBe(w)
  })
  test("it rotates: over a month more than one actor wears", () => {
    const days = Array.from({ length: 30 }, (_, i) => `2026-10-${String(i + 1).padStart(2, "0")}`)
    expect(new Set(days.map((d) => wearerOf(d, bench))).size).toBeGreaterThan(1)
  })
  test("nobody about, nobody wears", () => expect(wearerOf("2026-10-22", [])).toBeUndefined())
  test("wearing puts the part in its slot over what was there, and leaves the base look alone", () => {
    const base = { ...baseLook("yu"), parts: { head: { id: "tophat" }, hand: { id: "mug" } } }
    const on = wearing(base, part)
    expect(on.parts).toEqual({ head: { id: part.id }, hand: { id: "mug" } })
    expect(base.parts!.head).toEqual({ id: "tophat" })
  })
})
```

Implementation (`looks.ts`, add `hash` to the sprites import, `DataPart` type from `./parts`):

```ts
/** who wears the day's part: one of `names` by the day's hash, the same however they are ordered; undefined with nobody about */
export function wearerOf(day: string, names: readonly string[]): string | undefined {
  const sorted = [...names].sort()
  return sorted.length ? sorted[hash(day) % sorted.length] : undefined
}
/** `look` wearing `part` in its slot instead of what was there. A view over the look, never written back to looks.json */
export const wearing = (look: Look, part: DataPart): Look => ({ ...look, parts: { ...look.parts, [part.slot]: { id: part.id } } })
/** the server's day (`Date.utc_today`), which names a part */
export const today = (): string => new Date().toISOString().slice(0, 10)
```

Done when: `cd office && bun test test/day-part.test.ts` is green. Commit: `office: who wears the day's part (#97)`.

---

## Task 6 — office: the room dresses the wearer

Files: edit `office/kit/sim.ts`; create `office/test/day-part-room.test.ts`.

Test first (copy the `room()`/`inside()`/`seeded` scaffolding at the top of `office/test/door-visit.test.ts`;
type `Inside` also gets `actors: Map<string, { look: { parts?: Record<string, { id: string } | undefined> } }>`):

```ts
const part: DataPart = { id: `gen:${today()}`, day: today(), slot: "head", front: { 2: "..yyyyyy...." }, side: { 2: "..yyyyyy...." }, back: { 2: "..yyyyyy...." } }
const toys = (parts: DataPart[]) => ({ visitors: [], puns: [], reactions: {}, parts })
const wearers = (r: WideRoom) => [...inside(r).actors.values()].filter((a) => a.look.parts?.head?.id === part.id).length

test("exactly one actor wears today's part, and it is nobody's saved look", () => seeded(7, () => {
  const { r, a } = room()
  r.setToys(toys([part])); r.step(a)
  expect(wearers(r)).toBe(1)
}))
test("no part, or a part from another day, is worn by nobody", () => seeded(7, () => {
  const { r, a } = room()
  r.setToys(toys([])); r.step(a); expect(wearers(r)).toBe(0)
  r.setToys(toys([{ ...part, id: "gen:2020-01-01", day: "2020-01-01" }])); r.step(a); expect(wearers(r)).toBe(0)
}))
test("clearing the toys undresses them", () => seeded(7, () => {
  const { r, a } = room()
  r.setToys(toys([part])); r.step(a)
  r.setToys(null); r.step(a)
  expect(wearers(r)).toBe(0)
}))
test("the override layer is untouched: overrideFor and baseLook never see the part", () => { /* after the first test's step, import { overrideFor } from "../kit/looks" and assert overrideFor(name)?.parts is undefined for every actor */ })
```

Implementation in `sim.ts`:
1. imports: `import { looksGen, overrideFor, today, wearerOf, wearing } from "./looks"` and `useDataParts, type DataPart` from `./parts`.
2. Actor type (line 37): add `worn?: string`.
3. Replace `setToys` (line 684):
```ts
private dayPart: DataPart | null = null
setToys(t: Toys | null) {
  this.toys = t
  useDataParts(t?.parts ?? [])
  this.dayPart = t?.parts.at(-1) ?? null
}
```
4. In the people loop (line ~846), before `for (const r of l.people)`:
```ts
// one actor wears today's invented part, and only on its own day: a view over the look, never saved
const wearer = this.dayPart?.day === today() ? wearerOf(today(), l.people.map((r) => r.agent)) : undefined
const lookFor = (agent: string): Look => {
  const base = { ...lookOf(agent), ...overrideFor(agent) }
  return agent === wearer && this.dayPart ? wearing(base, this.dayPart) : base
}
const wornBy = (agent: string) => (agent === wearer ? this.dayPart!.id : "")
```
   line 857: `if (actor.lookGen !== looksGen() || actor.worn !== wornBy(r.agent)) { actor.look = lookFor(r.agent); actor.lookGen = looksGen(); actor.worn = wornBy(r.agent) }` (keep the trailing comment), and the constructor at line 861: `look: lookFor(r.agent), lookGen: looksGen(), worn: wornBy(r.agent),`.
   (`Look` is already imported there as a type.)

The weirdness gate already lives in `tui/main.ts:533` (curated passes `null`), so a curated room dresses nobody.

Done when: `cd office && bun test test/day-part-room.test.ts` green, then the whole office suite (`cd office && bun test`) and `bunx tsc --noEmit` are clean (existing golden tests must not move: with no toys nobody wears anything).
Commit: `office: the room dresses the day's wearer (#97)`.

---

## Task 7 — wcag guard for the legal letters

Files: edit `office/test/wcag.test.ts`.

This test is the guard that PartCheck's letter list can never drift from the palette. Add beside the skin
test (line ~69; it already imports `contrast`, `ROLE`):

```ts
import { paints } from "../kit/sprites"
// the letters Server.PartCheck lets a model-drawn part use (server/lib/server/part_check.ex @legal); `.` and `_` paint nothing
const LEGAL = ["y", "c", "g", "e", "w", "r", "o"]
test("every letter a model-drawn part may use reads at 3:1 against every room background", () => {
  const paint = paints(ROLE.prose, lookOf("yu"))   // import lookOf; the shirt/look do not matter for gear letters
  for (const letter of LEGAL) for (const bg of [ROLE.ground, ROLE.panel, ROLE.raised, ROLE.edge])
    expect({ letter, bg, ok: contrast(paint[letter]!, bg) >= 3 }).toMatchObject({ ok: true })
})
```

If a letter FAILS (likely candidates: `c` and `o` map to `structure` and `body`), do not weaken the test:
remove that letter from `@legal` in `part_check.ex` and from the prompt in `generated_parts.ex` and from
`LEGAL`, and add a line to `part_check_test.exs` that the letter is now refused. That is the whole point of
the guard.

Done when: `cd office && bun test test/wcag.test.ts` is green. Final: `mise run check` green (unsandboxed).
Commit: `office: wcag guard for the letters a model-drawn part may use (#97)`.

---

## Docs, in the commit that makes them stale
- Task 3: the endpoint line in `operator_api.ex` and `ToyPool` moduledoc.
- Task 2: `tasks/server.toml` `toys:refresh` description; `scripts/tlon-cli.sh` line ~53 comment ("…and the day's invented accessory").
- Task 4: the header comment of `office/kit/parts.ts` gains one sentence: data parts (`gen:` ids) are drawn by the server's model, loaded by `useDataParts`, kept out of PARTS/idsIn.

## Out of scope (spec)
Retries, curation UI, eyes/mouth/back slots, dials, pruning of the library.

## Risks the builder should know
- `rollLook` is why data parts are not in `idsIn`; task 4's snapshot test is the tripwire. Do not "simplify" by adding them there.
- Task 6 compares `part.day` to the office's `today()` in UTC; if the office box's clock is far off UTC the wearer appears at the UTC midnight, not local. Intended: matches the server's day.
- `Generator.run` needs banter on and cap left; every server test uses the stand-in CLI, never the real model.
