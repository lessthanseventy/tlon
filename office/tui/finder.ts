// The finder's rows that are tickets: what a row shows, what it is matched on, and what Enter does.
import type { Ticket } from "../kit/types"
import { ROLE } from "../kit/palette"
import type { Seg } from "./term"

/** one row of the finder: what it shows, what it is matched on, what picking it does */
export type Pick = { segs: Seg[]; text: string; run: () => void }

/** every ticket as a finder row; `wsName` names its workspace, `open` opens its card */
export function ticketPicks(tickets: Ticket[], wsName: (id: number) => string, open: (id: number) => void): Pick[] {
  return tickets.map((t) => {
    const where = wsName(t.workspace_id)
    // labelled, as the finder's workspace and coworker rows are: ticket #15 is not thread #15
    return { segs: [{ s: "ticket ", fg: ROLE.inactive }, { s: `#${t.id} `, fg: ROLE.key }, { s: t.title, fg: ROLE.prose }, { s: `  ${where}`, fg: ROLE.inactive }], text: `ticket #${t.id} ${t.title} ${where}`, run: () => open(t.id) }
  })
}
