// The TUI's line to the server: the operator API over loopback HTTP (Server.MCP.OperatorAPI) — the
// always-up service at 127.0.0.1:4040 unless TLON_URL says otherwise. No checkout, no release
// beside it: a compiled TUI runs anywhere the server answers.
import { EMPTY, type Agents, type ThreadView } from "../kit/types"
import type { Target } from "./terminal"

const BASE = (process.env.TLON_URL ?? "http://127.0.0.1:4040").replace(/\/$/, "")

async function call(method: "GET" | "POST", path: string, body?: unknown): Promise<{ status: number; json: any }> {
  const r = await fetch(`${BASE}/api${path}`, {
    method,
    headers: body === undefined ? {} : { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(8000),
  })
  return { status: r.status, json: await r.json().catch(() => null) }
}

export async function status(): Promise<Agents> {
  try {
    const { status, json: j } = await call("GET", "/office")
    if (status !== 200 || !j) throw new Error(`office ${status}`)
    return {
      ok: true, roster: j.roster ?? [], threads: j.threads ?? [], counts: j.counts ?? {}, awaiting: j.awaiting ?? 0,
      bench: j.bench ?? [], projects: j.projects ?? [], tickets: j.tickets ?? [], workspaces: j.workspaces ?? [], archetypes: j.archetypes ?? [], models: j.models ?? [], notes: j.notes ?? [], visits: j.visits ?? [],
    }
  } catch {
    return { ...EMPTY, note: `channel down (${BASE})` }
  }
}
/** where a thread's coworker runs (its tmux socket, session, window), or null when it has no window */
export async function terminal(id: number): Promise<Target | null> {
  try { const r = await call("GET", `/threads/${id}/terminal`); return r.status === 200 ? r.json : null } catch { return null }
}
export async function thread(id: number): Promise<ThreadView | null> {
  try { const r = await call("GET", `/office/threads/${id}`); return r.status === 200 ? r.json : null } catch { return null }
}

/** a write: a line for the status bar saying what happened, or why it didn't */
async function write(what: string, path: string, body: unknown, ok: (j: any) => string): Promise<string> {
  try {
    const r = await call("POST", path, body)
    return r.status < 300 ? ok(r.json) : `${what} failed: ${r.json?.error ?? r.status}`
  } catch (e) {
    return `${what} failed: ${(e as Error).message}`
  }
}
/** post to a thread as the operator; a body naming an open prompt's option answers it */
export const post = (id: number, body: string) => write(`reply to #${id}`, `/threads/${id}/messages`, { body }, () => `sent to #${id}`)
export const ticketFile = (ws: number, title: string) => write("filing a ticket", "/tickets", { workspace_id: ws, title }, (j) => `filed ticket #${j.id}`)
/** send a ticket to the workspace's manager to staff (no manager: its lead starts it) */
export const ticketRoute = (id: number) =>
  write(`sending #${id} to the manager`, `/tickets/${id}/route`, {}, (j) => (j.routed_to ? `ticket #${id} sent to ${j.routed_to}` : `no manager: #${id} started as thread #${j.thread}`))
/** start a ticket's thread with the workspace's lead */
export const ticketStart = (id: number) => write(`starting #${id}`, `/tickets/${id}/start`, {}, (j) => `ticket #${id} started as thread #${j.thread}`)
/** close a thread as done: its sessions end, its ticket is done, a child reports up */
export const closeThread = (id: number) => write(`closing #${id}`, `/threads/${id}/close`, {}, (j) => `closed #${id} — ${j.title}`)
