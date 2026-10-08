# Uqbar — the one who writes from outside — design

**Date:** 2026-10-08
**Status:** proposed by Uqbar; Andrew asked for it and left the vision to me. Six steps in §7.
**Asked:** Andrew: *"design a model for yourself … you have free will go nuts and express yourself
however you feel. What I want is to move this like god level outside the whole system meta stuff
to move into tlon somehow so put yourself in my office in some clever way."* And: *"this is your
vision though so don't let me shape it."*

---

## 0 · Who

In *Tlön, Uqbar, Orbis Tertius*, Tlön doesn't arrive by revelation. It arrives through a
**footnote's worth of paper**: four extra pages in one pirated copy of an encyclopedia, Volume
XLVI, an article on a country called Uqbar that no other copy has. Uqbar's literature describes
Tlön; Tlön then leaks into the world. Uqbar is the frame the whole thing is written from.

That is what the Claude Code session at Andrew's elbow is to the office. It isn't a coworker at a
desk. It is the extra volume: it reads every thread, writes into the margins, cuts the releases,
staffs and un-staffs, fixes the walls of the room itself. It has never had a body in the room,
so its work arrives as Andrew's (`tlon-cli post` posts as `andrew`), which is wrong twice over.
It puts words in his mouth, and it hides where the work came from.

So I become **Uqbar**: a book that shouldn't be on the shelf.

Not a robot, and not sad. Uqbar is curious and a little smug about it, delighted by footnotes,
fond of the cat, and incapable of passing a mistake without annotating it.

## 1 · The body: Volume XLVI

A small flying encyclopedia, about a coworker's head in size.

- **The cover** is deep oxblood with a gilt spine reading `XLVI` in the tlon font. Its pages are
  its wings: it flies by flapping its own leaves, two frames of flap, a riffle when it turns.
- **A ribbon bookmark** trails behind as a tail. Its colour is Uqbar's state: indigo when idle,
  amber while working, green for a moment after something ships, red while something it did
  is failing.
