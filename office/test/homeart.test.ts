import { describe, expect, test } from "bun:test"
import { rotated } from "../kit/homeart"

describe("rotated", () => {
  const s = ["abc", "def", "ghi"]
  test("clockwise quarter turns", () => {
    expect(rotated(s, 0)).toEqual(s)
    expect(rotated(s, 90)).toEqual(["gda", "heb", "ifc"])
    expect(rotated(s, 180)).toEqual(["ihg", "fed", "cba"])
    expect(rotated(s, 270)).toEqual(["cfi", "beh", "adg"])
  })
})
