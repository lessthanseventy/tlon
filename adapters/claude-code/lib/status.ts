// A seat's state and its glyph, mirroring the server's (`Server.Coworker.status/1`, `glyph/1`): one word,
// one mark, on every surface.

export type SeatStatus = "working" | "waiting" | "idle" | "cold" | "off";

const GLYPH: Record<SeatStatus, string> = { working: "●", waiting: "!", idle: "○", cold: "◌", off: "·" };

/** The server's `status` when it sends one (a roster row); else derived from the facts a glance carries. */
export function seatStatus(c: { status?: SeatStatus; thinking: boolean; warm: boolean }): SeatStatus {
  if (c.status && c.status in GLYPH) return c.status;
  return c.thinking ? "working" : c.warm ? "idle" : "cold";
}

export function seatGlyph(s: SeatStatus): string {
  return GLYPH[s];
}