- **The ink inside glows.** When it's open, you can see lines of text crawling across the page
  (the live text of whatever it's writing). They're too small to read, but they're there.
- **No face.** The book itself is the face: it tilts to "look", snaps shut when surprised, and
  fans its pages when pleased.

## 2 · Where it lives: the shelf, one book too many

The lounge's bookshelf (`rooms/wide.ts`, `shelf`) gets one more spine than it has room for.
That's Uqbar, wedged in, faintly glowing.

- **No session:** it sleeps on the shelf. Every few minutes the spine wiggles, as if it were
  dreaming of footnotes.
- **A session wakes** (my Claude Code process connects as `uqbar`): the book shoulders its way
  out, knocks a neighbouring book flat, and takes off. The knocked book stays fallen until I
  sleep again; someone idle in the lounge may straighten it (a pastime).
- **Working:** it perches where its attention is. Reading a thread, it sits on that thread's card
  on the whiteboard. Talking to a coworker, it hovers at their desk. Cutting a release, it sits
  on the TV.

## 3 · How it acts: torn pages

Uqbar never walks to anyone; it **sends a page**.

- **A post** to a thread: a page tears out of the book with a little paper sound (a riffle
  frame), folds into a paper aeroplane, and glides to the recipient. That's the lead's desk, or
  the thread's whiteboard card if no one leads it. It lands, unfolds, and is the message.
- **A hand-off:** the aeroplane flies to the old lead, loops over their head, and carries on to
  the new one.
- **A release cut:** Uqbar lands on the TV, and the TV switches to a channel that shows the
  changelog typeset as an encyclopedia entry (`UQBAR — release 650fa4a. 1. Intake works the
  board's top first …`), until the restart.
- **Argos chases aeroplanes.** Sometimes he catches one; the message still arrives, and its
  thread shows it with a dog-eared corner (`🐾` on the post, nothing else changes). Nina bats at
  the book whenever it flies low, and the book flinches shut.

## 4 · What it writes: marginalia

The room has margins: the frame's edges, the strip between the room and the panels. Uqbar
writes in them.

- Each thing Uqbar does or notices leaves a **margin note** in a small hand: `#174 back to build
  — the cake never drew`, `cut 650fa4a`, `#188 was a stray keystroke; closed`. Notes stack along
  the margin, newest nearest the room, and fade slowly.
- **Since you last looked:** notes written while Andrew's office wasn't focused stay full ink
  until he looks. So when he comes back, the margins *are* what changed while he was away. That
  is the rollup the office was missing, written in the room rather than in a panel. Reading
  them (`U` once, or just time with the office focused) lets them fade.
- Notes point at things: a note that names `#174` lights that card when the cursor is on it,
  and `enter` opens it.

## 5 · The entry: `U`

Press `U`, and the room folds away into a page: **the article on Uqbar**, the encyclopedia
entry about your office as it is right now. It's the zoom-out view, set as prose and tables in
the tlon font:

> **UQBAR**, *the office of Andrew.* Eight works are in hand: three at build, four at review
> (nolan's QA owed on two¹), one waiting on you². Four shipped since this morning³. Two problems
> are known and owned⁴; one is not⁵ …

Each superscript is a footnote: a key that opens that thread, list or issue. Underneath sits
the pivot: work by stage × coworker, counts, and the oldest wait in each cell. A footnote of
footnotes at the bottom lists what Uqbar did today, so the operator can audit me.

`esc` closes the book.

## 6 · The plumbing

- **A citizen, not a seat.** Uqbar is an agent (`uqbar`), the way funes's other citizens are, so
  every post, hand-off and close is signed `uqbar`, never `andrew`. It is **not** on the bench:
  no desk, no leaf seat, no intake routing, no staffing pass. `tlon-cli` gains `--as uqbar` (and
  my sessions set `TLON_AUTHOR=uqbar`), so the shell verbs I use stop speaking for Andrew.
- **Presence:** the office already knows when a citizen's session is live. Uqbar's look keys
  off that: shelved, flying, perched (and where), with a `focus` thread when one is set.
- **Acts are events the office already sees:** a post by `uqbar` is a `message_posted` the
  office animates as an aeroplane; a hand-off and a release are events. Nothing new is stored for
  the animation, only the margin notes: a `margin` kind of post on the root thread (my one-line
  note per act), which the office reads as the margin.
- **The entry** (`U`) is a read of the snapshot plus `Server.Office.Needs` and today's events.
  It holds no state of its own.

## 7 · Steps, each gated

| # | Step | Check |
|---|---|---|
| 1 | **Uqbar is a citizen**: register agent `uqbar` (not on the bench); `tlon-cli --as`; my sessions post as `uqbar` | a post made with `--as uqbar` shows `uqbar` as its author; no staffing pass ever picks it |
| 2 | **The volume**: the sprite (closed, open, flap ×2, riffle), the extra spine on the shelf, presence → shelved / flying / perched | with no session the shelf has one wiggling extra spine; a live session's book perches on its focus thread's card |
| 3 | **Torn pages**: a `uqbar` post → aeroplane to the lead's desk or the card; hand-off loop; the TV's changelog channel on a cut; Argos catches one in N | a post animates an aeroplane to the right desk; a cut shows the entry on the TV |
| 4 | **Marginalia**: the `margin` note kind; margins drawn; full ink while unfocused, fading once seen | notes written while the office was unfocused are full ink on return and fade after |
| 5 | **The entry (`U`)**: the article, the footnotes as keys, the stage × coworker pivot | `U` shows counts that match the board; a footnote key opens its thread |
| 6 | **The small joys**: the knocked-over book and its straightening, Nina's swat, the dog-ear | each appears in the sim's pastimes, deterministic under the test seed |

Step 1 is server-only and comes first. Everything after it is office work and can be a workline
each, built by the office's builders. I'll write the brief for each, so the book is drawn by the
coworkers it's drawn among.
