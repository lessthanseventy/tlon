// The stereo: what playerctl reports, parsed into a label and an optional tempo; and the
// scroll-window math for a marquee longer than its display width.

/** what's playing, as the stereo's label draws it; `bpm` is null unless a player's metadata
 *  actually carries a tempo field (most don't — the dance trigger stays inert until one does) */
export type NowPlaying = { text: string; bpm: number | null }

/** `stdout` of `playerctl metadata --format '{{ title }}|{{ artist }}|{{ bpm }}'`; null when
 *  there's nothing playing (blank title and artist) */
export function parseNowPlaying(stdout: string): NowPlaying | null {
  const [title = "", artist = "", bpmRaw = ""] = stdout.trim().split("|")
  if (!title && !artist) return null
  const bpm = Number(bpmRaw)
  return { text: artist ? `${title} - ${artist}` : title, bpm: Number.isFinite(bpm) && bpm > 0 ? bpm : null }
}

/** a `width`-wide slice of `text` at `tick`: padded still if it fits, else scrolling, looping
 *  with a gap so the end doesn't run straight into the start */
export function marqueeWindow(text: string, width: number, tick: number): string {
  if (text.length <= width) return text.padEnd(width)
  const loop = text + "   ", doubled = loop + loop
  return doubled.slice(tick % loop.length, (tick % loop.length) + width)
}
