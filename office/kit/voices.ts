// What Nina says, by occasion, when the server's model has written her nothing fresh
// (`Server.Office.Pets`, through `Sim.hear`). She is a princess and a diva — a cat of some renown, in
// her own opinion, in a jewelled collar — and the office exists to admire her. Argos' lines are his
// room's (rooms/wide.ts): he lives only there.
import type { Temperament } from "./temperament"

export const pick = <T,>(xs: readonly T[]): T => xs[Math.floor(Math.random() * xs.length)]!

/** a pick that skips what was said lately, while anything else is left to say */
export const pickFresh = (xs: readonly string[], recent: readonly string[]): string => {
  const unsaid = xs.filter((x) => !recent.includes(x))
  return pick(unsaid.length ? unsaid : xs)
}

/**
 * A musing put together from parts, so the same few lines don't come round again: an opener and a
 * matter, each a pet's own (`NINA_RIFF`, Argos' `ARGOS_RIFF`) — dozens of lines out of a handful.
 */
export const riff = (parts: { open: readonly string[]; matter: readonly string[] }) => `${pick(parts.open)} ${pick(parts.matter)}`

export const NINA_RIFF = {
  open: ["Note to self:", "Official statement:", "For the record,", "Royal decree:", "Breaking news:", "Unpopular opinion:", "Overheard in my head:", "Today's grievance:"],
  matter: ["the sunbeam moved without my permission.", "that keyboard is warm and I am entitled to it.", "the red dot owes me an apology.", "my collar has never looked better.", "nobody has complimented my tail in an hour.", "the printer is plotting against me.", "I would make an excellent tech lead.", "the fish are getting ideas.", "this cushion is beneath my station.", "I have decided to like the dog. Today only."],
}

/** a worker fussing over a pet: a pat on the head, a scratch, a belly rub, a treat */
export type Fuss = "pat" | "scratch" | "belly" | "treat"

export const NINA = {
  // you, clicking on her
  pet: ["Yes. Adore me. Continue.", "You may touch the royal fur. Briefly.", "Mind the collar. It's couture.", "prrr... this changes nothing.", "Finally, some respect in this office.", "Again. But with more reverence.", "You missed a spot. Behind the ear. Obviously.", "I permit this.", "Your hands are cold. I'll allow it."],
  wake: ["I was NOT asleep. I was resting my eyes, regally.", "Who woke the princess? I want names.", "Ugh. Fine. I'm up. Worship accordingly."],
  muse: ["Has anyone noticed my collar today? Anyone??", "I am the main character of this office.", "I could lead this workspace. I'd be incredible.", "This floor is beneath me. Literally.", "I deserve a bigger tower. A castle, really.", "Sparkle check: still sparkling.", "My public needs me. Probably.", "Robbed of best nap. AGAIN."],
  // a worker starting a kind of tool
  read: ["Reading? Read about ME.", "Is it a book about princesses? No? Pass."],
  edit: ["Your typing is ruining my beauty rest.", "Write something nice about me in there."],
  bash: ["A terminal. How very common.", "Type quieter. I'm being fabulous."],
  search: ["Lost something, darling? Not my problem.", "If it's my sparkly collar, it's ON me."],
  web: ["Do NOT look up other cats.", "The internet is better when it's me."],
  test: ["If those fail, I am not taking the blame.", "Tests. I'd pass all of mine."],
  delegate: ["Delegating. Very princess of you. Approved."],
  done: ["Done? Good. Now attend to me.", "Wonderful. Now the important work: me."],
  queue: ["Someone's waiting on you. So am I, but prettier."],
  shipped: ["{name} shipped. I inspired it, obviously.", "Confetti? For ME? Oh. For {name}. Fine."],
  fish: ["The orange one mocks me. I have noted it.", "Glass. Always glass. Why is there always glass."],
  // what you tell her to do
  nap: ["Napping was MY idea, for the record.", "Wake me for treats. Only treats.", "Beauty sleep. You wouldn't understand."],
  play: ["The yarn has disrespected me for the LAST time.", "Fear me, string.", "I am a fearsome hunter. Of wool."],
  come: ["I'm coming because I WANT to. Not because you asked.", "Fine. Clear the desk. I'm lying on the important papers.", "I was going that way anyway."],
  zoomies: ["PRINCESS ZOOMIES! Clear the runway!"],
  // she sits on someone's keyboard
  keyboard: ["This is my desk now.", "I fixed your code, {name}. You're welcome.", "Warm. Mine. Go away.", "I'm helping.", "Your keyboard is my cushion now, {name}."],
  // you send her over to someone: she tells them so, in her way
  cheer: ["{name}. Your code is almost as elegant as me.", "{name}, I've decided you're doing well. You're welcome.", "Keep going, {name}. I'll supervise. From your keyboard.", "{name}, a princess believes in you. Briefly.", "{name}! That test will pass. I've commanded it.", "{name}, you may pet me when you've shipped. Not before."],
  // a worker fussing over her
  fuss: {
    pat: ["Gentle. I'm priceless.", "Head pats are a privilege, peasant.", "prrr... you may continue."],
    scratch: ["Left. LEFT. Ohhh, yes. Right there.", "Under the collar. Carefully. It's couture."],
    belly: ["The belly is NOT for touching. It's a TRAP."],
    treat: ["A tribute! I accept your offering.", "nom. Adequate. Bring more.", "nom nom. You may live."],
  } satisfies Record<Fuss, string[]>,
}

