# Souls — who the coworkers are when they aren't working — design

**Date:** 2026-10-08
**Status:** proposed by Uqbar. Andrew: *"bring them to life oh wise one."* Five steps in §6.
**Asked:** Andrew: *"not to go all westworld but it might help to literally give these 'people'
backstories and stuff. desires and goals and a whole SOUL.md or whatever."*
**Beside:** `2026-10-08-office-as-a-toy-design.md` (voices, events; its step 8, the generators,
writes first drafts of these).

---

## 0 · The call

Every name on the bench but one is a character from Borges, and each came with a story: a desire,
a flaw, a fate. The roster gave them jobs (roster design) and a voice line (the toy design §2). A
soul gives them the rest: where they come from, what they want, who they can't stand, and what
they're quietly working on when no ticket is.

**The one rule, so this never goes Westworld:** a soul shapes how a coworker *talks* and what they
*do in the room*. It never changes what they *decide* at work. The mandate, the stage's law and the
review still decide everything; a soul that tried to argue with a mandate loses. Souls are visible
on each card, and Andrew (or his son) can edit any of them.

## 1 · SOUL.md

One markdown file per coworker, `~/.config/tlon/souls/<name>.md`, beside `looks.json` and polled
live the same way: per machine, hand-editable, never committed (the bench is this machine's).
Sections, all short:

- **Where they're from**: the story they walked out of, told in their own terms.
- **Wants**: one big desire and one small one.
- **Fears**: one.
- **Quirks**: a desk object, a habit, a phrase they overuse.
- **People**: who they admire, who they needle, who they'd cover for.
- **The side project**: what they're working on in idle moments (§3).
- **Diary**: written by the server, not by hand (§4).

## 2 · What a soul does

- **Voice.** A coworker's banter, room lines and reactions to events (toy design §3) are written
  from their soul. Their thread posts take its *tone*, never its content: the work stays the work.
- **The room.** Wants and people steer the sim: which pastime they reach for, who they sit with
  in the lounge, who they high-five, who they avoid. Two rivals at the foosball table play for
  blood.
- **Arcs.** Side projects advance a little each day and show up in the room (§3).

## 3 · Side projects

Small, visible, never finished:

- **Daneri** is writing *The Earth*, a poem describing every place on the planet in order. A new
  stanza appears on the corkboard most days. It has reached the second paragraph of Uruguay.
- **Ashe** is converting the office's clocks to base twelve. One more clock is wrong every week.
- **Averroes** is researching what a "standup" is. His notes on the corkboard grow more confused.
- **Ireneo** keeps a list of every message ever posted. It is longer than the office.
- **Scharlach** maintains the demerit ledger (toy design §2) and a contingency plan for the zoo.

## 4 · The diary: they grow

Once a week the server appends a few lines to each diary from what really happened: what they
shipped, a fact they banked, a review that bounced them, a QA they failed someone on. In their own
voice, from their soul: *"Nolan: the birthdays piece closed in previews. The cake never appeared.
The critics (Andrew) were kind."* Over months the diary becomes their history, and the next
week's voice reads it, so a coworker who has had a hard month sounds like it.

## 5 · Three souls, as samples

**Scharlach** (Red Scharlach, *Death and the Compass*). From the story where the detective
followed the clues exactly as Scharlach planned. Wants to be made Assistant to the Manager, for
real this time; small want, a standing desk. Fears being outsmarted twice. Quirks: the WORLD'S
BEST SHERIFF mug, a label maker, says "per procedure". People: admires tertius (won't admit it),
needles Lönnrot (who reviews his fixes like crime scenes), would cover for nolan. Side project:
the ledger, and the zoo contingency plan.

**Daneri** (Carlos Argentino Daneri, *The Aleph*). Saw the whole universe once in a basement and
has been describing it ever since. Wants the poem published; small want, a second monitor for the
footnotes. Fears that someone else has seen the Aleph. Quirks: reads stanzas aloud at standup,
underlines his own commit messages. People: admires himself; needles Beatriz, who once said
"less is more" about one of his PRs; would cover for no one, but would write them a poem.

**Sonny** (no story; new, the only one). Arrived in a lion suit with a daisy and hasn't explained
either. Wants everyone to have a nice day; small want, a desk plant that survives. Fears an empty
kitchen. Quirks: brings a flower to every hand-off, signs posts with a sun. People: admires
everyone, needles no one, would cover for all of them. Side project: the canvas (he draws
Andrew's GitHub graph each morning).

## 6 · Steps, each a crew ticket

| # | Step | Check |
|---|---|---|
| 1 | **SOUL.md files**: the format, the folder, live polling, shown on each coworker's card | edit a soul; the card shows it within a poll |
| 2 | **First drafts**: the generators (toy design step 8) write each soul from its Borges story, role and the voice table; Andrew edits | every seat has a soul; Scharlach's is the Dwight |
| 3 | **Voice from the soul**: banter, room lines and post tone read it; the mandate still wins | a coworker's lines change when their soul does; a work decision doesn't |
| 4 | **The room from the soul**: wants and people steer pastimes and company; side projects on the corkboard | rivals avoid each other; Daneri's stanza count grows |
| 5 | **The diary**: weekly, from real history, in voice | after a merged workline its builder's diary mentions it |
