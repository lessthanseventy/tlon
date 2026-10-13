# Plan — Toy step 9: the hiring hall (ticket #65, thread 257)

Spec: `work/toy-step-9-the-hiring-hall-swipe-on-gene/spec.md`. Seven tasks, one commit each, in order.
Server tasks first (1–2), then pure office kit (3–4), then the view (5–7). Commit trailer on every
commit: `Co-Authored-By: <your model> <noreply@…>` per the repo AGENTS.md.

Loop commands (from the worktree root): server tests
`~/projects/menard/bin/menard run test --in server <file>`; office tests `cd office && bun test <file>`;
final gate `mise run check` (run unsandboxed). Edit Elixir with Menard verbs, TS with Edit.

## Task 0 — prerequisite (no commit): `Server.Soul` must exist
Spec §5 builds on #61's `Server.Soul`. On this branch `server/lib/server/soul.ex` does **not** exist; it
lives on the unmerged `work/souls-step-2-first-drafts-from-their-bor` (commits 57f98fc…82588e3).
- Check: `test -f server/lib/server/soul.ex && echo ok`.
- If missing: stop and wait for souls-step-2 to land on main, then `git rebase origin/main` this branch.
  **Do not re-implement or cherry-pick it into this branch.** Tell the thread; the lead decides.
- Nothing else in tasks 3–7 depends on it, so tasks 3–4 may proceed while waiting.

## Task 1 — `Server.Soul.create/2` (extract the exclusive write)
Files: `server/lib/server/soul.ex`, `server/test/server/soul_test.exs`.

Failing test first (append inside `Server.SoulTest`, uses the existing `setup`/`dir`):
```elixir
test "create/2 writes once and never over an existing file", %{dir: dir} do
  assert {:ok, :written} = Soul.create("borges-2", "## Wants\nquiet\n")
  assert File.read!(Path.join(dir, "borges-2.md")) == "## Wants\nquiet\n"
  assert {:ok, :exists} = Soul.create("borges-2", "something else")
  assert File.read!(Path.join(dir, "borges-2.md")) == "## Wants\nquiet\n"
end

test "create/2 refuses a bad name and writes nothing", %{dir: dir} do
  assert {:error, :bad_name} = Soul.create("../evil", "x")
  refute File.exists?(Path.join(dir, "../evil.md"))
end

test "valid_name?/1 is the one name check" do
  assert Soul.valid_name?("ireneo_2")
  refute Soul.valid_name?("Ireneo")
  refute Soul.valid_name?("")
end
```
Implementation (replace private `create/3`; `check_name/1` stays private, `valid_name?/1` wraps it):
```elixir
@doc "Write `body` as `<name>.md` if there is none; an existing file is left alone, edited or not."
@spec create(String.t(), String.t()) :: {:ok, :written | :exists} | {:error, :bad_name}
def create(name, body) do
  with :ok <- check_name(name) do
    File.mkdir_p!(dir())

    case File.write(Path.join(dir(), name <> ".md"), body, [:exclusive]) do
      :ok -> {:ok, :written}
      {:error, :eexist} -> {:ok, :exists}
    end
  end
end

@doc "Whether `name` is a legal soul/seat handle (`^[a-z0-9][a-z0-9_-]*$`)."
@spec valid_name?(term()) :: boolean()
def valid_name?(name), do: is_binary(name) and check_name(name) == :ok
```
In `draft/2` replace `create(path, name, archetype)` with `create(name, body(name, archetype))` (keep the
`File.exists?` short-circuit so the model is not called for an existing soul); delete `create/3`.
Done: `menard run test --in server server/test/server/soul_test.exs` green, old `draft/2` tests unchanged and green.

## Task 2 — `POST /api/workspaces/:id/hire`
Files: `server/lib/server/mcp/operator_api.ex`, `server/test/server/mcp/gateway_test.exs`.

