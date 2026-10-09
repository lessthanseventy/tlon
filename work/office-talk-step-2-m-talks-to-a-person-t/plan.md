# Plan — office talk step 2: `m` talks to a person, `'` talks to the office

Design: `docs/plans/2026-10-08-office-talk-design.md` §2, §5 step 2. Step 1 (balloons) is on main.
Nothing of step 2 is on main (no `talk.ts`, no `'` key; `m` on a person card is "model…").

## Assumptions (say if wrong)
- **Composer = the existing multi-line `ask()` pane** (`office/tui/main.ts` `ask`/`inputKey`: enter sends,
  alt/shift-enter newline, esc drops), labelled "say to X" / "say to the office". The design's
  "speech box over the speaker" drawn *in the room* is not built: the operator has no sprite to anchor to,
  and replies-as-balloons is step 3. The pane composer is what drive-office will show. Flagged, not silent.
- **Lobby** = the open thread with `standing === true` in the current workspace (`Thread.standing`,
  `kit/types.ts`). No server change: `POST /api/threads/:id/messages` (`data.post`) already delivers,
  and a body starting `@name` wakes that coworker in their home window.
- `m` conflicts with the person card's "model…" action (`seatActions`, `main.ts` ~527; own actions win over
  globals). Model moves to `M`.

## Task 1 — pure talk logic (TDD)
Files: new `office/tui/talk.ts`, new `office/test/talk.test.ts`.

Test first (`talk.test.ts`):
```ts
import { describe, expect, test } from "bun:test"
import { lobbyOf, speech, say } from "../tui/talk"
const th = (id: number, ws: number, standing: boolean) => ({ id, title: "lobby", stage: null, awaiting: null, workspace_id: ws, standing })
describe("talk", () => {
  test("the lobby is the workspace's standing thread", () => {
    const ts = [th(1, 1, false), th(2, 1, true), th(3, 2, true)]
    expect(lobbyOf(ts, 1)).toBe(2)
    expect(lobbyOf(ts, 9)).toBeNull()
  })
  test("a person's words are addressed; the office's are not", () => {
    expect(speech("nolan", "  hi there ")).toBe("@nolan hi there")
    expect(speech(null, " a want ")).toBe("a want")
    expect(speech("nolan", "   ")).toBeNull()
  })
  test("say posts to the lobby over the operator API (benched coworker included)", async () => {
    const got: { path: string; body: unknown }[] = []
    const srv = Bun.serve({ port: 0, async fetch(r) { got.push({ path: new URL(r.url).pathname, body: await r.json() }); return Response.json({}) } })
    process.env.TLON_URL = `http://127.0.0.1:${srv.port}`
    await say([th(2, 1, true)], 1, "ada", "hello")      // ada is on the bench: no thread of her own
    await say([th(2, 1, true)], 1, null, "we need a thing")
    srv.stop()
    expect(got).toEqual([
      { path: "/api/threads/2/messages", body: { body: "@ada hello" } },
      { path: "/api/threads/2/messages", body: { body: "we need a thing" } },
    ])
  })
  test("no lobby, no post", async () => { expect(await say([], 1, null, "x")).toMatch(/no front desk|no lobby/) })
})
```
Run (red: module missing): `~/projects/menard/bin/menard`-less TS, so `cd office && bun test test/talk.test.ts`.

Code (`talk.ts`):
```ts
// Talking in the office: what `m` (to a person) and `'` (to the office) post, and where.
import * as data from "./data"
import type { Thread } from "../kit/types"

/** the workspace's lobby — its standing thread, where the manager hears the office and a home window lives */
export const lobbyOf = (threads: Thread[], ws: number | null): number | null =>
  threads.find((t) => t.standing && t.workspace_id === ws)?.id ?? null

/** the body to post: `@name …` to a person, the bare words to the office; null when nothing was said */
export function speech(to: string | null, text: string): string | null {
  const s = text.trim()
  return s ? (to ? `@${to} ${s}` : s) : null
}

/** say it on the workspace's lobby; the status line's text */
export async function say(threads: Thread[], ws: number | null, to: string | null, text: string): Promise<string> {
  const body = speech(to, text), lobby = lobbyOf(threads, ws)
  if (!body) return "nothing said"
  if (lobby === null) return "no lobby in this workspace to say it on"
  const r = await data.post(lobby, body)
  return r.startsWith("sent") ? (to ? `said to ${to}` : "said to the office") : r
}
```
Done: `cd office && bun test test/talk.test.ts` green. Commit: `office: talk.ts — what m and ' post, and where`.

## Task 2 — wire the keys
Files: `office/tui/main.ts` only.
1. `import { say } from "./talk"`.
2. Add near `newNote()`:
```ts
/** speak to a coworker (`to`) or, with null, to the office — the speech composer */
function talk(to: string | null) {
  if (ws === null) return
  const w = ws
  ask(to ? `say to ${to}` : "say to the office", (s) => { void did(say(view().threads, w, to, s)) }, { multiline: true })
}
```
3. `seatActions`: change the model action `key: "m"` → `key: "M"`.
4. `case "person"` actions: prepend `{ key: "m", label: "talk", run: () => talk(name) }` (before the seat/thread actions, so benched coworkers get it too).
5. `onKey` switch: `case "'": return talk(null)`; add `{ key: "'", label: "talk to the office" }` to `GLOBALS`.
Do not add to `look-editor` (its `m` mirror is handled before the switch — leave it).

Done: `mise run office:check` (typecheck + tests) green; no `grep -n 'key: "m"' office/tui/main.ts` besides the talk action.

## Task 3 — verify end to end + docs
- `/drive-office`: open a person card (a benched one too), press `m` → composer titled "say to NAME"; type, enter → status "said to NAME"; `'` anywhere → "say to the office". Check the post on the lobby (`get_messages` on the workspace's lobby thread). Attach the screen text to the thread.
- `office/AGENTS.md`: one line in the `tui/` description — `talk.ts`: `m`/`'` and where they post. Same commit as any code it describes (Task 2) — so do this edit in Task 2's commit.
- Gate: `mise run check` (run unsandboxed).
- Commit task 2: `office: m talks to a person, ' talks to the office; model moves to M`.

## Out of scope (later steps)
Balloon replies + inbox item (step 3); `v` conversation view, "front desk" naming (step 4).
