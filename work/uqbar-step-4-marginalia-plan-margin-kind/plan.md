# Uqbar step 4 — marginalia: plan

Spec: `docs/plans/2026-10-08-uqbar-design.md` §4, §6, §7 step 4. Ticket #49. Scope fence: `U`
mark-read and the entry are step 5 (#50); small joys step 6 (#51).

Check (from §7): *notes written while the office was unfocused are full ink on return and fade after.*

## Decisions (the four the brief asked for)

**(a) Where notes come from, and their shape.**
- Written: a new MCP tool `margin_note(text, workspace_id?)` posts a `margin`-kind message, author
  = the caller's agent (`uqbar`), on the **workspace's root thread** (`Server.Channel.machine_thread/1`).
  `post_message` cannot do it: it posts to the caller's own thread and takes no `kind`.
- Read: a new `GET /api/office/margin/:ws` → `Server.Office.Margin.notes/1`, newest first, cap 12:
  `[%{id, author, body, at}]` (`at` unix seconds). Same shape/route pattern as `/office/suggestions/:ws`.
  Not `/office/activity`: that feed is already a rollup of other things; margins are a kind of message.
- `#N` refs are parsed **client-side** from `body` with `/#(\d+)/g` (one place, in `kit/margin.ts`);
  no server field. `cut <sha>` notes carry no `#N`, so they are plain text (no link; step 5's footnotes own shas).
- Needs a **DB migration**: `message_kind_check` is a CHECK constraint (migrations
  `20260925100000`, `20261008060000`, `20261009020000`), so the changeset alone is not enough.
  `margin` must also reach nobody (switchboard) and must not count as an `@operator` mention (Needs).

**(b) "Since you last looked": purely client-side, no server signal.**
- Terminal focus reporting: DEC 1004 (`ESC[?1004h` on enter, `?1004l` on leave); focus-in `ESC[I`,
  focus-out `ESC[O` become a new `Input` `{t:"focus", on}`.
- `Looks` (in `kit/margin.ts`): a `focusedS` clock that advances only while focused, and per note
  the focused-clock reading when it was first *seen*. A note is **unseen** until a frame is drawn while
  focused; unseen = full ink. Seen at `focusedS = s0` → its age is `focusedS - s0`.
- Survives a restart: one small state file (`~/.local/state/…/margin-looked`, via the existing
  `readState`/`writeState` like `TRAY`) holds `lookedAt` (epoch s of the last focused moment, stamped at
  most every 5 s while focused and on focus-out). On load, a note with `at <= lookedAt` is already seen,
  aged by wall time `lookedAt - at` (a stated upper bound on its focused age); newer ones are unseen.
  Survival *across surfaces* is explicitly out of scope (step 5's `U` is the mark-read key).

**(c) Fade: a pure function of focused age.** `inkAlpha(age) = 1` for `age <= HOLD_S (60)`, then
linear down to `FLOOR (0.45)` at `HOLD_S + FADE_S (1200)`, then flat. The floor keeps every note
legible (amber on black; the operator has XLRS — never fade to invisible). Colour =
`tint(ROLE.body, ROLE.ground, alpha)`. No clock reads inside: callers pass `focusedS`, so tests and
goldens are deterministic.

**(d) Enter on a note reuses the open-thread path.** Notes are drawn as `Hit`s with
`act: {kind:"thread", tid}` — the same act a whiteboard card click runs (`act()` → `open({kind:"thread"})`,
`main.ts:378`). Hovering a note (mouse motion over its hit) sets `lit = tid`; the room draws that
card as picked (`picked = lit ?? picked` at the `render` call, `main.ts:1405`), and `enter` in home mode with
`lit !== null` runs `act({kind:"thread", tid: lit})`. No keyboard note-cursor in this step (open item, below).

**Layout / how the notes are drawn.** In the frame's bottom-left, over the hallway runner
(`HALL` row region), as `text` ink appended **after `clipFrame`** in `main.ts` so a pan can't push
them off-screen. Newest on top (nearest the room's interior), older ones below toward the frame edge,
max 5 lines, each cut to 44 chars. Because they are composed after the room render, **no room frame
changes → `golden.json` is not re-hashed, and `office/rooms/wide.ts` / `office/kit/uqbar.ts` are
untouched** (those are step 3 workline A's files, #235).

## Sequencing / split

Two worklines, recommended (the server half is small but is its own gate and touches none of step 3's files):

- **S — server** (Tasks S1–S4): can start now, in parallel with step 3.
- **O — office** (Tasks O1–O4): needs S merged (reads `/office/margin`) — or builds against the
  endpoint's documented shape with `fetch` faked, which `data.margin` allows. Touches `term.ts`,
  `tui/main.ts`, new `kit/margin.ts`; no step-3 file. Serialising behind step 3 A is for review
  sanity only, not for conflicts.

Commands: server — `mise run server:test` (or `cd server && mix test <file>`); office —
`mise run office:test`, full gate `mise run check` (precommit is `--warnings-as-errors`).
Each task = one commit; red test first.

---

## S1 — the `margin` kind exists (migration + changeset)

Files: `server/priv/repo/migrations/20261010000000_message_margin.exs` (new),
`server/lib/server/message.ex:62`, `server/test/server/message_test.exs` (new if absent; else append).

Test first (red: `:margin` is not in the inclusion list and the CHECK refuses the insert):

```elixir
defmodule Server.MessageMarginTest do
  use ExUnit.Case, async: false

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Margins"})
    {:ok, root} = Server.Channel.open_thread(%{title: "standing", scope: "machine", workspace_id: ws.id})
    %{root: root}
  end

  test "a margin note is a valid kind and survives the CHECK constraint", %{root: root} do
    assert {:ok, %Server.Message{kind: "margin"} = m} =
             Server.Channel.post(%{thread_id: root.id, author: "uqbar", body: "#174 back to build", kind: "margin"})

    assert %Server.Message{kind: "margin"} = Server.Repo.get(Server.Message, m.id)
  end

  test "an unknown kind is still refused" do
    cs = Server.Message.post_changeset(%{thread_id: 1, author: "a", body: "b", kind: "scribble"})
    refute cs.valid?
  end
end
```

Code:

```elixir
# 20261010000000_message_margin.exs
defmodule Server.Repo.Migrations.MessageMargin do
  @moduledoc false
  use Ecto.Migration

  # A `margin` is one of Uqbar's one-line margin notes (docs/plans/2026-10-08-uqbar-design.md §4)
  # kept on the workspace's root thread: stored delivered, it wakes nobody; the office draws it.
  def up do
    drop constraint(:message, :message_kind_check)

    create constraint(:message, :message_kind_check,
             check: "kind in ('chat', 'prompt', 'stall', 'notice', 'suggestion', 'margin')"
           )
  end

  def down do
    execute "DELETE FROM message WHERE kind = 'margin'"
    drop constraint(:message, :message_kind_check)

    create constraint(:message, :message_kind_check,
             check: "kind in ('chat', 'prompt', 'stall', 'notice', 'suggestion')"
           )
  end
end
```

`message.ex:62` → `validate_inclusion(:kind, ["chat", "prompt", "stall", "notice", "suggestion", "margin"])`.

Done when: `cd server && mix test test/server/message_test.exs` (path as created) green; `mix ecto.rollback --step 1 && mix ecto.migrate` on `tlon_test` is clean.

## S2 — a margin note wakes nobody and is not a mention

Files: `server/lib/server/switchboard.ex:177,212`, `server/lib/server/office/needs.ex:259`,
tests in `server/test/server/switchboard_test.exs` and `server/test/server/office/needs_test.exs`.

Tests first (mirror the existing `suggestion` cases in each file — grep `"suggestion"` there and copy the
setup, changing kind to `"margin"`):
- switchboard: a `margin` post on a thread whose lead has a live session claims the row (`delivered_at` set)
  and wakes **no** session — same assertions as the `suggestion`/`notice` case.
- needs: a `margin` body containing `@<operator>` produces no `:mention` need.

Code (three one-word changes):

```elixir
# switchboard.ex
defp reaches_nobody?(%Message{kind: kind}) when kind in ["notice", "suggestion", "margin"], do: true
defp recipients(%Message{kind: kind}) when kind in ["notice", "suggestion", "margin"], do: []
# needs.ex (mentions/2 where clause)
m.thread_id in ^ids and m.kind not in ["suggestion", "margin"] and m.author != ^operator and ...
```

Also update the `recipients` doc comment's bullet list to mention `margin`.

Done when: those two test files green. Command: `cd server && mix test test/server/switchboard_test.exs test/server/office/needs_test.exs`.

## S3 — the read path: `Server.Office.Margin.notes/1` + `GET /office/margin/:ws`

Files: `server/lib/server/office/margin.ex` (new), `server/lib/server/mcp/operator_api.ex`
(route + the route list in the moduledoc at line ~28), `server/test/server/office/margin_test.exs` (new).

Test first:

```elixir
defmodule Server.Office.MarginTest do
  use ExUnit.Case, async: false
  alias Server.Office.Margin

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Margins"})
    {:ok, root} = Server.Channel.open_thread(%{title: "standing", scope: "machine", workspace_id: ws.id})
    {:ok, other} = Server.Channel.open_thread(%{title: "work", workspace_id: ws.id})
    %{ws: ws, root: root, other: other}
  end

  test "the workspace's margin notes, newest first, as id/author/body/at", %{ws: ws, root: root} do
    {:ok, a} = Server.Channel.post(%{thread_id: root.id, author: "uqbar", body: "cut 650fa4a", kind: "margin"})
    {:ok, b} = Server.Channel.post(%{thread_id: root.id, author: "uqbar", body: "#174 back to build", kind: "margin"})

    assert [%{id: bid, author: "uqbar", body: "#174 back to build", at: at}, %{id: aid}] = Margin.notes(ws.id)
    assert {bid, aid} == {b.id, a.id}
    assert is_integer(at)
  end

  test "only margin kind, only the root thread, capped", %{ws: ws, root: root, other: other} do
    {:ok, _} = Server.Channel.post(%{thread_id: root.id, author: "tlon", body: "chat", kind: "chat"})
    {:ok, _} = Server.Channel.post(%{thread_id: other.id, author: "uqbar", body: "elsewhere", kind: "margin"})
    for i <- 1..15, do: Server.Channel.post(%{thread_id: root.id, author: "uqbar", body: "n#{i}", kind: "margin"})

    notes = Margin.notes(ws.id)
    assert length(notes) == 12
    assert hd(notes).body == "n15"
    refute Enum.any?(notes, &(&1.body in ["chat", "elsewhere"]))
  end

  test "a workspace with no root thread has no margins" do
    assert Margin.notes(-1) == []
  end
end
```

Code:

```elixir
defmodule Server.Office.Margin do
  @moduledoc """
  Uqbar's margin notes (docs/plans/2026-10-08-uqbar-design.md §4): the `margin`-kind messages on a
  workspace's root thread, which the office draws in the room's margins. Read-only: they are
  written by the `margin_note` tool and wake nobody.
  """
  import Ecto.Query

  alias Server.{Channel, Message, Repo}

  @keep 12

  @doc "The workspace's margin notes, newest first: `[%{id, author, body, at}]` (`at` unix seconds)."
  @spec notes(integer()) :: [map()]
  def notes(workspace_id) do
    case Channel.machine_thread(workspace_id) do
      nil ->
        []

      %{id: root_id} ->
        from(m in Message, where: m.thread_id == ^root_id and m.kind == "margin", order_by: [desc: m.id], limit: @keep)
        |> Repo.all()
        |> Enum.map(&%{id: &1.id, author: &1.author, body: &1.body, at: DateTime.to_unix(&1.created_at)})
    end
  end
end
```

Route (next to the `suggestions` route, `operator_api.ex:230`):

```elixir
defp route(conn, "GET", "office", ["margin", ws]) do
  case Integer.parse(ws) do
    {id, ""} -> json(conn, 200, Server.Office.Margin.notes(id))
    _ -> json(conn, 404, %{error: "no workspace #{ws}"})
  end
end
```

Plus the doc line `GET /api/office/margin/:ws  Office.Margin.notes (Uqbar's margin notes)`.
Add an operator_api test beside the suggestions route test (grep `office/suggestions` in `server/test`).

Done when: `cd server && mix test test/server/office/margin_test.exs test/server/mcp` green and
`mise run server:check` compiles with `--warnings-as-errors` (boundary: Margin is a plain Office module like Corkboard).

## S4 — the write path: MCP tool `margin_note`

Files: `server/lib/server/mcp/tools/margin.ex` (new), `server/lib/server/mcp/endpoint.ex:27`
(register), `server/lib/server/profiles.ex:~340` (the tool-name allow lists — add `margin_note` where
`post_message` is listed *only for the profile Uqbar's session uses*; grep how `uqbar` is launched,
`TLON_AUTHOR=uqbar`), `server/test/server/mcp/margin_note_test.exs` (new, model on `gateway_test.exs`).

Test first: calling `margin_note` with `text: "#174 back to build"` as agent `uqbar` bound to thread T (workspace W)
creates one `margin` message on W's root thread authored `uqbar`; a blank/over-140-char text is refused with
no row; no root thread → error reply. (Copy the frame/identity setup from the `post_message` test.)

Code:

```elixir
defmodule Server.MCP.Tool.MarginNote do
  @moduledoc """
  Write one line in the room's margin (a `margin` note on this workspace's root thread). One short
  line per thing you did or noticed: `#174 back to build — the cake never drew`, `cut 650fa4a`.
  Name a thread as `#N` and the office lights that card when the note is hovered. It wakes nobody.
  """
  use Server.MCP.Tool

  alias Server.{Channel, Repo, Thread}

  @max 140

  schema do
    field :text, :string, required: true, description: "One line, ≤ 140 chars"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    text = String.trim(params[:text] || "")

    with :ok <- check(text),
         %Thread{workspace_id: ws} <- Repo.get(Thread, identity.thread_id),
         %Thread{id: root} <- Channel.machine_thread(ws) do
      result = Channel.post(%{thread_id: root, author: identity.agent, body: text, kind: "margin"})
      reply(frame, result, fn m -> %{"note_id" => m.id} end)
    else
      {:error, why} -> reply(frame, {:error, why}, & &1)
      _ -> reply(frame, {:error, "no root thread to write the margin on"}, & &1)
    end
  end

  defp check(""), do: {:error, "a margin note needs text"}
  defp check(t) when byte_size(t) > @max * 4, do: {:error, "one line, ≤ #{@max} chars"}
  defp check(t), do: if(String.length(t) > @max, do: {:error, "one line, ≤ #{@max} chars"}, else: :ok)
end
```

(`Identity`/`reply` are aliased the way `Server.MCP.Tool.PostMessage` in `tools/thread.ex` gets them —
copy that module's header; adapt `reply/3`'s error shape to what that file does with `{:error, _}`.)
Register: `component(Server.MCP.Tool.MarginNote, name: "margin_note")` after `post_message`.
If the repo has a tool manual/golden listing tool names (the `check` gate includes "the task manual"),
regenerate it the way its failure message says.

Done when: `mix test test/server/mcp/margin_note_test.exs` green and `mise run server:check` green.
Not in scope: a `tlon-cli` verb; Uqbar's session instructions to *use* the tool (docs follow-up, own commit).

---

## O1 — terminal focus events

Files: `office/tui/term.ts`, `office/test/term.test.ts` (append).

Test first (red: `ESC[I` tokenizes to `{t:"key", key:"esc[I"}`):

```ts
test("focus reports are their own input, not keys", () => {
  expect(tokenize("\x1b[I").inputs).toEqual([{ t: "focus", on: true }])
  expect(tokenize("\x1b[O").inputs).toEqual([{ t: "focus", on: false }])
  expect(tokenize("a\x1b[Ib").inputs.map((i) => i.t)).toEqual(["key", "focus", "key"])
})
test("enter turns focus reporting on and leave turns it off", () => {
  // read the strings the way term-mute.test.ts captures `out`; assert ?1004h in enter, ?1004l in leave
})
```
(Write the second test the way `office/test/term-mute.test.ts` captures stdout.)

Code (`term.ts`): add `| { t: "focus"; on: boolean }` to `Input`; in `enter()` the mode string gains
`${ESC}[?1004h` (before `[2J`); `leave()` gains `${ESC}[?1004l` next to `[?2004l`; in `tokenize` add, **before**
the generic `\x1b(\[[\d;]*[~A-Zu]…)` branch:

```ts
else if ((m = s.match(/^\x1b\[([IO])/))) inputs.push({ t: "focus", on: m[1] === "I" })
```
(`m[0].length` is already used for `len`.)

Done when: `mise run office:test` green for `term.test.ts` and `term-mute.test.ts`. Note `[?1004h` replies
arrive as `\x1b[I`/`\x1b[O` only; no existing reply starts with `ESC[I`/`ESC[O`.

## O2 — the pure core: `kit/margin.ts` (refs, fade, looks, lines)

Files: `office/kit/margin.ts` (new), `office/test/margin.test.ts` (new).

Test first:

```ts
import { describe, expect, test } from "bun:test"
import { contrast, ROLE } from "../kit/palette"
import { FADE_S, FLOOR, HOLD_S, Looks, inkAlpha, linesOf, refsOf, tintInk, type Note } from "../kit/margin"
import { MIN_CONTRAST } from "../tui/paint"

const note = (id: number, at: number, body = `n${id}`): Note => ({ id, author: "uqbar", body, at })

describe("refs", () => {
  test("#N names a thread, once each, in order", () => {
    expect(refsOf("#174 back to build — see #188 and #174")).toEqual([174, 188])
    expect(refsOf("cut 650fa4a")).toEqual([])
  })
})
describe("fade", () => {
  test("full ink through the hold, linear to the floor, flat after", () => {
    expect(inkAlpha(0)).toBe(1)
    expect(inkAlpha(HOLD_S)).toBe(1)
    expect(inkAlpha(HOLD_S + FADE_S / 2)).toBeCloseTo((1 + FLOOR) / 2)
    expect(inkAlpha(HOLD_S + FADE_S)).toBe(FLOOR)
    expect(inkAlpha(1e9)).toBe(FLOOR)
  })
  test("the floor is still legible on the ground", () => {
    const c = (a: number) => tintInk(a)
    expect(contrast(c(FLOOR), ROLE.ground)).toBeGreaterThanOrEqual(MIN_CONTRAST)
  })
})
describe("since you last looked", () => {
  test("a note that arrives while unfocused stays full ink, however long the wait", () => {
    const l = new Looks(0 /* lookedAt */)
    l.see([note(1, 100)], false)      // unfocused frame
    l.tick(0)
    expect(l.alpha(note(1, 100))).toBe(1)
  })
  test("focus starts the fade; it fades by focused time only", () => {
    const l = new Looks(0)
    l.see([note(1, 100)], false)
    l.focus(true)
    l.see([note(1, 100)], true)       // looked: seen at focusedS = 0
    l.tick(HOLD_S + FADE_S)           // that much focused time passes
    expect(l.alpha(note(1, 100))).toBe(FLOOR)
    l.focus(false)
    l.tick(0)                         // unfocused time is not fed to tick; clock must not move
    expect(l.focusedS).toBe(HOLD_S + FADE_S)
  })
  test("a note older than the last-looked stamp is already seen, aged by the wall gap", () => {
    const l = new Looks(10_000)
    l.see([note(1, 10_000 - (HOLD_S + FADE_S) - 5), note(2, 10_500)], false)
    expect(l.alpha(note(1, 0))).toBe(FLOOR)
    expect(l.alpha(note(2, 10_500))).toBe(1)   // newer than lookedAt: unseen, full ink
  })
})
describe("lines", () => {
  test("newest first, at most 5, each cut to 44 chars, lit when hovered thread is named", () => {
    const notes = Array.from({ length: 8 }, (_, i) => note(i + 1, 1000 + i, `#${100 + i} ${"x".repeat(60)}`))
    const l = new Looks(0)
    const got = linesOf(notes, l, 107)
    expect(got.length).toBe(5)
    expect(got[0]!.id).toBe(8)
    expect(got.every((x) => [...x.text].length <= 44)).toBe(true)
    expect(got[0]!.lit).toBe(true)         // names #107
    expect(got[1]!.lit).toBe(false)
    expect(got[0]!.tid).toBe(107)          // first ref: what a click/enter opens
  })
})
```
(`tintInk` is the exported colour function below; import it.)

Code:

```ts
// Uqbar's margin notes (docs/plans/2026-10-08-uqbar-design.md §4): one-line notes written on the
// workspace's root thread, drawn in the room's margin, newest nearest the room. Pure: callers pass
// the focused clock, so a golden or test is deterministic. See docs/plans: "since you last looked".
import { ROLE, tint } from "./palette"

export type Note = { id: number; author: string; body: string; at: number }
export const HOLD_S = 60, FADE_S = 1200, FLOOR = 0.45
export const KEEP = 5, WIDTH = 44

/** the threads a note names (`#174`), once each, in order */
export function refsOf(body: string): number[] {
  const seen = new Set<number>()
  for (const m of body.matchAll(/#(\d+)/g)) seen.add(Number(m[1]))
  return [...seen]
}
/** ink strength for a note seen `age` focused seconds ago: full through the hold, then down to the floor */
export const inkAlpha = (age: number) =>
  age <= HOLD_S ? 1 : age >= HOLD_S + FADE_S ? FLOOR : 1 - ((age - HOLD_S) / FADE_S) * (1 - FLOOR)
export const tintInk = (alpha: number) => tint(ROLE.body, ROLE.ground, alpha)

/** what the operator has looked at: a clock of focused seconds and when each note was first seen on it */
export class Looks {
  focusedS = 0
  private focused = false
  private readonly seenAt = new Map<number, number>()
  /** `lookedAt`: the persisted epoch second of the last focused moment (0 on a first run) */
  constructor(public lookedAt: number) {}
  focus(on: boolean) { this.focused = on }
  /** advance the focused clock by `dt` seconds; unfocused time never counts */
  tick(dt: number) { if (this.focused) this.focusedS += dt }
  /** a frame drew these notes: while focused they are looked at; a note older than the last look is already seen */
  see(notes: Note[], focused: boolean) {
    this.focused = focused
    for (const n of notes) {
      if (this.seenAt.has(n.id)) continue
      if (focused) this.seenAt.set(n.id, this.focusedS)
      else if (n.at <= this.lookedAt) this.seenAt.set(n.id, this.focusedS - (this.lookedAt - n.at))
    }
  }
  alpha(n: Note): number {
    const s = this.seenAt.get(n.id)
    return s === undefined ? 1 : inkAlpha(this.focusedS - s)
  }
}

export type Line = { id: number; text: string; color: string; tid: number | null; lit: boolean }
/** the margin as lines: newest first, ≤ KEEP, cut to WIDTH; `lit` when it names the hovered thread `over` */
export function linesOf(notes: Note[], looks: Looks, over: number | null): Line[] {
  return [...notes].sort((a, b) => b.id - a.id).slice(0, KEEP).map((n) => {
    const refs = refsOf(n.body), t = [...n.body]
    const lit = over !== null && refs.includes(over)
    return {
      id: n.id, tid: refs[0] ?? null, lit,
      text: t.length > WIDTH ? `${t.slice(0, WIDTH - 1).join("")}…` : n.body,
      color: lit ? ROLE.key : tintInk(looks.alpha(n)),
    }
  })
}
```

Done when: `bun test office/test/margin.test.ts` green (via `mise run office:test`), plus `mise run office:check`
typecheck passes. (Check `MIN_CONTRAST` import is exported from `tui/paint`; it is — `wcag.test.ts` imports it.)

## O3 — fetch, persist and feed the clock

Files: `office/tui/data.ts`, `office/tui/main.ts`, `office/test/data.test.ts` (append).

Test first (`data.test.ts`, same style as the `suggestions` case there): with `fetch` faked to return
`[{id:1,author:"uqbar",body:"cut 650fa4a",at:5}]` for `/api/office/margin/1`, `data.margin(1)` returns it;
a 500 and a throw each return `[]`.

Code:

```ts
// data.ts — next to suggestions()
/** Uqbar's margin notes in a workspace, newest first (empty when there are none or the server is down) */
export async function margin(ws: number): Promise<Note[]> {
  try { const r = await call("GET", `/office/margin/${ws}`); return r.status === 200 ? r.json : [] } catch { return [] }
}
```
(`import type { Note } from "../kit/margin"`.) Under `--sandbox` `call` answers 404 for it → `[]`; fine.

`main.ts` wiring (state next to `ideas`, line ~159; follow how `TRAY`/`trayRead` is read and written):

```ts
const LOOKED = join(STATE_DIR, "margin-looked")      // same dir TRAY lives in
let notes: Note[] = []
const looks = new Looks(Number(readState(LOOKED)) || 0)
let focused = true, lit: number | null = null, lastStamp = 0
```
- In `refresh()` beside `loadFeed()`: `notes = ws === null ? [] : await data.margin(ws)`.
- On `{t:"focus"}` input: `focused = e.on; looks.focus(e.on); if (!e.on) stamp(); changed(); draw()`.
- `every(() => { looks.tick(1); if (focused && ++n % 5 === 0) stamp(); roomChanged… }, 1000)` where
  `stamp = () => { looks.lookedAt = Math.floor(Date.now()/1000); writeState(LOOKED, String(looks.lookedAt)) }`.
- Begin focused (`focused = true`): terminals that never send focus events (no 1004 support) then behave
  as always-focused: notes start fading from first sight. That is the graceful degradation, stated.

Done when: `bun test office/test/data.test.ts` green; manually `mise run office:sandbox` still draws.
(The focus/tick wiring is verified in O4's drive.)

## O4 — draw the margin, light the card, open on enter

Files: `office/tui/main.ts` (`draw()` ~1405, `onMouse` ~1722, `onKey` ~1668),
`office/test/margin.test.ts` (append a hit-geometry test of the pure helper below),
`office/kit/margin.ts` (append `marginInk`).

Test first (append to `margin.test.ts`):

```ts
import { marginInk } from "../kit/margin"
test("marginInk: text ink anchored bottom-left of the viewport, with one hit per linked note", () => {
  const notes = [note(2, 20, "#188 closed"), note(1, 10, "cut 650fa4a")]
  const { ink, hits } = marginInk(notes, new Looks(0), null, { x: 50, y: 10, w: 300, h: 100 })
  expect(ink.map((i) => (i.t === "text" ? i.s : ""))).toEqual(["#188 closed", "cut 650fa4a"])
  expect(ink[0]).toMatchObject({ x: 52, align: "left" })
  expect(ink[0]!.t === "text" && ink[0]!.y).toBeLessThan(ink[1]!.t === "text" ? ink[1]!.y : 0) // newest on top
  expect(hits).toHaveLength(1)                                   // the cut note names no thread
  expect(hits[0]!.act).toEqual({ kind: "thread", tid: 188 })
})
```

Code (`kit/margin.ts`, append; check `Ink`/`Hit` types in `kit/canvas.ts`/`kit/draw.ts` and match their fields):

```ts
import type { Hit, Ink } from "./canvas"
export const LINE_H = 9, SIZE = 9
/** the margin as ink + hits in room pixels, pinned to the viewport's bottom-left (so a pan can't lose it) */
export function marginInk(notes: Note[], looks: Looks, over: number | null, vp: { x: number; y: number; w: number; h: number }): { ink: Ink[]; hits: Hit[] } {
  const ls = linesOf(notes, looks, over), ink: Ink[] = [], hits: Hit[] = []
  const y0 = vp.y + vp.h - 4 - ls.length * LINE_H
  ls.forEach((l, i) => {
    const x = vp.x + 2, y = y0 + i * LINE_H
    ink.push({ t: "text", s: l.text, x, y, color: l.color, size: SIZE, align: "left" })
    if (l.tid !== null) hits.push({ x, y: y - 2, w: Math.min(vp.w - 4, l.text.length * 4), h: LINE_H, tip: `${l.text} — enter opens #${l.tid}`, act: { kind: "thread", tid: l.tid }, note: l.tid } as Hit)
  })
  return { ink, hits }
}
```
(`note: l.tid` lets `onMouse` tell a margin hit from a card hit — add an optional `note?: number` to `Hit`
in `kit/canvas.ts` if it isn't open-ended. Width: measure with `measureFor(g)` if a more accurate width is
wanted; 4 px/char is the SMALL font's advance at scale 1 — verify against `font.ts`.)

`main.ts`:
- `draw()`, after `const seen = clipFrame(frame!, vp)`: 
  `looks.see(notes, focused); const m = marginInk(notes, looks, lit, vp); seen.ink.push(...m.ink); seen.hits.push(...m.hits)`
  — and pass `picked: lit ?? picked` in the `render` call so the hovered note's card lights (`roomChanged = true` when `lit` changes).
- `onMouse` motion branch (`main.ts:1722`): after finding hit `h`, `const next = (h as Hit & {note?: number})?.note ?? null; if (next !== lit) { lit = next; roomChanged = true }` (before the existing tip logic; keep it one assignment).
- `onKey` home-mode `enter`: `if (mode.kind === "home" && lit !== null) return act({ kind: "thread", tid: lit })`
  placed before the existing `case "enter"` fallthrough (`main.ts:1668`). A click already works through the hit's `act`.

Done when — verified end to end with the `drive-office` skill, not just tests:
1. `mise run office:test` and `mise run office:check` green at frozen 03:00 and 15:00; `golden.json` unchanged (`git diff --stat` shows no `golden.json`).
2. Drive: start the office on a scratch server with 3 margin notes (two naming `#N` of real cards);
   unfocused (send `ESC[O`) → add a note via `margin_note` → send `ESC[I`: that note is full amber, older
   ones are dimmer; advance focused time (`tick` is 1 s: wait/stub) → it fades to the floor, still legible.
3. Hover a `#N` note: that card shows picked; `enter` opens its thread reader; `esc` returns.

## Open items / risks (named, not "known")

- **No keyboard note cursor.** Hover (mouse) + `enter`, or click. A key-only path (`[`/`]` to walk notes) is a
  small follow-up if Andrew wants it; step 5's footnote keys are the keyboard story.
- **Terminals without DEC 1004** never send focus events → notes fade from first sight (documented
  degradation, not an error). Under tmux, `focus-events on` must be set for events to pass through.
- **Margins are per workspace** (root thread of the workspace shown); Uqbar writes to its own session's
  workspace. A note about another workspace's thread appears there, and `enter` goes through
  `goThread`-style switching only if built — here `act({kind:"thread"})` opens within the current
  workspace; cross-workspace `#N` should use `goThread(id, wsId)` once the note carries a `workspace_id`
  (not carried today — one-line server addition if it matters).
- **Restart aging uses wall time** for notes older than `lookedAt` (upper bound on focused age): they may
  fade slightly sooner than strict focused-time. Acceptable; stated.
- **Uqbar's session instructions** must tell it to call `margin_note`: a docs/brief change owned by the
  operator's side, outside both worklines.
