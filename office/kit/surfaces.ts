// Who acts on what waits (`Server.Office.Needs.surface/1`): the phone rings for an answer owed, the
// answering machine blinks for information, the sheriff's clipboard holds what the crew owns.
import type { Scene } from "./draw"
import { ROLE, tint } from "./palette"

/** the top bar's one count: only an answer owed reaches it */
export function phoneBar(counts: { phone: number }): { text: string; ringing: boolean } | null {
  return counts.phone > 0 ? { text: `${counts.phone} waiting on you`, ringing: true } : null
}

/** the phone's glyph at a tick: it shakes while ringing, so the ring never rests on colour alone */
export const ringFrame = (tick: number, ringing: boolean) => (ringing && tick % 2 === 1 ? "☏" : "☎")

/** the answering machine at its foot (x, y): its light blinks while it holds messages nobody has heard */
export function drawMachine(sc: Scene, x: number, y: number, n: number) {
  const px = sc.px.bind(sc), on = n > 0 && sc.f % 4 < 2
  sc.item(y, () => {
    px(x, y - 5, 10, 5, ROLE.inactive); px(x, y - 5, 10, 1, ROLE.borderInactive)
    px(x + 2, y - 4, 4, 2, ROLE.edge) // the tape
    px(x + 7, y - 4, 2, 2, on ? ROLE.attention : n > 0 ? tint(ROLE.attention, ROLE.ground, 0.6) : ROLE.raised)
  })
  if (n) sc.overhead.push(() => sc.text(`${n} new`, x + 5, y - 8, ROLE.attention, 9))
  sc.hits.push({ x: x - 1, y: y - 10, w: 12, h: 11, tip: n ? `the answering machine: ${n} new messages` : "the answering machine: nothing new", act: { kind: "machine" } })
}

export type ClipRow = { owner?: string | null; tracking?: string | null; title: string; recommendation?: string | null }

/** the sheriff's clipboard by the door: a sheet line for each thing the crew owns (four at most); `z` its depth, a wall's when it hangs on one */
export function drawClipboard(sc: Scene, x: number, y: number, rows: ClipRow[], z = y + 12) {
  const px = sc.px.bind(sc)
  sc.item(z, () => {
    px(x, y, 9, 12, ROLE.structure)
    px(x + 1, y + 1, 7, 10, ROLE.prose)
    px(x + 3, y - 1, 3, 2, ROLE.inactive) // the clip
    for (let i = 0; i < Math.min(4, rows.length); i++) px(x + 2, y + 3 + i * 2, 5, 1, ROLE.inactive)
  })
  if (rows.length) sc.overhead.push(() => sc.text(`${rows.length}`, x + 4, y - 4, ROLE.body, 9))
  const lines = rows.map((r) => `${clipLabel(r)} · ${r.title}${r.recommendation ? ` (tip: ${r.recommendation})` : ""}`)
  const tip = rows.length ? `the sheriff's clipboard: ${rows.length} on the clipboard, the crew's to fix — ${lines.join("; ")}` : "the sheriff's clipboard: nothing on it"
  sc.hits.push({ x: x - 3, y: y - 8, w: 15, h: 20, tip, act: { kind: "clipboard" } })
}

const SECTION = {
  phone: { label: "PHONE", note: "an answer is owed: work waits on you" },
  machine: { label: "MACHINE", note: "for your information: heard once you play the machine" },
  clipboard: { label: "CLIPBOARD", note: "the crew owns these: nothing for you to do" },
  settled: { label: "SETTLED BY UQBAR", note: "today's digest: u overrules one, back to Uqbar" },
  uqbar: { label: "WITH UQBAR", note: "Uqbar decides whether these need you" },
} as const

/** the inbox's sections in the order who acts: phone, machine (with Uqbar's settled digest), clipboard, then what waits with Uqbar — the empty ones left out */
export function inboxSections<T>(g: Record<"phone" | "machine" | "clipboard", T[]> & { settled?: T[]; uqbar?: T[] }) {
  return (["phone", "machine", "settled", "clipboard", "uqbar"] as const)
    .map((s) => ({ s, items: g[s] ?? [] }))
    .filter(({ items }) => items.length)
    .map(({ s, items }) => ({ surface: s, label: `${SECTION[s].label} · ${items.length}`, note: SECTION[s].note, items }))
}

/** a clipboard row's who and what: its owner and what tracks it, or that nobody does */
export const clipLabel = (r: { owner?: string | null; tracking?: string | null }) => `${r.owner ?? "nobody"} · ${r.tracking ?? "untracked"}`
