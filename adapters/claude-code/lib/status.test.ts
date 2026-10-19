import { expect, test } from "bun:test";
import { seatGlyph, seatStatus } from "./status.ts";

test("the server's status wins, and each status has its one glyph", () => {
  expect((["working", "waiting", "idle", "cold", "off"] as const).map((s) => seatGlyph(seatStatus({ status: s, thinking: false, warm: false })))).toEqual(["●", "!", "○", "◌", "·"]);
});

test("an older server's row, with no status, is derived through the same mapping", () => {
  expect(seatStatus({ thinking: true, warm: true })).toBe("working");
  expect(seatStatus({ thinking: false, warm: true })).toBe("idle");
  expect(seatStatus({ thinking: false, warm: false })).toBe("cold");
});
