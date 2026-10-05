// The TUI's line to the server: the same tlon-cli verbs the desktop shell calls, run from this
// checkout, so it works wherever the server does (Linux or macOS).
import { resolve } from "node:path"
import { EMPTY, type Agents, type ThreadView } from "../kit/types"

const CLI = resolve(import.meta.dir, "../../scripts/tlon-cli.sh")

/** run a verb; its last stdout line, or throw with what it said */
async function run(...args: string[]): Promise<string> {
  const p = Bun.spawn([CLI, ...args], { stdout: "pipe", stderr: "pipe" })
  const [out, err, code] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text(), p.exited])
  if (code !== 0) throw new Error((err || out).trim().split("\n").pop() || `${args[0]} exited ${code}`)
  return out.trim().split("\n").pop() ?? ""
}

export async function status(): Promise<Agents> {
  try {
    const j = JSON.parse(await run("shell-status"))
    return {
      ok: true, roster: j.roster ?? [], threads: j.threads ?? [], counts: j.counts ?? {}, awaiting: j.awaiting ?? 0,
      bench: j.bench ?? [], projects: j.projects ?? [], tickets: j.tickets ?? [], workspaces: j.workspaces ?? [], archetypes: j.archetypes ?? [], models: j.models ?? [], notes: j.notes ?? [], visits: j.visits ?? [],
    }
  } catch {
    return { ...EMPTY, note: "channel down" }
  }
}
export async function thread(id: number): Promise<ThreadView | null> {
  try { return JSON.parse(await run("shell-thread", String(id))) } catch { return null }
}

/** a write: what it said back (or why it failed), for the status line */
async function write(what: string, ...args: string[]): Promise<string> {
  try { return (await run(...args)) || `${what}: ok` } catch (e) { return `${what} failed: ${(e as Error).message}` }
}
/** post to a thread as the operator; a body naming an open prompt's option answers it */
export const post = (id: number, body: string) => write(`reply to #${id}`, "post", String(id), body)
export const ticketFile = (ws: number, title: string) => write("filing a ticket", "ticket-file", String(ws), "-", title, "")
/** send a ticket to the workspace's manager to staff (no manager: its lead starts it) */
export const ticketRoute = (id: number) => write(`sending #${id} to the manager`, "ticket-route", String(id))
/** start a ticket's thread with the workspace's lead */
export const ticketStart = (id: number) => write(`starting #${id}`, "ticket-start", String(id))
/** close a thread as done: its sessions end, its ticket is done, a child reports up */
export const closeThread = (id: number) => write(`closing #${id}`, "close-thread", String(id))
