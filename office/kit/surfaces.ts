// Who acts on what waits (`Server.Office.Needs.surface/1`): the phone rings for an answer owed, the
// answering machine blinks for information, the sheriff's clipboard holds what the crew owns.

/** the top bar's one count: only an answer owed reaches it */
export function phoneBar(counts: { phone: number }): { text: string; ringing: boolean } | null {
  return counts.phone > 0 ? { text: `${counts.phone} waiting on you`, ringing: true } : null
}

/** the phone's glyph at a tick: it shakes while ringing, so the ring never rests on colour alone */
export const ringFrame = (tick: number, ringing: boolean) => (ringing && tick % 2 === 1 ? "☏" : "☎")
