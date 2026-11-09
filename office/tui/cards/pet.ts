import { random } from "../../kit/rng"
import { cycleAxis, dots, previewOf, resolvePets, SLOT_SPECIES, SPECIES_BLURB, TEMPERAMENTS, type CatSpecies } from "../../kit/pets"
import { AXES } from "../../kit/temperament"
import { WideRoom } from "../../rooms/wide"
import { bind } from "../keys"
import { loadPets, savePets } from "../pets"
import { type Mode, type Row, type Card } from "../state"
import { changed } from "../select"
import { cycleVal, dim, plain } from "../ui"
import type { State } from "../state"
import type { Ctl } from "../ctl"

export function petCard(app: State, ctl: Ctl, mode: Extract<Mode, { kind: "pet" }>): Card {
  const r = ctl.room(), wideRoom = r instanceof WideRoom ? r : null
  const doIt = (f: () => unknown) => () => { f(); changed(app); ctl.draw() }
  // someone mid-turn in this workspace, for a pet to go and cheer on
  const busy = () => app.all.roster.filter((x) => x.workspace_id === app.ws && x.thinking).map((x) => x.agent)
  const cheer = (send: (name: string) => boolean) => doIt(() => { const who = busy(); if (who.length) send(who[Math.floor(random() * who.length)]!) })
  if (mode.who === "cat") {
    const draft = (app.petDraft ??= structuredClone((app.petsNow ?? resolvePets(loadPets())).cat))
    const named = Object.entries(TEMPERAMENTS).find(([, t]) => AXES.every((a) => t[a] === draft.temperament[a]))?.[0]
    const row = (label: string, value: string, cycle: () => void): Row => ({ segs: [dim(label.padEnd(12)), plain(value)], open: () => { cycle(); ctl.draw() } })
    const beat = previewOf(draft, app.previewTick)
    const rows: Row[] = [
      { segs: [plain(SPECIES_BLURB[draft.species as CatSpecies] ?? SPECIES_BLURB.cat)] },
      { segs: [dim("name".padEnd(12)), plain(draft.name)] },
      row("species", draft.species, () => { draft.species = cycleVal(SLOT_SPECIES.cat, draft.species as CatSpecies) }),
      row("temperament", named ?? "custom", () => { const names = Object.keys(TEMPERAMENTS); draft.temperament = { ...TEMPERAMENTS[names[(names.indexOf(named ?? "") + 1) % names.length]!]! } }),
      ...AXES.map((a) => row(a, dots(draft.temperament[a]), () => { draft.temperament[a] = cycleAxis(draft.temperament[a]) })),
      { segs: [dim("preview".padEnd(12)), plain(`${{ sleep: "z", sit: "·", play: "o", walk: ">" }[beat.mode]} ${beat.line}`)] },
    ]
    return {
      title: `${draft.name.toUpperCase()}`, rows,
      actions: [
        { ...bind("pet.S.cat"), run: () => { savePets({ cat: { species: draft.species, temperament: named ?? { ...draft.temperament } } }); app.petsSeen = ""; ctl.followPets(); ctl.back(); app.roomChanged = true; ctl.draw() } },
        { ...bind("pet.p.cat"), run: doIt(() => r.pet()) },
        { ...bind("pet.z.cat"), run: doIt(() => r.catDo("zoomies")) },
        { ...bind("pet.y.cat"), run: doIt(() => r.catDo("play")) },
        { ...bind("pet.c.cat"), run: doIt(() => r.catDo("come")) },
        { ...bind("pet.s.cat"), run: doIt(() => r.catDo("nap")) },
        { ...bind("pet.b.cat"), run: doIt(() => r.catDo("drink")) },
        { ...bind("pet.u.cat"), run: doIt(() => r.catDo("tub")) },
        ...(busy().length ? [{ ...bind("pet.g.cat"), run: cheer((name) => r.catCheer(name)) }] : []),
        ...(busy().length ? [{ ...bind("pet.l.cat"), run: cheer((name) => r.catLetter(name)) }] : []),
        ctl.back1,
      ],
    }
  }
  return {
    title: (app.petsNow ?? resolvePets(loadPets())).dog.name.toUpperCase(), rows: [{ segs: [plain(wideRoom ? "the office dog. good boy." : "the dog lives in the wide room — make the terminal wider to see him.")] }],
    actions: wideRoom ? [
      { ...bind("pet.p.dog"), run: doIt(() => wideRoom.patDog()) },
      { ...bind("pet.w.dog"), run: doIt(() => wideRoom.dogDo("walk")) },
      { ...bind("pet.o.dog"), run: doIt(() => wideRoom.dogDo("office")) },
      { ...bind("pet.s.dog"), run: doIt(() => wideRoom.dogDo("sit")) },
      { ...bind("pet.b.dog"), run: doIt(() => wideRoom.dogDo("bed")) },
      ...(busy().length ? [{ ...bind("pet.g.dog"), run: cheer((name) => wideRoom.dogCheer(name)) }] : []),
      ctl.back1,
    ] : [ctl.back1],
  }
}
