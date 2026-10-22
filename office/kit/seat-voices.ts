// A coworker's voice for their room lines — the §2 table of the office-as-a-toy design, the
// fallback the office uses when the server's banter wrote nothing (in `--sandbox`, always). The
// server's `Server.Persona` keeps the one-line voice description it seeds a persona from; these are
// the canned lines a seat mutters in the room, in that voice. A voice is presentation only — it
// never changes a decision.

import type { EventKind } from "./events"
import { pickFresh } from "./voices"

/** the §2 seats, in design order */
export const SEATS = ["scharlach", "tertius", "hronir", "lonnrot", "yu", "beatriz", "nolan", "emma", "ireneo", "daneri", "sonny"] as const
export type SeatName = (typeof SEATS)[number]

/** a seat's voice: `banter` is what it mutters in the room */
export type Voice = { banter: readonly string[]; /** what a seat says after losing a game to a rival */ sore: readonly string[] }

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
    sore: [
      "That match will be struck from the record.",
      "I am filing a complaint about the table.",
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
    sore: [
      "Fine. It was a bad table anyway.",
      "Lost. It happens. Not to me, usually.",
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
    sore: [
      "Hmph. The old tables were levelled.",
      "In my day nobody lost on a bad bounce.",
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
    sore: [
      "I was misled by the angle. Noted.",
      "The loss was not random. I will find the cause.",
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
    sore: [
      "Sorry, sorry, I should have seen that coming.",
      "I lost. Is that bad? That feels bad.",
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
    sore: [
      "That was an outlier. I have the numbers.",
      "Rematch. I have a bracket drawn up.",
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
    sore: [
      "A tragedy in three acts, and I played the fool.",
      "The performance was robbed!",
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
    sore: [
      "Again. I'm not done.",
      "One game. I'm taking the next one.",
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
    sore: [
      "I remember every shot. This one still lost.",
      "I will never forget this. Rematch.",
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
    sore: [
      "A masterpiece, undone by a single bounce!",
      "History will record this as a draw.",
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
    sore: [
      "Good game! Mostly. A bit sore, honestly.",
      "Well played. I'm picking you a flower out of spite.",
    ],
  },
}

/** a plain-spoken builder, the fallback for a seat the table doesn't name */
const GENERIC: Voice = {
  banter: ["Done. Moving on.", "That's built. Next.", "Right, that's sorted.", "Shipped it. On to the next."],
  sore: ["Lost. Again, then.", "That table is rigged."],
}

/** a pick that skips what was said lately, while anything else is left to say */
export const seatLine = (name: string, recent: readonly string[]): string => {
  const voice = SEAT_VOICE[name] ?? GENERIC
  const all = voice.banter
  const unsaid = all.filter((l) => !recent.includes(l))
  const pool = unsaid.length ? unsaid : all
  return pool[Math.floor(Math.random() * pool.length)]!
}

/** what a seat says after losing a game to a rival */
export const soreLine = (name: string): string => {
  const sore = (SEAT_VOICE[name] ?? GENERIC).sore
  return sore[Math.floor(Math.random() * sore.length)]!
}

/** each seat's two lines for each scripted event (kit/events.ts), in its own voice */
export const SEAT_REACT: Record<string, Partial<Record<EventKind, readonly string[]>>> = {
  scharlach: {
    drill: ["Muster point B. I have a clipboard.", "Single file. I am counting heads."],
    zoo: ["This is a Class 3 incursion.", "I am deploying the net. Stand clear."],
    meteor: ["An unscheduled impact. I am filing a report.", "That was not in the safety binder."],
    power: ["Remain calm. I have a torch and a log.", "Outage recorded at the time of occurrence."],
    duck: ["An unregistered waterfowl. I will see it out.", "Visitor without a badge. Noted."],
    gary: ["That dumpster is not zoned for occupancy. Noted.", "Stand clear of the lid. I will be logging this."],
  },
  tertius: {
    drill: ["Drill. Right. Coat's by the door.", "Seen drills. This is one of them."],
    zoo: ["That's a goat. Fine.", "Seen worse. Not by much."],
    meteor: ["Well. That's new.", "Mm. Somebody will have to sweep that."],
    power: ["Lights. Right. Wait it out.", "It always comes back."],
    duck: ["A duck. Alright.", "Don't feed it. Nobody listens."],
    gary: ["Gary's out. Guard your yogurt.", "Seen him worse. Just don't stand nearest."],
  },
  hronir: {
    drill: ["In my day we just left by the stairs.", "Drills. We called it going home."],
    zoo: ["Back when I started, the zoo came on Fridays.", "They never used to let the goat in."],
    meteor: ["Used to be you'd hear it coming.", "Hmph. They don't make meteors like they used to."],
    power: ["We had candles for this. Real ones.", "Dark. Same as the old server room."],
    duck: ["A duck. Used to have two.", "Hmph. At least this one is on time."],
    gary: ["In my day the bins stayed shut.", "Hmph. A fish bone. Proper sword, that."],
  },
  lonnrot: {
    drill: ["A drill — or is it? I shall observe the exits.", "Note who leaves first. It is telling."],
    zoo: ["The goat has been at the corkboard. The motive is unclear.", "Four animals, one door. The case writes itself."],
    meteor: ["The window faced the impact. That is not a coincidence.", "I shall want to examine the crater."],
    power: ["Darkness. Convenient for someone.", "The lamps went out together. I have marked the time."],
    duck: ["The duck is concealing something.", "A visitor, unexplained. I am following it."],
    gary: ["The yogurt is the motive. The lid is the alibi.", "Eyes in the gap under the lid. I shall keep my distance."],
  },
  yu: {
    drill: ["Is it the real one? I'll just double check.", "Sorry — which way is out, exactly?"],
    zoo: ["Is it supposed to do that? The goat, I mean.", "Sorry, there is a penguin. I just want to flag it."],
    meteor: ["That was probably fine. …Probably.", "I'd like to be certain that was outside."],
    power: ["Did I save? I should have saved.", "It's fine. It's fine. Where did my work go?"],
    duck: ["Is the duck okay? Should someone check?", "Sorry — I'd like to be sure it knows the way out."],
    gary: ["Is the thing in the dumpster allowed to do that?", "Sorry — he said my yogurt. Is that my yogurt?"],
  },
  beatriz: {
    drill: ["Drill logged. Two minutes, tops.", "I've got the headcount. Everyone's on the sheet."],
    zoo: ["That's four animals. I'll add a row.", "Unplanned headcount. Updating the sheet."],
    meteor: ["Impact, time-stamped. Moving on.", "I'll block out time for the cleanup."],
    power: ["Outage. I'll note the duration.", "Laptop at forty percent. We're fine."],
    duck: ["One duck. Tracked.", "Not on the calendar. Noted anyway."],
    gary: ["One gremlin, one sandwich at risk. Tracked.", "Slap odds are one in three. I'll note it."],
  },
  nolan: {
    drill: ["The alarm! A grand entrance, darling.", "Places, everyone. This is our scene."],
    zoo: ["A menagerie! The second act arrives.", "The penguin steals the show. Rude."],
    meteor: ["Now THAT is a dramatic reveal.", "Lightning, thunder, a crater. Bravo."],
    power: ["Blackout. Pure theatre. I adore it.", "Lights out — the audience gasps."],
    duck: ["A duck! A cameo, unannounced.", "The duck has presence. I'll allow it."],
    gary: ["A villain in a lid crown! Enter, stage left.", "The cape is banana peel. I am in love."],
  },
  emma: {
    drill: ["Out we go. I'll finish when we're back.", "Steady. Walk, don't run."],
    zoo: ["I'll keep working. The goat can sort itself out.", "One thing at a time. Goat first, perhaps."],
    meteor: ["That was close. I'll get back to it.", "Fine. Not my crater."],
    power: ["I'll pick it up where I left off.", "Quiet. I can finish this in the dark."],
    duck: ["Hello, duck. I have work to do.", "It'll find its own way out."],
    gary: ["I'll keep working. He can have the sandwich.", "Not looking up. If I don't look, he can't slap."],
  },
  ireneo: {
    drill: ["I remember the last drill. Every step of it.", "I recall the exits. All four."],
    zoo: ["I remember the goat. It was a Tuesday.", "The penguin was here before. I remember its name."],
    meteor: ["I remember the last meteor. Exactly this angle.", "As I noted at the time — it was a Thursday."],
    power: ["I remember the previous outage, to the second.", "I recall that exact dark. It lasted four minutes."],
    duck: ["I remember this duck. It had a limp.", "I recall the duck. We exchanged nods."],
    gary: ["I remember Gary's last slap. It was left cheek.", "I recall the sock he left. It was argyle."],
  },
  daneri: {
    drill: ["An alarm for me, surely. Magnificent.", "They evacuate for genius. As is proper."],
    zoo: ["A zoo — in honour of my latest commit, I assume.", "Even the goat knows greatness."],
    meteor: ["The heavens salute my merge. Naturally.", "A meteor. It had to be worthy of me."],
    power: ["Even the lamps bow to my work.", "Darkness. I shall write by my own brilliance."],
    duck: ["A duck has come to witness greatness.", "It arrives, as all do, to admire the work."],
    gary: ["He wears a crown; I wear my commits. Equals.", "Slap me if you dare. The diff will outlive us both."],
  },
  sonny: {
    drill: ["Out we go! Fresh air is great, actually.", "Everybody smiling? Great, let's go!"],
    zoo: ["Animals! I brought a flower for the penguin.", "The goat seems lovely, honestly."],
    meteor: ["Wow, a shooting star! Make a wish!", "That was fun — is everybody okay?"],
    power: ["Cosy! Candlelight, everyone!", "Dark, but we've got each other."],
    duck: ["A duck! Hi, duck! Here's a flower.", "Look at him go! What a day."],
    gary: ["Gary! Hi, Gary! I'd share my yogurt!", "He's just a little guy with a fish bone. Aww."],
  },
}

/** a plain one-liner per event for a seat the table doesn't name */
const GENERIC_REACT: Record<EventKind, readonly string[]> = {
  drill: ["Drill. On my way."],
  zoo: ["That's a lot of animals."],
  meteor: ["Was that a meteor?"],
  power: ["Lights are out."],
  duck: ["There's a duck."],
  gary: ["Something is in the dumpster."],
}

/** a seat's line for an event, skipping what it said lately while anything else is unsaid */
export const reactLine = (name: string, kind: EventKind, recent: readonly string[]): string =>
  pickFresh(SEAT_REACT[name]?.[kind] ?? GENERIC_REACT[kind], recent)
