import { previewOf, resolvePets, slotOf } from "../../kit/pets"
import { hallSignature } from "../../kit/hall"
import { adopt, back as storeBack, candidateOf as storeCandidate, pass as storePass, rename, saveStore, shelve, toggleLock as storeToggle, type Store } from "../../kit/store"
import { adoptAsk, storeRows } from "../store"
import { bind } from "../keys"
import { loadPets, savePets } from "../pets"
import { STORE, type Row, type Card } from "../state"
import { storeTaken } from "../select"
import type { State } from "../state"
import type { Ctl } from "../ctl"

export function storeSet(app: State, s: Store) { app.store = s; saveStore(STORE, s); app.storeSeen = hallSignature(STORE) }

/** ⏎: adopt the shown candidate into its slot; the occupant leaves by the door, once the operator says y */
export function storeAdopt(app: State, ctl: Ctl) {
  const taken = storeTaken(app), c = storeCandidate(app.store, taken), slot = slotOf(c.species)
  const file = slot ? adopt(c, slot) : null
  if (!slot || !file) { app.status = `${c.name} can't be adopted here`; return ctl.draw() }
  const old = (app.petsNow ?? resolvePets(loadPets()))[slot].name
  ctl.ask2(adoptAsk(old, c.name), () => {
    savePets(file)
    app.petsSeen = ""; ctl.followPets(); app.roomChanged = true
    storeSet(app, storePass(app.store, [...taken, c.name]))
    app.status = `adopted ${c.name}`
    ctl.draw()
  })
}

export function storeCard(app: State, ctl: Ctl): Card {
  const taken = storeTaken(app), c = storeCandidate(app.store, taken), slot = slotOf(c.species) ?? "cat"
  const occupant = (app.petsNow ?? resolvePets(loadPets()))[slot]
  const rows: Row[] = storeRows(c, app.store.locks, occupant.name, previewOf({ name: c.name, species: c.species, temperament: c.temperament }, app.previewTick).line).map((r) => ({
    segs: r.segs,
    open: r.lock ? () => { storeSet(app, storeToggle(app.store, r.lock!)); ctl.draw() } : undefined,
  }))
  return {
    title: `PET STORE · ${app.store.seed}`, rows,
    actions: [
      { ...bind("store.left"), run: () => { storeSet(app, shelve(app.store, -1, storeTaken(app))); ctl.draw() } },
      { ...bind("store.right"), run: () => { storeSet(app, shelve(app.store, 1, storeTaken(app))); ctl.draw() } },
      { ...bind("store.up"), run: () => { storeSet(app, storePass(app.store, storeTaken(app))); ctl.draw() } },
      { ...bind("store.down"), run: () => { storeSet(app, storeBack(app.store, storeTaken(app))); ctl.draw() } },
      { ...bind("store.space"), run: () => rows[app.sel]?.open?.() },
      { ...bind("store.e"), run: () => ctl.ask("name", (s) => { if (s.trim()) { storeSet(app, rename(app.store, s.trim())); ctl.draw() } }, { text: c.name }) },
      { ...bind("store.enter"), run: () => storeAdopt(app, ctl) },
      ctl.back1,
    ],
  }
}
