# The office as a toy — Dwight, hijinks, a bathroom, a doorbell, and a sandbox — design

**Date:** 2026-10-08
**Status:** proposed by Uqbar from ideas by Andrew's son, who asked for most of what is good here.
Steps 1, 3, 4, 5 are built; 2, 6, 7, 8 are partial or in flight (status in §8), each a crew ticket.
**Asked:** Andrew, relaying his son: *"a dwight type character … distinct personalities in their
interactions and responses … hijinxy type things to happen … monkeys and animals breaking out of the
zoo and rampaging the office, or an asteroid blowing things up … a bathroom … nina to go in and drink
out of the bathtub and … when her paws get wet she should track water for awhile and leave little
pawprints … a front door and a doorbell that people will stop by sometimes."* And: *"I think … I have
built maybe the worlds greatest desk toy. an ai fish tank … maybe there's a sandbox mode that doesn't
have any of the workflow stuff and is just a literal toy where you can play around."*

---

## 0 · The call

He's right: the office is a fish tank whose fish happen to do the work. Two dials make that a
choice instead of an accident:

- **Mode**: `office` (today: the work, with the room drawn over it) or `sandbox` (the room alone,
  a toy: no server, no workflow, nothing staffed, everything pokeable).
- **Whimsy**: `off`, `some` (today's level), or `lots` (the events in §3 come round often).

Everything below works in both modes. In `office` it never gets in the way of the work: an event
never touches a thread, a ticket or a turn. It's weather, not a fault.

## 1 · Sandbox mode

`mise run office:sandbox` (the binary: `office --sandbox`) starts the TUI against a **made-up
world** instead of the server: the bench from `looks.json`, a few pretend threads on the
whiteboard, the pets, the weather. No server process is needed, so it runs on a laptop with
nothing else installed: the toy you hand a kid.

What you can do in it, one key each, shown on the help line:

- `d` ring the doorbell (§5); `e` start an event (§3); `t` drop a treat (the pets come running);
- `f` a fire drill (§2); `n` night falls; `w` change the weather;
- `p` pet whoever's under the cursor; `c` call a coworker over to the cursor.

The sim is the same code as the office's (`kit/sim.ts`); sandbox only swaps where the snapshot
comes from (`tui/data.ts` gets a fake source), so whatever the toy grows, the office gets.

## 2 · Personalities, and the Dwight

The roster already reserves a **temperament** per seat, voice only (roster design §5, dollhouse
§9), and the pets already have voice packs (`kit/voices.ts`). This step gives every coworker one:
how they phrase a post, what they mutter in the room, and how they react to an event (§3). They
still do their jobs exactly as before. The voice is presentation, never a different decision.

**The Dwight is Scharlach, the sheriff.** He already enforces the rules, so he was always going to
be the one who enjoys it too much:

- His nameplate says **Sheriff (Assistant to the Manager)**. tertius has never agreed to the
  second part.
- He keeps a **demerit ledger** on his desk, one tally per coworker, and it ticks up when a
  build of theirs goes red. Nobody knows what demerits are for. He does.
- He calls **surprise fire drills** (one key in sandbox, now and then in `office` at `lots`):
  everyone files out of the front door to the street and back; Nina refuses and stays on the
  radiator; Argos thinks it's a walk.
- His mug says WORLD'S BEST SHERIFF. He bought it himself.
- His posts are crisp and slightly too formal: *"Issue #8 resolved. I have noted the delay."*

Every other coworker gets a voice in the same pass. One line each, set on the seat:

| Seat | Voice |
|---|---|
| tertius | dry, unflappable, has seen it all |
| hronir | old-school; mutters about how it was done before |
| lonnrot | a detective; reviews read like case notes |
| yu | careful, precise, a little anxious |
| beatriz | brisk, organized, has a spreadsheet for this |
| nolan | theatrical; QA is "the performance" |
| emma | quietly determined; finishes what she starts |
| ireneo | remembers everything, says so |
| daneri | grandiose; every change is a masterpiece |
| sonny | sunny; brings a flower to every handoff |

## 3 · Hijinks: the events

Rare, harmless, and funny, with the cast reacting in voice. None of them touch the work. Each is a
little scripted scene in the sim that runs for a minute or two and then tidies itself away.

- **The zoo's open day.** A monkey swings in through the window on the light fittings, a penguin
  waddles the length of the lounge, and a goat eats a sticky note off the corkboard. Scharlach
  gives chase with a butterfly net; Nina watches from the top of the fridge; Argos is beside
  himself with joy. A van marked ZOO pulls up outside and they're rounded up out of the front door.
- **The meteor.** A tiny asteroid streaks past the window and lands in the street with a puff of
  smoke: a small crater, gone by morning. The lights flicker, everyone rushes to the window, and
  one coworker blames the last deploy. (Nothing blows up. The crater is the joke.)
- **The fire drill** (§2), Scharlach's.
- **The power cut.** The lamps go out, the screens glow, someone lights a candle, and the lights
  come back on to applause.
- **A duck.** One duck walks in, looks around, and leaves. That's the whole event.

The wackiness dial (§7) sets how often: `never`, `rare`, `some` (the default) or `lots`, in a mean gap
of open-hours ticks; the room starts one on its own only inside open hours. Sandbox's `e` starts one now,
unless every event is switched off.

## 4 · The bathroom

A small room off the hallway: a sink, a toilet with the lid down, and a clawfoot bathtub with a
dripping tap. Coworkers go in now and then (a pastime) and come back out, and the door closes
behind them.

**Nina and the bathtub**, exactly as asked: now and then she trots in, hops onto the rim, and
drinks from the tub. When she comes out her paws are wet, and for a while every step leaves a
little **pawprint** on the floor tiles. The prints fade one by one over a minute or so. Argos
sometimes follows the trail sniffing it. Rarely, she falls in (a splash, an offended cat, a much
longer trail).

## 5 · The front door and the doorbell

A front door on the street side of the office, with a doorbell. Now and then it rings (`d` in
sandbox), someone gets up to answer, and a visitor stands in the doorway for a moment:

- **the mail carrier**, with letters for the mailbox (the mailbox ticket's errand, #185);
- **a pizza delivery** when a release ships: the release is literally delivered, and the crew
  gathers in the kitchen;
- **a neighbour's kid selling cookies** (the crew always buys some);
- **a lost tourist** asking for directions to Uqbar. Nobody knows where it is. The book on the
  lounge shelf (Uqbar design §2) wiggles;
- and on special days, whoever fits the day: a trick-or-treater, a carol singer.

## 6 · The canvas, while we're here

The contribution-graph canvas (`Server.Canvas`, the crew draws Andrew's GitHub graph) takes the
same humour: Sonny's brief says holidays get their picture (an egg at Easter, a pumpkin at
Halloween, a tree in December), and puns and nerdy jokes are welcome. That's a brief, not a step.

## 7 · Configuration

One file, `office.json` in the config dir, edited on the wackiness card (finder: "the wackiness dial", or `Z`
on the settings card): `mode` (`office` | `sandbox`), one **preset**, and per-dial **overrides**. Choosing a
preset sets the dials; touching a dial keeps the preset and shows it as `(custom)`. Defaults: `office`,
`casual`, no overrides, everything on.

| preset | banter | events | chain | severity | pets | doorbell | moods | souls |
|---|---|---|---|---|---|---|---|---|
| `business` | off | never | no | 1 | asleep | off | no | off |
| `casual` (default) | on | some | no | 1 | on | normal | no | on (#478, unmerged) |
| `party` | on | lots | no | 2 | on | busy | no | on |
| `rimworld` | on | lots | yes | 3 | on | busy | a red build sours the afternoon | on |

The dials under a preset: `banter`, `frequency`, `severity`, `chain`, per-event toggles, `pets`,
`doorbell`, `moods`, `souls` and `weirdness`. `souls` off: the sim ignores the souls' People sections (no
friends, no rivals) and a pair's small talk is the canned seat voice, not a model line written from the souls.
`weirdness` past `curated`: the door also draws the server's generated visitors, puns say a groan after a
visit, and a seat's generated reaction lines replace the scripted ones at an event (`GET /api/office/toys/:ws`,
`Server.ToyPool`; empty until generated). A toggled-off event never plays, keyed or not.

**The one rule at every setting: the work is never touched.** The dials gate the room's own behaviour;
nothing here reads or writes a thread, ticket, turn or code (`test/whimsy-work-untouched.test.ts`).

## 8 · Steps, each a crew ticket

| # | Step | Check |
|---|---|---|
| 1 | **Sandbox mode**: a fake snapshot source in `tui/data.ts`, `office:sandbox`, the play keys | the TUI runs with no server; each key does what §1 says — built; `Sim.play` is the stand-in steps 3–5 replace |
| 2 | **Voices**: a voice per seat (posts and room lines), the §2 table; Scharlach's nameplate, ledger and mug | each seat's banter reads in its voice; the ledger ticks on a red build — partial: voices are built; the nameplate and mug are drawn by #448 (unmerged); the ledger is open |
| 3 | **The bathroom**: the room, its pastime, Nina drinking from the tub, fading pawprints | Nina's trip leaves prints that fade; deterministic under the test seed — built |
| 4 | **Front door and doorbell**: the door, the bell, the visitors in §5 | a ring brings a coworker to the door and a visitor in it; a cut brings pizza — built |
| 5 | **Events**: the zoo, the meteor, the fire drill, the power cut, the duck | each plays and tidies itself; none touches a thread or a turn — built |
| 6 | **The wackiness dial** (preset + dials + toggles, `office.json`) | `business` plays no event and no banter; `rimworld` chains events; a dial overridden under a preset holds; a toggled-off event never plays — built; the `souls` and `weirdness` dials are wired by #475 and the casual preset keeps souls on in #478 (both unmerged) |
| 7 | **The rest of the cast's room reactions** to events, in voice | every seat reacts to each event in its own way — in flight: scripted lines exist; pooled generated reactions land with #475 (unmerged) |
| 8 | **Generators**: personas per seat, and pools of visitors, reactions and puns, on cheap model calls (`Server.Persona`, `Server.ToyPool`) | a hired seat gets a persona; `--reroll` records a new seed; the room renders with the model off — partial: the person card shows the persona, `E` makes, rerolls and edits it; the pools reach the room through `GET /api/office/toys/:ws` (#456, #475, unmerged); pools of puns are open |
