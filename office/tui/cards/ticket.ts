import { boardColumns, COLS, groupRows, openTotal, treeRows } from "../../kit/crew"
import { ROLE } from "../../kit/palette"
import { type Agents } from "../../kit/types"
import * as data from "../data"
import { bind } from "../keys"
import { wrap } from "../editor"
import { arrange, next } from "../order"
import { COL_SORTS, type Mode, type Row, type Action, type Card } from "../state"
import { boardCtx } from "../select"
import { cols, dim, key, pick, pink, plain, stateSeg } from "../ui"
import type { State } from "../state"
import type { Ctl } from "../ctl"

export function columnCard(app: State, ctl: Ctl, a: Agents, mode: Extract<Mode, { kind: "column" }>): Card {
  const col = boardColumns(a, boardCtx(app))[mode.col]!, items = arrange(col.items, app.colSort.cmp, null)[0]!.items
  // the TICKETS column is a tree: its rows are the open groups' children too, each level in the sort's order
  const titleOf = (x: { id: number }) => a.tickets.find((t) => t.id === x.id)?.title ?? ""
  const levelOrder = <T extends { id: number }>(xs: T[]): T[] => app.colSort.name === "title" ? [...xs].sort((p, q) => titleOf(p).localeCompare(titleOf(q))) : xs
  const tree = mode.col === 0 ? treeRows(a, app.expanded, levelOrder) : null
  const it = tree ? pick(tree, app.sel) : pick(items, app.sel), group = tree ? pick(tree, app.sel) : undefined
  const shown = tree ?? items
  const reorder = (dir: "up" | "down"): Action => ({ ...bind(dir === "up" ? "column.K" : "column.J", `move ${dir}`), run: () => { if (it?.act.kind === "ticket") { const was = JSON.stringify(it.act); void ctl.did(data.ticketReorder(it.act.id, dir)).then(() => { const at = ctl.detail().rows.findIndex((r) => r.ref === was); app.sel = at >= 0 ? at : Math.max(0, Math.min(app.sel + (dir === "up" ? -1 : 1), shown.length - 1)); ctl.draw() }) } } })
  return {
    // tickets carry no owner, so the tree has no who order to name
    title: `${col.name} · ${mode.col === 0 ? openTotal(a, items.length) : items.length}${app.colSort.name === "board" || (tree && app.colSort.name === "who") ? "" : ` · by ${app.colSort.name}`}`,
    rows: tree ? tree.map((x) => {
      const id = (x.act as { id: number }).id
      return {
        segs: [plain("  ".repeat(x.depth)), dim(x.group ? (x.open ? "▾ " : "▸ ") : "  "), ...(x.header ? [] : [key(`#${id} `)]), plain(x.title), ...(x.flight ? [dim(`  ⚙ on #${x.flight}`)] : [])],
        open: () => x.header ? undefined : x.flight ? ctl.act({ kind: "thread", tid: x.flight }) : x.group ? ctl.resort(() => { if (x.open) app.expanded.delete(id); else app.expanded.add(id) }) : ctl.open({ kind: "ticket", id, from: mode }),
        ref: JSON.stringify(x.act),
      }
    }) : items.map((x) => {
      const blocked = x.act.kind === "ticket" && (app.tickets.find((t) => t.id === (x.act as { id: number }).id)?.blocked_by.length ?? 0) > 0
      return {
        segs: [...(x.state ? [stateSeg(x.state)] : []), key(x.act.kind === "ticket" || x.act.kind === "epic" ? `#${x.act.id} ` : x.act.kind === "thread" ? `#${x.act.tid} ` : ""), plain(x.title), dim(`  ${x.stage}${x.who ? ` · ${x.who}` : ""}`),
          ...(x.state ? [{ s: `  ${x.state.why}`, fg: x.state.kind === "needs" ? ROLE.attention : ROLE.inactive }] : x.asks ? [pink("  waiting on you")] : []), ...(blocked ? [pink("  ⊘ blocked")] : [])],
        open: () => x.act.kind === "ticket" || x.act.kind === "epic" ? ctl.open({ ...x.act, from: mode }) : ctl.act(x.act), ref: JSON.stringify(x.act),
      }
    }),
    actions: [
      ...(mode.col === 0 ? [{ ...bind("column.n"), run: ctl.newTicket }, ...(app.colSort.name === "board" ? [reorder("up"), reorder("down")] : [])] : []),
      ...(group?.group && !group.header ? [{ ...bind("column.space"), run: () => ctl.open({ kind: "epic", id: (group.act as { id: number }).id, from: mode }) }] : []),
      { ...bind("column.s", `sort: ${app.colSort.name} → ${next(COL_SORTS, app.colSort).name}`), run: () => ctl.resort(() => { app.colSort = next(COL_SORTS, app.colSort) }) },
      { ...bind("column.right"), run: () => ctl.open({ kind: "column", col: ((mode as { col: number }).col + 1) % COLS.length }) },
      ctl.back1,
    ],
  }
}