Failing tests first (in the describe that has the `coworkers` POST tests, same helpers `post_json`,
workspace creation; set `Application.put_env(:server, :souls_dir, tmp)` + restore in `on_exit` as soul_test does):
```elixir
test "hire seats, writes the soul once and answers 201" do
  # ws created like the coworkers test above
  r = post_json("/api/workspaces/#{ws["id"]}/hire",
        %{name: "hall-ireneo", archetype: "builder", grade: "junior", specialty: "office", soul: "## Wants\nsleep\n"})
  assert %{"name" => "hall-ireneo", "soul" => "written"} = r
  assert Enum.any?(Server.Workspaces.bench_all(ws["id"]), &(&1.name == "hall-ireneo"))
  assert File.read!(Path.join(souls_dir, "hall-ireneo.md")) == "## Wants\nsleep\n"
end

test "hire with a bad name is refused and seats nobody" do
  before = length(Server.Workspaces.bench_all(ws["id"]))
  assert {422, _} = request_status(:post, "/api/workspaces/#{ws["id"]}/hire", %{name: "Bad Name", archetype: "builder"})
  assert length(Server.Workspaces.bench_all(ws["id"])) == before
end
```
(Use whatever status-returning helper that file already has; mirror the `:unknown_model` 422 test at ~L442.)

Route + handler, next to `hire/2` (L888), same shape:
```elixir
defp on_workspaces(conn, "POST", [id, "hire"]), do: with_workspace(conn, id, &hall_hire(conn, &1))

# the hiring hall's one call: seat first (the only refusable step), then persona, then soul; a failure
# after the seat leaves a working seat and says so in the reply instead of crashing
defp hall_hire(conn, ws) do
  case body(conn) do
    {%{"name" => name, "archetype" => arch} = b, conn} when is_binary(name) and is_binary(arch) ->
      with true <- Server.Soul.valid_name?(name) || {:error, "name must match ^[a-z0-9][a-z0-9_-]*$"},
           {:ok, c} <-
             Workspaces.seat(ws.id, %{name: name, archetype: arch, grade: b["grade"], specialty: b["specialty"], crew: "all"}) do
        Task.Supervisor.start_child(Server.TaskSupervisor, fn -> Server.Persona.ensure(ws.id, c.name) end)
        soul = soul_result(name, b["soul"])
        json(conn, 201, %{seat_id: c.id, agent_id: c.agent_id, name: c.name, archetype: c.archetype, soul: soul})
      else
        {:error, why} when is_binary(why) -> json(conn, 422, %{error: why})
        {:error, why} -> refused(conn, why)
      end

    {_, conn} ->
      json(conn, 400, %{error: ~s(expected {"name", "archetype", "grade"?, "specialty"?, "soul"?})})
  end
end

defp soul_result(_name, soul) when not is_binary(soul), do: "skipped"
defp soul_result(name, soul) do
  case Server.Soul.create(name, soul) do
    {:ok, r} -> Atom.to_string(r)
    {:error, _} -> "failed"
  end
rescue
  _ -> "failed"
end
```
Add the route to the endpoint list in the module doc (near L95):
`POST /api/workspaces/:id/hire {"name","archetype","grade"?,"specialty"?,"soul"?} → seat + persona + soul; 201`.
Do **not** change the existing `hire/2`. Done: `menard run test --in server server/test/server/mcp/gateway_test.exs` green.

## Task 3 — `office/kit/hall.ts`: the candidate, pure
Files: new `office/kit/hall.ts`, new `office/test/hall.test.ts`. No I/O, no model.

