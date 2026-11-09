import type { Act } from "../kit/crew"
import type { RailRoom } from "../rooms/rail"
import type { WideRoom } from "../rooms/wide"
import type { State as WhimState } from "../kit/whimsy"
import type { ReaderDeps } from "./reader"
import type { Action, Card, Cycle, Mode, Pick, Prompt } from "./state"

/** what a card may do to the app: the operations that stay with the screen */
export type Ctl = {
  open: (m: Mode) => void
  back: (everything?: boolean) => void
  act: (x: Act) => void
  ask: (label: string, submit: Prompt["submit"], opts?: { multiline?: boolean; text?: string; cycles?: Cycle[] }) => void
  ask2: (label: string, run: () => void) => void
  did: (p: Promise<string>) => Promise<void>
  draw: () => void
  detail: () => Card
  resort: (step: () => void) => void
  refresh: () => Promise<void>
  loadCard: () => Promise<void>
  find: (title: string, items: Pick[]) => void
  room: () => RailRoom | WideRoom
  back1: Action
  hire: () => void
  talk: (to: string | null) => void
  reply: (tid: number) => void
  newThread: () => void
  newTicket: () => void
  newNote: () => void
  finder: () => Promise<void>
  inbox: () => void
  quit: () => void
  goThread: (id: number, wsId: number | null | undefined) => void
  goWs: (id: number) => void
  openReader: (tid: number, extra?: Partial<ReaderDeps>, focus?: boolean) => void
  closeReader: () => void
  openConversation: (name: string) => void
  openBabel: () => void
  openDump: () => Promise<void>
  openSoul: (name: string) => void
  readPage: (id: number) => Promise<void>
  restorePage: (id: number) => Promise<void>
  zoomInto: (tid: number) => Promise<void>
  zoomGit: (tid: number) => Promise<void>
  pickDoc: (tid: number) => Promise<void>
  play: (g: { name: string; cmd: string; what: string }) => void
  playDo: (id: string) => void
  setWhim: (s: WhimState) => void
  followPets: () => boolean
}
