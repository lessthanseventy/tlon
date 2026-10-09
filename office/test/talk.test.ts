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
    await say([th(2, 1, true)], 1, "ada", "hello")
    await say([th(2, 1, true)], 1, null, "we need a thing")
    srv.stop()
    expect(got).toEqual([
      { path: "/api/threads/2/messages", body: { body: "@ada hello" } },
      { path: "/api/threads/2/messages", body: { body: "we need a thing" } },
    ])
  })
  test("no lobby, no post", async () => { expect(await say([], 1, null, "x")).toMatch(/no lobby/) })
})
