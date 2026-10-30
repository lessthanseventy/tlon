# Plan — hall `s`: draft a hire's soul and pitch before the hire (ticket #660, plan task 7 of #65)

Source: `work/toy-step-9-the-hiring-hall-swipe-on-gene/plan.md` task 7. `e` (#369, `overrides.soul`/`overrides.pitch`)
is built; this adds the endpoint and the `s` key that feeds it. Not #301 (hire-time file).

## Decisions (assumed — shout if wrong)
1. **Soul** = `Server.Soul.preview/2`, a public wrapper over the existing `body/2`'s model-then-fallback (no second prompt).
   It writes nothing and seats nobody. Returns `{text, :model | :fallback}`.
2. **Pitch** = the fixed template `"<name>: a <grade> <archetype> for <specialty>."` (the old plan's fallback). The soul
   prompt is not widened to also write a pitch: that changes the prompt `draft/2` shares with every hire. `source` describes the soul.
3. **`@samples` names** (the bench's seeded names) return their sample, source `"fallback"` — that is what `body/2` does today.
4. **The draft lands as the overrides** `soul`, `pitch` and `drawn: true` via the existing `editField` path, so `e` edits it
   and a hire writes what was seen (`hallHire` already writes `c.soul`). A pass drops it (unless locked) — existing rule.
5. **Toy/sandbox:** `data.call` already answers 409 "it's a toy" to a POST, so `s` there shows that line; no fixed text built (YAGNI).
6. The render path never calls the server; only the key does (#59).

## Task 1 — `Server.Soul.preview/2` (server)
Files: `server/lib/server/soul.ex`, `server/test/server/soul_test.exs`.
- Test first (red: `preview/2` undefined), in `soul_test.exs` using the existing `stub_model/2`:
  - stub replies with all six `@sections` + `## Diary` → `{text, :model}`; `text` ends `## Diary\n`; no file appears in `dir`.
  - generator cmd unset (default `/nonexistent/...`) → `{text, :fallback}` with `## Wants`.
  - `Soul.preview("lonnrot", "reviewer")` (a `@samples` name) → `:fallback`, text = the sample.
- Code, next to `body/2`:
  ```elixir
  @doc "The soul `draft/2` would write for `name`, and whether the model wrote it; writes nothing."
  @spec preview(String.t(), String.t()) :: {String.t(), :model | :fallback}
  def preview(name, archetype) do
    cond do
      sample = Map.get(@samples, name) -> {sample, :fallback}
      text = from_model(name, archetype) -> {text, :model}
      true -> {fallback(name, archetype), :fallback}
    end
  end
  defp body(name, archetype), do: preview(name, archetype) |> elem(0)
  ```
  (Delete the old `body/2` body; `body` keeps its callers.)
- Done: `~/projects/menard/bin/menard run test --in server test/server/soul_test.exs`. Commit.

## Task 2 — `POST /api/workspaces/:id/hire/draft` (server)
Files: `server/lib/server/mcp/operator_api.ex`, `server/test/server/mcp/gateway_test.exs` (hire tests ~line 573).
- Test first (red: 404 no route): `post_json("/api/workspaces/#{id}/hire/draft", %{name: "sonny", archetype: "builder", grade: "senior", specialty: "server"})`
  → `{200, %{"soul" => s, "pitch" => "sonny: a senior builder for server.", "source" => "fallback"}}`, `s =~ "## Wants"`;
  with `:generator_cmd` stubbed as in soul_test → `"source" => "model"`; after both, `Workspaces.bench(id)` is unchanged and no
  soul file exists. `name: "Sonny"` → 422 (same message as hire); missing `archetype` → 400; unknown workspace → 404.
- Code: in `on_workspaces/3` add, before the catch-all, `defp on_workspaces(conn, "POST", [id, "hire", "draft"]), do: with_workspace(conn, id, &draft_hire(conn, &1))`.
  ```elixir
  # a soul and pitch for a hire not yet made: nothing written, nobody seated (the hall's `s`)
  defp draft_hire(conn, _ws) do
    case body(conn) do
      {%{"name" => name, "archetype" => arch} = b, conn} when is_binary(name) and is_binary(arch) ->
        case name_ok(name) do
          :ok ->
            {soul, source} = Soul.preview(name, arch)
            pitch = "#{name}: a #{b["grade"] || "junior"} #{arch} for #{b["specialty"] || "office"}."
            json(conn, 200, %{soul: soul, pitch: pitch, source: source})
          {:error, :bad_name} -> json(conn, 422, %{error: "a name is lowercase letters, digits, - and _, starting with a letter or digit"})
        end
      {_, conn} -> json(conn, 400, %{error: ~s(expected {"name", "archetype", "grade"?, "specialty"?})})
    end
  end
  ```
  Extract the 422 message into one `@bad_name` attribute shared with `hire/2` (two uses, DRY). Add the route to the moduledoc's list.
- Done: `menard run test --in server test/server/mcp/gateway_test.exs`. Commit.

## Task 3 — `data.draftSoul` + `hall.s` key + hall action (office)
Files: `office/tui/data.ts`, `office/tui/keys.ts`, `office/tui/main.ts`, `office/kit/hall.ts`, `office/test/hall.test.ts`.
- Test first in `hall.test.ts` (red: `drawn` pure fn missing): add pure `drawSoul(h, c, {soul, pitch})` in `kit/hall.ts` returning
  `{...h, overrides: {...h.overrides, soul, pitch, drawn: true}}`; test it round-trips through `saveHall`/`loadHall`, that
  `candidateOf` then shows the soul/pitch and `drawn: true`, and that `pass` drops them (unlocked) — mirrors the `editField` tests.
- `data.ts`, beside `talk`:
  `export async function draftSoul(ws: number, c: {name:string; archetype:string; grade:string; specialty:string}): Promise<{soul:string; pitch:string; source:string} | {error:string}>` — `call("POST", \`/workspaces/${ws}/hire/draft\`, c)`; 200 → json, else `{error: json?.error ?? "no draft"}`; catch → `{error: "the server didn't answer"}`.
- `keys.ts` hall block: `{ id: "hall.s", scope: "card:hall", key: "s", label: "draw a soul and pitch", verb: "draw" }`.
  Run `bun test test/keys.test.ts` — it enforces one verb per key per scope; if `s` or `draw` collides, pick the free letter and tell the ticket.
- `main.ts` hall actions (after `hall.e`): `{ ...bind("hall.s"), run: () => void hallDraw() }`, and next to `hallHire`:
  ```ts
  async function hallDraw() {
    if (ws === null) return
    const c = candidateOf(hall, hallCtx())
    status = `drawing ${c.name}…`; draw()
    const r = await data.draftSoul(ws, c)
    if ("error" in r) status = r.error
    else { hallSet(drawSoul(hall, r)); status = `drew ${c.name}'s soul (${r.source}) — e to edit` }
    draw()
  }
  ```
  Guard: if the candidate changed while the call ran (`candidateOf(hall,…).name !== c.name`), drop the result.
- Docs, same commit: `office/AGENTS.md` hall paragraph (add `s` and "calls `POST /api/workspaces/:id/hire/draft`; the render never does"); `hall.json` line says soul/pitch/drawn come from `s` or `e`.
- Done: `cd office && bun test && bunx tsc --noEmit`. Commit.

## Task 4 — gate and live check
- `menard run check --in server`; `cd office && bun test && bunx tsc --noEmit` (a coworker seat never runs `mise run check`; verify does).
- Live (verify stage, real server): `h`, `s` → status "drew …", soul row shows six sections; `e` on the soul row edits it; → hires and `souls/<name>.md` equals the shown text.

## Risks
- `s` may collide in keys.test.ts (Task 3 says what to do).
- A model call takes seconds; `data.call` times out at 8 s — a slow draft shows "the server didn't answer" and the hall is unchanged (acceptable v1).
- No migration, dep, gate or AGENTS.md-in-server change: no limit gate.
