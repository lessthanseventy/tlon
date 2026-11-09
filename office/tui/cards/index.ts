import type { Card, State } from "../state"
import { view } from "../select"
import { arcadeCard, babelCard, banterCard, helpCard, homeCard, ideasCard, playCard, trophiesCard } from "./home"
import { crewCard, personCard } from "./crew"
import { threadCard } from "./thread"
import { columnCard, epicCard, ticketCard } from "./ticket"
import { calendarCard, lifeCard, pagesCard, runCard, runsCard } from "./schedule"
import { archiveCard, buildCard, memoryCard, notesCard, trayCard } from "./shelf"
import { decideCard, issueCard, needsCard, triageCard } from "./needs"
import { entryCard, healthCard } from "./release"
import { bossCard, settingsCard, whimsyCard, workspaceCard } from "./workspace"
import { reviewCard } from "./review"
import { petCard } from "./pet"
import { lookCard, lookEditorCard } from "./look"
import { castCard } from "./cast"
import { hallCard, hallPileCard } from "./hall"
import { storeCard } from "./store"
import type { Ctl } from "../ctl"

/** the card the pane shows: its title, its rows (the left, j/k + enter when any open), its actions (the right, by key) */
export function detail(app: State, ctl: Ctl): Card {
  const a = view(app)
  switch (app.mode.kind) {
    case "home": return homeCard(app, ctl, a)
    case "crew": return crewCard(app, ctl, a)
    case "person": return personCard(app, ctl, a, app.mode)
    case "thread": return threadCard(app, ctl, app.mode)
    case "column": return columnCard(app, ctl, a, app.mode)
    case "epic": return epicCard(app, ctl, a, app.mode)
    case "ticket": return ticketCard(app, ctl, a, app.mode)
    case "calendar": return calendarCard(app, ctl)
    case "life": return lifeCard(app, ctl)
    case "pages": return pagesCard(app, ctl)
    case "runs": return runsCard(app, ctl, app.mode)
    case "run": return runCard(app, ctl, app.mode)
    case "archive": return archiveCard(app, ctl)
    case "notes": return notesCard(app, ctl, a)
    case "tray": return trayCard(app, ctl)
    case "triage": return triageCard(app, ctl)
    case "issue": return issueCard(app, ctl, app.mode)
    case "health": return healthCard(app, ctl)
    case "memory": return memoryCard(app, ctl)
    case "build": return buildCard(app, ctl)
    case "boss": return bossCard(app, ctl)
    case "card": return workspaceCard(app, ctl)
    case "review": return reviewCard(app, ctl, app.mode)
    case "whimsy": return whimsyCard(app, ctl)
    case "settings": return settingsCard(app, ctl)
    case "needs": return needsCard(app, ctl)
    case "babel": return babelCard(app, ctl, app.mode)
    case "entry": return entryCard(app, ctl, a)
    case "decide": return decideCard(app, ctl, app.mode)
    case "ideas": return ideasCard(app, ctl, a)
    case "banter": return banterCard(app, ctl, a)
    case "trophies": return trophiesCard(app, ctl)
    case "arcade": return arcadeCard(app, ctl)
    case "play": return playCard(app, ctl, app.mode)
    case "pet": return petCard(app, ctl, app.mode)
    case "look": return lookCard(app, ctl, app.mode)
    case "cast": return castCard(app, ctl, a, app.mode)
    case "hall": return hallCard(app, ctl)
    case "store": return storeCard(app, ctl)
    case "hall-pile": return hallPileCard(app, ctl)
    case "help": return helpCard(app, ctl, app.mode)
    case "look-editor": return lookEditorCard(app, app.mode)
  }
}
