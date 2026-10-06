import { describe, expect, test } from "bun:test"
import { drawActors, Scene } from "../kit/draw"
import type { Actor } from "../kit/sim"
import { ACTIVITY, lookOf } from "../kit/sprites"
import { EMPTY, type Agents } from "../kit/types"
import { WideRoom } from "../rooms/wide"
import { viewOf } from "../kit/crew"

// the server's `presence_doing` kinds (Server.MCP.Tool.PresenceDoing), and a turn between tools
const KINDS = ["think", "read", "edit", "bash", "search", "web", "test", "delegate"]
const focus = { picked: null, armed: null, person: null }

function frame(doing: string | null, tick = 0, extra: Partial<Actor> = {}) {
  const sc = new Scene(48, 48, tick)
  const seat = { agent: "hronir", thread_id: 1, title: "", warm: true, thinking: true, doing, archetype: "builder" }
  const spot = { x: 14, y: 40, aisle: 44, pose: "sit" as const, face: "up" as const, kind: "desk" as const }
  drawActors(sc, [{ seat, look: lookOf("hronir"), x: 14, y: 40, path: [], spot, spotKey: "", pose: "sit", face: "up", moving: false, until: 0, emote: null, emoteUntil: 0, leaving: false, doingSince: tick, stretch: 0, ...extra }], new Map(), EMPTY, focus)
  return sc.finish().rgba.join(",")
}

describe("what a worker is doing, over their head", () => {
  test("every kind the server can say has 5x5 frames", () => {
    for (const k of KINDS) {
      expect(ACTIVITY[k]?.length).toBeGreaterThan(0)
      for (const g of ACTIVITY[k]!) expect([g.length, ...g.map((r) => r.length)]).toEqual([5, 5, 5, 5, 5, 5])
    }
  })

  test("each kind looks different from every other", () => {
    expect(new Set(KINDS.map((k) => frame(k === "think" ? null : k))).size).toBe(KINDS.length)
  })

  test("a kind this office has never heard of is plain thinking", () => {
    expect(frame("juggle")).toBe(frame(null))
  })

  test("a tool that runs on makes them sweat", () => {
    expect(frame("bash", 1000, { doingSince: 0 })).not.toBe(frame("bash", 1000))
  })
})

function office(state: { thinking: boolean; doing?: string | null }): Agents {
  return {
    ...EMPTY, ok: true,
    workspaces: [{ id: 1, name: "Machine" }],
    archetypes: [{ name: "builder", meta: false, read_only: false, model: "" }],
    bench: [{ workspace_id: 1, seat_id: 1, agent_id: 1, name: "hronir", archetype: "builder", lead: true, model: null, ask: null }],
    threads: [{ id: 100, title: "t", stage: null, awaiting: null, workspace_id: 1, lead: "hronir" }],
    roster: [{ agent: "hronir", thread_id: 100, title: "t", warm: false, workspace_id: 1, ...state }],
  }
}

describe("the sim keeps time for it", () => {
  const actor = (room: WideRoom) => (room as unknown as { actors: Map<string, Actor> }).actors.get("hronir")!

  test("a new kind of work restarts the clock its sweat runs on", () => {
    const room = new WideRoom(560)
    for (let i = 0; i < 300; i++) room.step(viewOf(office({ thinking: true, doing: "bash" }), 1))
    const since = actor(room).doingSince
    room.step(viewOf(office({ thinking: true, doing: "edit" }), 1))
    expect(actor(room).doingSince).toBeGreaterThan(since)
  })

  test("a turn done at the desk, they stretch there before they get up", () => {
    const room = new WideRoom(560)
    for (let i = 0; i < 600; i++) room.step(viewOf(office({ thinking: true }), 1))
    expect(actor(room).spot.kind).toBe("desk")
    for (let i = 0; i < 10; i++) room.step(viewOf(office({ thinking: false }), 1))
    expect([actor(room).spot.kind, actor(room).moving]).toEqual(["desk", false])
    for (let i = 0; i < 30; i++) room.step(viewOf(office({ thinking: false }), 1))
    expect(actor(room).spot.kind).not.toBe("desk")
  })
})
