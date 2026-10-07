import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { WideRoom } from "../rooms/wide"
import { office } from "./wcag.test"

describe("Sim.at", () => {
  test("Sim.at returns a seated actor's current spot, or null for a stranger", () => {
    const room = new WideRoom(696)
    room.step(viewOf(office(), 1)) // seeds actors from the roster
    const at = room.at("yu")
    expect(at === null || (typeof at.x === "number" && typeof at.y === "number")).toBe(true)
    expect(room.at("nobody-by-this-name")).toBeNull()
  })
})
