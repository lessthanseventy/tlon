// A coworker's voice for their room lines — the §2 table of the office-as-a-toy design, the
// fallback the office uses when the server's banter wrote nothing (in `--sandbox`, always). The
// server's `Server.Persona` keeps the one-line voice description it seeds a persona from; these are
// the canned lines a seat mutters in the room, in that voice. A voice is presentation only — it
// never changes a decision.

/** the §2 seats, in design order */
export const SEATS = ["scharlach", "tertius", "hronir", "lonnrot", "yu", "beatriz", "nolan", "emma", "ireneo", "daneri", "sonny"] as const
export type SeatName = (typeof SEATS)[number]

/** a seat's voice: `banter` is what it mutters in the room, `{name}` whoever it is about */
export type Voice = { banter: readonly string[] }

export const SEAT_VOICE: Record<string, Voice> = {
  // the Dwight: crisp and slightly too formal; enforces the rules and enjoys it too much
  scharlach: {
    banter: [
      "Issue noted. I have filed it.",
      "Duly logged. Further action is at my discretion.",
      "I have reviewed the matter. It is resolved.",
      "A discrepancy. I will be keeping a record of this.",
      "Noted, and filed under 'ongoing concerns.'",
    ],
  },
  // dry, unflappable, has seen it all
  tertius: {
    banter: [
      "Seen worse. This will pass.",
      "That again. Right.",
      "Mm. Noted, in the sense that I am not surprised.",
      "It was done before. It will be done again.",
      "Calm. It's only a deploy.",
    ],
  },
  // old-school; mutters about how it was done before
  hronir: {
    banter: [
      "We did this by hand, you know. Faster, too.",
      "Before your fancy tools, we had this sorted.",
      "Hmph. In my day the build didn't lie to you.",
      "Used to be a one-line fix. Probably still is.",
      "They don't write them like that anymore. Shame.",
    ],
  },
  // a detective; reviews read like case notes
  lonnrot: {
    banter: [
      "The clue was in the diff, as it so often is.",
      "A curious case. I am following the thread.",
      "Note the inconsistency. It is not nothing.",
      "The facts, once assembled, admit one reading.",
      "I have marked the anomaly for further inquiry.",
    ],
  },
  // careful, precise, a little anxious
  yu: {
    banter: [
      "I just want to be sure. One more look.",
      "Probably fine. …Probably.",
      "Let me re-check that, if no one minds.",
      "I'd rather be certain than fast, if that's alright.",
      "Sorry — small thing, but it nags at me.",
    ],
  },
  // brisk, organized, has a spreadsheet for this
  beatriz: {
    banter: [
      "Tracked. It's in the sheet.",
      "Next. I've blocked out the hour.",
      "Numbered, filed, moving on.",
      "I have a tab for that, obviously.",
      "Sorted by priority. We're on item three.",
    ],
  },
  // theatrical; QA is "the performance"
  nolan: {
    banter: [
      "The performance begins. Watch the tests, darling.",
      "A standing ovation for that coverage, surely.",
      "The drama is in the failure. I live for it.",
      "Curtain up on the next suite. Break a leg.",
      "Critics agree: this build is a triumph.",
    ],
  },
  // quietly determined; finishes what she starts
  emma: {
    banter: [
      "I'll see it through. Don't wait up.",
      "Nearly there. Steady does it.",
      "Not done yet. Soon.",
      "One thing at a time. That one's almost done.",
      "I said I'd finish it. So I will.",
    ],
  },
  // remembers everything, says so
  ireneo: {
    banter: [
      "I remember when this last broke. Exactly the same.",
      "I recall the fix. It was a Tuesday.",
      "I have total recall of that incident, you know.",
      "As I noted at the time — and I do note things —",
      "I remember every line of this. Every one.",
    ],
  },
  // grandiose; every change is a masterpiece
  daneri: {
    banter: [
      "A masterpiece. They will study this commit.",
      "I have composed a work of real grandeur here.",
      "Behold: the definitive solution. You're welcome.",
      "My finest yet, and I say that without vanity.",
      "History will remember this merge. Mark it.",
    ],
  },
  // sunny; brings a flower to every handoff
  sonny: {
    banter: [
      "Here you go — fixed it, and I brought a flower.",
      "Bright day, isn't it? Handoff's all smiles.",
      "All done! Left a little bloom on your desk.",
      "Passing it along with good vibes only.",
      "Done and dusted. Sunny side up, as ever.",
    ],
  },
}

/** a plain-spoken builder, the fallback for a seat the table doesn't name */
const GENERIC: Voice = {
  banter: ["Done. Moving on.", "That's built. Next.", "Right, that's sorted.", "Shipped it. On to the next."],
}

/** a pick that skips what was said lately, while anything else is left to say */
export const seatLine = (name: string, recent: readonly string[]): string => {
  const voice = SEAT_VOICE[name] ?? GENERIC
  const all = voice.banter.map((l) => l.replaceAll("{name}", "you"))
  const unsaid = all.filter((l) => !recent.includes(l))
  const pool = unsaid.length ? unsaid : all
  return pool[Math.floor(Math.random() * pool.length)]!
}