// What Nina says, by occasion, when the server's model has written her nothing fresh
// (`Server.Office.Pets`, through `Sim.hear`). She is a princess and a diva — a cat of some renown, in
// her own opinion, in a jewelled collar — and the office exists to admire her. Argos' lines are his
// room's (rooms/wide.ts): he lives only there.

export const pick = <T,>(xs: readonly T[]): T => xs[Math.floor(Math.random() * xs.length)]!

/** a worker fussing over a pet: a pat on the head, a scratch, a belly rub, a treat */
export type Fuss = "pat" | "scratch" | "belly" | "treat"

export const NINA = {
  // you, clicking on her
  pet: ["Yes. Adore me. Continue.", "You may touch the royal fur. Briefly.", "Mind the collar. It's couture.", "prrr... this changes nothing.", "Finally, some respect in this office."],
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
  // what you tell her to do
  nap: ["Napping was MY idea, for the record."],
  play: ["The yarn has disrespected me for the LAST time."],
  come: ["I'm coming because I WANT to. Not because you asked."],
  zoomies: ["PRINCESS ZOOMIES! Clear the runway!"],
  // a worker fussing over her
  fuss: {
    pat: ["Gentle. I'm priceless.", "Head pats are a privilege, peasant.", "prrr... you may continue."],
    scratch: ["Left. LEFT. Ohhh, yes. Right there.", "Under the collar. Carefully. It's couture."],
    belly: ["The belly is NOT for touching. It's a TRAP."],
    treat: ["A tribute! I accept your offering.", "nom. Adequate. Bring more.", "nom nom. You may live."],
  } satisfies Record<Fuss, string[]>,
}
