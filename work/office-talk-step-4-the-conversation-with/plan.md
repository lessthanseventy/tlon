# Plan — office talk step 4: the conversation with X (`v`), and the room stops saying "lobby"

Spec: `docs/plans/2026-10-08-office-talk-design.md` §2 (conversation = a filter, no DM schema), §4
(naming), §5 step 4. Office-only (`office/`, TypeScript, bun). Step 3 (`replies`, `reply_to` on
`thread_view`) is on main (7aaa4aa, 367943f) — verified in `git log main`.

Verify everything with: `cd office && bun test && bun run typecheck` (the gate is `mise run office:check`,
run unsandboxed with OFFICE_TEST_HOUR=3 and =15 — fact #899).

## Decisions (the design leaves these open; say so on the thread if wrong)

1. **`v` on a person's card is the conversation, not their work thread.** Today `v` there reads their
   current thread (`threadActions`). The ticket says `v` on a card opens the conversation, so on the
   person card `v` = "the conversation" and their work thread moves to `w` ("read #N"). Thread cards keep `v`.
2. **A conversation reader's composer sends `@X …` to the lobby**, so a reply in it is the same post as `m`.
3. **Filter sees the loaded pages only** (same limit step 3 documented): a reply to an operator post
   that scrolled out is missed until older pages load; the filter runs at render so paging still works.
4. **#general**: the office never shows channels today (nothing in `office/` reads them), so "only once a
   second channel exists" is already true — no task, nothing built (YAGNI).
5. **Out of scope, flagged**: §3's `... (v)` balloon tail has no producer (step 1 cut with `…` only).
   Needs a "last speaker" notion; file as its own ticket if wanted.

## Task 1 — the filter (pure) · `office/tui/talk.ts`, `office/test/talk.test.ts`

Test first, append to `talk.test.ts` (import `conversation` too):

```ts
describe("conversation", () => {
  const m = (id: number, author: string, body: string, reply_to: number | null = null) => ({ id, author, body, at: "", kind: "chat", reply_to })
  test("keeps X's posts and the operator's posts mentioning or replying to X, nothing else", () => {
    const msgs = [
      m(1, "andrew", "@ada how goes it"),        // keep: mentions ada
      m(2, "ada", "fine"),                       // keep: ada's
      m(3, "bo", "unrelated"),                   // drop: someone else's
      m(4, "andrew", "@bo you there"),           // drop: mentions bo only
      m(5, "andrew", "thanks", 2),               // keep: replies to ada's post
      m(6, "andrew", "ok", 3),                   // drop: replies to bo's post
      m(7, "tlon", "ada was staffed", 2),        // drop: system
      m(8, "andrew", "@adam hi"),                // drop: @adam is not @ada
      m(9, "andrew", "we need a thing"),         // drop: to the office
    ]
    expect(conversation(msgs, "ada", "andrew").map((x) => x.id)).toEqual([1, 2, 5])
  })
})
```

Run `cd office && bun test test/talk.test.ts` → red (no export). Then add to `talk.ts`:

```ts
/** the lobby's posts that are a conversation with `x`: theirs, and the operator's that mention or answer them. A filter, no DM schema. */
export function conversation<M extends { id: number; author: string; body: string; reply_to?: number | null }>(msgs: M[], x: string, operator: string): M[] {
  const theirs = new Set(msgs.filter((m) => m.author === x).map((m) => m.id))
  const named = new RegExp(`@${x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![\\w-])`)
  return msgs.filter((m) => m.author === x || (m.author === operator && (named.test(m.body) || (m.reply_to != null && theirs.has(m.reply_to)))))
}
```

Done: test green. Commit: `office talk: the conversation with X is a filter over the lobby`.

## Task 2 — the reader can show a filtered, retitled thread · `office/tui/reader.ts`, `office/test/reader.test.ts` (new)

Test first (new file; same shape as `dogear.test.ts`):

```ts
import { expect, test } from "bun:test"
import { Reader } from "../tui/reader"

const msg = (id: number, author: string) => ({ id, author, body: `post ${id}`, at: "2026-10-12T10:00:00.000000Z", kind: "chat" })
const page = { messages: [msg(1, "ada"), msg(2, "bo"), msg(3, "ada")], peek: null, window: null }

test("keep filters what is shown, heading replaces the thread's title", () => {
  const r = new Reader(7, { load: async () => null, send: async () => "", operator: "andrew", redraw() {}, keep: (ms) => ms.filter((m) => m.author === "ada"), heading: "conversation with ada" }, false)
  r.take(page)
  const s = r.draw(60, 20, { id: 7, title: "lobby", stage: null, awaiting: null }, "")
  expect(s).toContain("post 1"); expect(s).toContain("post 3"); expect(s).not.toContain("post 2")
  expect(s).toContain("conversation with ada"); expect(s).not.toContain("lobby")
})
```

Red, then in `reader.ts`:
- `ReaderDeps` gains `keep?: (msgs: Msg[]) => Msg[]` (what to show of the pages read) and `heading?: string` (instead of the thread's title).
- In `body()`: `const shown = this.deps.keep ? this.deps.keep(this.msgs) : this.msgs` and loop `for (const m of shown)`; the "no messages yet" test uses `shown.length`.
- In `draw()`: `{ s: \` ${this.deps.heading ?? th?.title ?? ""}\`, … }`.

Done: reader test green, `dogear.test.ts` still green. Commit: `reader: show a filtered view under its own heading`.

## Task 3 — `v` on a person opens the conversation · `office/tui/main.ts`

No unit seam in `main.ts` (it is the TUI loop); the logic is Tasks 1–2, this is wiring. Add beside `openReader`:

```ts
/** the conversation with `name`: the lobby, filtered to them and the operator's words to them; replies go to them */
function openConversation(name: string) {
  const lobby = lobbyOf(view().threads, ws)
  if (lobby === null) { status = "no front desk in this workspace"; return draw() }
  openReader(lobby, false, {
    keep: (ms) => conversation(ms, name, OPERATOR),
    heading: `conversation with ${name}`,
    send: (body) => data.post(lobby, speech(name, body) ?? body),
  })
}
```

Change `openReader(tid, compose)` to `openReader(tid, compose, extra: Partial<ReaderDeps> = {})` and spread `...extra` last in the deps object. Import `conversation`, `speech` from `./talk`, `ReaderDeps` from `./reader`.

Person card (`case "person"`, main.ts ~972): actions become
`[{ key: "m", label: "talk", … }, { key: "v", label: "the conversation", run: () => openConversation(name) }, ...(c.thread === null ? [] : [{ key: "w", label: `read #${c.thread}`, run: () => openReader(c.thread!, false) }, ...liveActions(c.thread), ...threadActions(c.thread).filter((x) => x.key !== "v")]), …]`
(the filter drops the thread's own `v` so the key is not bound twice). Also bind the same `v` for the crew-roster
card if one exists at ~931 — it opens `person`, so nothing more is needed.

Done: `bun run typecheck` clean; drive-office (skill `drive-office`): open a person with a work thread, press `v` →
screen shows `conversation with <name>` and only their lobby posts; press `r`, type, enter → a post `@<name> …`
lands on the lobby. Commit: `office: v on a person is the conversation with them`.

## Task 4 — the room stops saying "lobby" · `office/tui/data.ts`, `office/test/data.test.ts`

Test first, in `data.test.ts`: extend the stand-in `/office` answer with
`threads: [{ id: 2, title: "lobby", standing: true, workspace_id: 1 }, { id: 3, title: "lobby notes", standing: false, workspace_id: 1 }]`
(only if it does not disturb the existing `status` test — otherwise add a second route) and assert:

```ts
expect(all.threads.find((t) => t.id === 2)?.title).toBe("the front desk")
expect(all.threads.find((t) => t.id === 3)?.title).toBe("lobby notes")
```

Red, then in `data.status()` map `threads`: `(j.threads ?? []).map((t: Thread) => t.standing && t.title === "lobby" ? { ...t, title: "the front desk" } : t)`
(one place; every list, finder pick, card and reader head reads `Agents.threads`). Also change talk.ts's status
`"no lobby in this workspace to say it on"` → `"no front desk in this workspace to say it on"` and update its
`/no lobby/` assertion in `talk.test.ts` to `/no front desk/`.

Done: `bun test` green; `grep -rn '"lobby"\|lobby' office/tui office/kit --include=*.ts` shows only code comments and the
one literal in `data.ts`. Commit: `office: the standing thread is the front desk, not "lobby"`.

## Finish

`mise run office:check` green (unsandboxed; OFFICE_TEST_HOUR=3 and 15). Four commits, each independently green.
Review points: Task 3's `v`→`w` move on the person card (decision 1).