/** Nina's warm bucket (`warmth` > 0): the same occasions, none of the edge. Missing occasions stay sassy. */
export const SWEET: Partial<Record<keyof typeof NINA, readonly string[]>> = {
  pet: ["Oh, that's lovely. Don't stop.", "prrr... you're my favourite person.", "Yes please. Right there."],
  wake: ["Oh! Hello. Was I snoring?", "Mm. Good morning, everyone."],
  muse: ["I love it when everyone's here.", "The sunbeam is warm and so are you.", "Good day for a good nap."],
  done: ["Well done. Genuinely.", "Done! I knew you could."],
  cheer: ["{name}, you're doing so well.", "{name}! I believe in you. Truly."],
}

/** sweet with odds (no roll at all when not warm: a seeded sequence must not shift) that grow with warmth (0 at neutral or cold, 0.9 at +2), else the sassy bucket */
export function bucketFor(occasion: string, t: Temperament, rand: () => number, species = "cat"): readonly string[] {
  const own = species === "rabbit" || species === "bird" ? SPECIES_VOICE[species] : null
  const sassy = own?.sassy[occasion] ?? (NINA as Record<string, unknown>)[occasion] as readonly string[]
  const sweet = own ? own.sweet[occasion] : (SWEET as Record<string, readonly string[]>)[occasion]
  return sweet && t.warmth > 0 && rand() < (Math.max(0, t.warmth) / 2) * 0.9 ? sweet : sassy
}

/** what a rabbit and a bird say, sassy or sweet by warmth; an occasion missing here falls back to Nina's lines */
export const SPECIES_VOICE: Record<"rabbit" | "bird", { sassy: Record<string, readonly string[]>; sweet: Record<string, readonly string[]> }> = {
  rabbit: {
    sassy: {
      pet: ["Ears are off limits. Ask first.", "Fine. Two strokes. Count them."],
      muse: ["The carrot situation is unacceptable.", "I could out-hop every one of you."],
      wake: ["I was thinking. Horizontally.", "Who thumped? Oh. It was me."],
      done: ["Done. Where is my carrot?", "Finally. Hop along, then."],
    },
    sweet: {
      pet: ["*nose wiggles* More, please.", "Soft. You have soft hands."],
      muse: ["Everyone is so nice to nap near.", "I like the quiet hours. And you."],
      wake: ["Oh! Good morning. Hop hop.", "Mm. Did I miss anything lovely?"],
      done: ["Well done! Binky!", "You did it. I'm doing a little hop."],
    },
  },
  bird: {
    sassy: {
      pet: ["Hands off the feathers.", "One pat. Then I'm back on my perch."],
      muse: ["I see everything from up here.", "That seed was stale. I said what I said."],
      wake: ["Tweet. That means go away.", "I was NOT dozing. I was surveying."],
      done: ["Done? Chirp. Obviously.", "About time. Seed, please."],
    },
    sweet: {
      pet: ["Tweet! Right there, thank you.", "*fluffs up* Lovely."],
      muse: ["The light is so nice on my perch today.", "I could sing for everyone. I think I will."],
      wake: ["Good morning! Chirp chirp!", "Oh, hello, friend!"],
      done: ["You did it! I'll sing for you.", "Hooray! Tweet tweet!"],
    },
  },
}