Failing tests first:
```ts
import { describe, expect, test } from "bun:test"
import { roll, nextSeed, BORGES } from "../kit/hall"

const VOCAB = { archetypes: ["builder", "reviewer", "planner"], grades: ["junior", "senior", "greybeard"], specialties: ["office", "server"] }

describe("hall roll", () => {
  test("same (seed, locks, taken) → identical candidate", () => {
    expect(roll("hall:7", { taken: [], locks: {}, vocab: VOCAB })).toEqual(roll("hall:7", { taken: [], locks: {}, vocab: VOCAB }))
  })
  test("the name is legal and not already taken", () => {
    const c = roll("hall:3", { taken: BORGES.slice(0, BORGES.length - 1), locks: {}, vocab: VOCAB })
    expect(c.name).toMatch(/^[a-z0-9][a-z0-9_-]*$/)
    expect(BORGES.slice(0, BORGES.length - 1)).not.toContain(c.name)
  })
  test("all names taken → a seeded original name, still legal", () => {
    const c = roll("hall:3", { taken: [...BORGES], locks: {}, vocab: VOCAB })
    expect(c.name).toMatch(/^[a-z0-9][a-z0-9_-]*$/)
    expect(BORGES).not.toContain(c.name)
  })
  test("a pass keeps locked slots and locked fields from the previous candidate", () => {
    const a = roll("hall:1", { taken: [], locks: {}, vocab: VOCAB })
    const b = roll("hall:2", { taken: [], locks: { slots: ["head", "hand"], fields: ["grade"] }, prev: a, vocab: VOCAB })
    expect(b.look.parts?.head).toEqual(a.look.parts?.head)
    expect(b.look.parts?.hand).toEqual(a.look.parts?.hand)
    expect(b.grade).toBe(a.grade)
    expect(b.seed).toBe("hall:2")
  })
  test("pitch and soul skeleton are deterministic text, drawn=false", () => {
    const c = roll("hall:9", { taken: [], locks: {}, vocab: VOCAB })
    expect(c.pitch.length).toBeGreaterThan(0)
    expect(c.soul).toContain("## Wants")
    expect(c.drawn).toBe(false)
  })
  test("nextSeed counts hall:<n> up", () => { expect(nextSeed("hall:41")).toBe("hall:42"); expect(nextSeed("junk")).toBe("hall:1") })
})
```
Implementation sketch (complete the lists; ≥24 Borges names, lower-case, e.g. `funes, lonnrot, tzinacan, ireneo, hladik, fervor, otalora, emma, nolan, ryan, cruz, asterion, ts_ai_ang…` — keep to legal chars; 3 pitch templates; skeleton uses `SOUL_SECTIONS` from `./souls`):
```ts
import { BODIES, hash, lookOf, rollLook, type Look } from "./sprites"
import { SLOTS, type Slot } from "./parts"
import { SOUL_SECTIONS } from "./souls"

export type Vocab = { archetypes: string[]; grades: string[]; specialties: string[] }
export type Field = "name" | "archetype" | "grade" | "specialty"
export type Locks = { slots?: Slot[]; fields?: Field[] }
export type Candidate = {
  seed: string; name: string; archetype: string; grade: string; specialty: string
  look: Look; pitch: string; soul: string; drawn: boolean
}
export const BORGES = ["funes", /* … ≥24 … */] as const

export const nextSeed = (s: string) => `hall:${(/^hall:(\d+)$/.exec(s)?.[1] ? Number(/^hall:(\d+)$/.exec(s)![1]) : 0) + 1}`

export function roll(seed: string, o: { taken: readonly string[]; locks: Locks; prev?: Candidate; vocab: Vocab }): Candidate {
  const pick = <T,>(xs: readonly T[], k: string) => xs[hash(seed + k) % xs.length]!
  const keep = <K extends Field>(f: K, v: Candidate[K]): Candidate[K] => (o.locks.fields?.includes(f) && o.prev ? o.prev[f] : v)
  const free = BORGES.filter(n => !o.taken.includes(n))
  const fresh = free.length ? pick(free, "name") : `hall-${(hash(seed + "n") % 9000) + 1000}`
  const name = keep("name", fresh)
  const rolled = rollLook(seed)
  const parts = { ...rolled.parts }
  for (const s of SLOTS) if (o.locks.slots?.includes(s) && o.prev) { const p = o.prev.look.parts?.[s]; if (p) parts[s] = p; else delete parts[s] }
  const look: Look = { ...lookOf(seed), ...rolled, parts }
  const archetype = keep("archetype", pick(o.vocab.archetypes, "arch"))
  const grade = keep("grade", pick(o.vocab.grades, "grade"))
  const specialty = keep("specialty", pick(o.vocab.specialties, "spec"))
  const pitch = `${name}: a ${grade} ${archetype} for ${specialty}.`   // 3 templates picked by hash, ≥1 sentence
  const soul = SOUL_SECTIONS.filter(h => h !== "Diary").map(h => `## ${h}\n`).join("\n")
  return { seed, name, archetype, grade, specialty, look, pitch, soul, drawn: false }
}
```
Note a locked name that is now taken (hired meanwhile) must re-roll: `keep("name", …)` returns prev only if
`!o.taken.includes(prev.name)`. Add that and a test. `BODIES` import only if used.
Done: `cd office && bun test test/hall.test.ts` green; `bunx tsc --noEmit` clean (office's typecheck as in `mise run office:*`).

## Task 4 — `hall.json` load / save / pile (pure + tiny fs)
Files: `office/kit/hall.ts` (add), `office/test/hall.test.ts` (add). Path from the TUI, not the kit.

Shape (spec §6): `{ seed, locks, overrides, soulDrawn?, pile: [{seed, overrides, soul?}] }`. Store seed + overrides
only, never the rendered result.

Failing tests first:
```ts
test("hall.json round trip keeps seed, locks, overrides and the pile", () => {
  const dir = mkdtempSync(join(tmpdir(), "hall-")), p = join(dir, "hall.json")
  const s = { seed: "hall:5", locks: { slots: ["eyes"] }, overrides: { name: "borges" }, pile: [{ seed: "hall:2", overrides: {} }] }
  saveHall(p, s); expect(loadHall(p)).toEqual(s)
})
test("a missing or corrupt file is the empty hall, not a crash", () => {
  expect(loadHall("/nonexistent/hall.json").pile).toEqual([])
})
test("hallSignature changes when the file does", () => { /* write, sig a; write again, sig b; a !== b */ })
test("a pile entry re-renders identically from seed + overrides", () => {
  const c = roll("hall:2", { taken: [], locks: {}, vocab: VOCAB })
  expect(applyOverrides(roll("hall:2", { taken: [], locks: {}, vocab: VOCAB }), {})).toEqual(c)
})
```
Implement `loadHall(path)`, `saveHall(path, s)` (`mkdirSync(dirname, {recursive})`, write JSON), `hallSignature(path)`
(mtimeMs, `""` when absent — same shape as `soulsSignature`), `applyOverrides(c, ov)` (spreads
`name/archetype/grade/specialty/soul/pitch/drawn` overrides, never `seed`). Pile helpers: `pushPile`,
`dropPile(i)`, cap the pile at 50.
Done: `bun test test/hall.test.ts` green.

## Task 5 — the hall view, sandbox first
Files: `office/tui/main.ts` (Mode + keys + draw), new `office/tui/hall.ts` (the card's rows, pure: `hallRows(c, sel, locks) → Row-like lines`),
`office/tui/sandbox.ts` (a `hire(c)` on `toy()` that appends to `bench`, `souls` map, and a looks entry),
`office/test/hall-view.test.ts`, `office/test/sandbox.test.ts`.

1. Failing tests: `hallRows` returns rows `name, archetype, grade, specialty, pitch` + one per `SLOTS` (6), marks
   locked rows, and `sel` wraps; `toy().hire(c)` makes `snapshot().bench` contain the name and grows by one.
2. Add `{ kind: "hall" }` to `Mode` (L54–61). Open it with `H` from home (pick a free key — grep the home key
   table in main.ts first) and list it in the help line. State: `let hallState = loadHall(HALL)`, `HALL = process.env.TLON_HALL ?? <config>/tlon/hall.json`
   (sandbox: `join(tmpdir(), "tlon-sandbox-hall.json")` so a toy pile never reaches the office).
3. Keys inside the mode, exactly spec §2: `←` pass (`nextSeed`, `roll` with `taken = all.bench names ∪ pile names`,
   locks carried), `↑` push to pile then pass, `→` hire (task 6; in sandbox calls `world.hire`), `tab/shift-tab` move row,
   `space` toggle lock on the row (slot rows → `locks.slots`, field rows → `locks.fields`), `esc` back and keep the
   roll (`saveHall`), `m` pile browser (↑/↓, enter bring back, `x` drop).
4. Draw: the full-size figure for all three views via `figure(look, archetype, false, false, face, "stand", 0, false)`
   with `face` ∈ down/left/up (reuse the look card's drawing code at L~1500 — find it, do not copy a second renderer).
5. Poll `hallSignature` beside `looksSeen`/`soulsSeen` (L248–265) so a hand edit shows up.
Done: `bun test` (office) green; `mise run office:drive` run: `H`, `←`,`←`,`↑`,`→` in the sandbox → the new
person is on the bench and in `souls/` + looks of the sandbox dir (spec §9.3).

## Task 6 — office hire: the confirm modal and the endpoint call
Files: `office/tui/data.ts`, `office/tui/main.ts`, `office/test/data.test.ts`, `office/test/hall-view.test.ts`.

1. Failing test (data.test.ts, shaped like the existing fetch-stub tests there): `data.hire(ws, c)` POSTs
   `/api/workspaces/<ws>/hire` with `{name, archetype, grade, specialty, soul}` and returns `{ ok, soul }`; a 422
   returns `{ ok:false, error }` without throwing.
2. `data.hire` next to `talk` (L~131), same `try/catch` shape. `call()` already refuses non-GET under `fake`, which is
   right — the sandbox hires through `world.hire`.
3. `→` in office mode opens the existing `confirm` (main.ts L~133: `{label, run}`) with label
   `hire <name> — <archetype>, <grade>, crew all, will be staffed work`; `y`/enter runs, `esc` seats nobody.
   On `run`: `await data.hire`, then `saveLook(name, c.look)` (existing function L90), drop the candidate from the pile if
   it came from there, roll the next seed, toast `hired <name>` or the error. A `soul:"failed"` reply toasts
   `hired <name> — soul not written` and does not roll back.
4. Never write `souls/` from the TUI in office mode (server owns it); sandbox mode writes via `world.hire`.
Done: `bun test` green; `office:drive`: in office mode `→` shows the confirm and `esc` leaves the bench unchanged
(spec §9.3).

## Task 7 — soul + pitch on demand (D2 default A)
Files: `server/lib/server/mcp/operator_api.ex`, `server/lib/server/generator.ex` (use, don't change),
`server/test/server/mcp/gateway_test.exs`, `office/tui/data.ts`, `office/tui/main.ts`.

1. Failing server test: `POST /api/workspaces/:id/hire/draft {"name","archetype","grade","specialty","seed"}` with the
   generator off/capped returns 200 `{"soul": <skeleton>, "pitch": <text>, "source": "fallback"}`; with the stub model
   (`:generator_cmd`, as soul_test's `stub_model`) returns `"source": "model"`. It writes nothing and seats nobody.
2. Handler: build the prompt the way `Server.Soul.from_model/2` does (reuse it — expose a `Server.Soul.preview(name, archetype)`
   returning `{text, :model | :fallback}` from the existing private `from_model`/`fallback`; no duplicate prompt),
   plus a one-line pitch from the same call or the fallback `"<name>: a <grade> <archetype> for <specialty>."`.
3. TUI: `s` calls `data.draftSoul(ws, c)`, stores `c.soul`, `c.pitch`, `c.drawn = true`, persists to `hall.json`
   (`soulDrawn`); **hire** sends `c.soul` as-is so the seat gets exactly what was seen. Pass/reroll never calls it.
   The render path never calls the server (#59).
4. Sandbox `s`: deterministic fixed text, no call.
Done: server test + `bun test` green.

## Close-out
- Docs in the same commits: `office/AGENTS.md` (the hall mode, `TLON_HALL`, keys), `server/AGENTS.md` only if it
  lists API routes; update the operator_api moduledoc (done in task 2/7).
- `mise run check` green (unsandboxed, one at a time), then hand off for review.
- Seams per spec §7: keep `Candidate` kind-agnostic; build nothing for #66/#68.

## Risks / open
- Task 0 (Soul on main) blocks tasks 1–2 and 7.
- D1–D3 still pending operator answers; plan uses the recommended defaults. D1 touches only task 6, D2 only task 7,
  D3 only task 4.
- Grade/archetype/specialty vocab: `archetypes` from the snapshot (`all.archetypes`), grades `junior|senior|greybeard`
  (`Server.Roster`), specialties `office|server`; wire the snapshot's list in task 5, fall back to the constants in tests.