export function epicCard(app: State, ctl: Ctl, a: Agents, mode: Extract<Mode, { kind: "epic" }>): Card {
  const id = mode.id, ep = a.tickets.find((t) => t.id === id)
  const word = ep?.kind === "initiative" ? "INITIATIVE" : "EPIC"
  if (!ep) return { title: `${word} #${id}`, rows: [{ segs: [dim("finished or gone")] }], actions: [ctl.back1] }
  const kids = groupRows(a, id)
  return {
    title: `${word} #${id}${ep.kind === "epic" ? ` · ${ep.done ?? 0}/${ep.total ?? 0}` : ""}`,
    rows: [{ segs: [plain(ep.title)] }, { segs: [dim(`${ep.priority} priority${ep.next ? ` · next #${ep.next.id} ${ep.next.title}` : ""}`)] },
      ...kids.map((k) => {
        const to = k.kind === "ticket" ? ({ kind: "ticket", id: k.id } as const) : ({ kind: "epic", id: k.id } as const)
        return { segs: [key(`#${k.id} `), plain(k.title), dim(`  ${k.kind}`)], open: () => ctl.open({ ...to, from: mode }), ref: JSON.stringify(to) }
      })],
    actions: [ctl.back1],
  }
}

export function ticketCard(app: State, ctl: Ctl, a: Agents, mode: Extract<Mode, { kind: "ticket" }>): Card {
  const id = mode.id
  const tk = a.tickets.find((t) => t.id === id), full = app.tickets.find((t) => t.id === id)
  if (!tk) return { title: `TICKET #${id}`, rows: [{ segs: [dim("started or gone")] }], actions: [ctl.back1] }
  // an epic or initiative reached as a ticket (a find, a link) is a group: its card, never "start it"
  if (tk.kind === "epic" || tk.kind === "initiative") { app.mode = { kind: "epic", id, from: mode.from }; return ctl.detail() }
  const rows: Row[] = [{ segs: [plain(tk.title)] }, { segs: [dim(`${tk.priority} priority${tk.routed ? " · with the manager to staff" : ""}`)] }]
  const parent = tk.epic_id != null ? a.tickets.find((t) => t.id === tk.epic_id) : undefined
  if (parent) rows.push({ segs: [dim("epic "), key(`#${parent.id} `), plain(parent.title)] })
  for (const by of full?.blocked_by ?? []) rows.push({ segs: [pink("⊘ blocked by "), key(`#${by} `), plain(app.tickets.find((t) => t.id === by)?.title ?? "")] })
  if (full?.body) for (const l of wrap(full.body, cols() - 40)) rows.push({ segs: [dim(l)] })
  return {
    title: `TICKET #${id}`, rows,
    actions: [
      { ...bind("ticket.S"), run: () => void ctl.did(data.ticketStart(id)) },
      { ...bind("ticket.s"), run: () => void ctl.did(data.ticketRoute(id)) },
      { ...bind("ticket.e"), run: () => ctl.ask(`ticket #${id} title`, (s) => { if (s.trim()) ctl.did(data.ticketPatch(id, { title: s.trim() })) }, { text: tk.title }) },
      {
        ...bind("ticket.b"), run: () => {
          const others = app.tickets.filter((t) => t.id !== id && t.status !== "done")
          ctl.find(`#${id} IS BLOCKED BY`, others.map((t) => ({ segs: [key(`#${t.id} `), plain(t.title), dim(`  ${t.status}`)], text: `#${t.id} ${t.title}`, run: () => { app.picker = null; void ctl.did(data.ticketBlock(id, t.id)) } })))
        },
      },
      ...(full?.blocked_by.length ? [{ ...bind("ticket.u"), run: () => { for (const by of full.blocked_by) void ctl.did(data.ticketUnblock(id, by)) } }] : []),
      { ...bind("ticket.K"), run: () => void ctl.did(data.ticketReorder(id, "up")) }, { ...bind("ticket.J"), run: () => void ctl.did(data.ticketReorder(id, "down")) },
      { ...bind("ticket.d"), run: () => ctl.ask2(`delete ticket #${id}`, () => { ctl.back(); void ctl.did(data.ticketDelete(id)) }) },
      ctl.back1,
    ],
  }
}
