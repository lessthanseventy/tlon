# The house's orchestrator

The human, 2026-11-22: "i want this whole orchestrator concept in asterion too kinda. just trying to
AIify my life i suppose".

arena's orchestrator (arena `docs/orchestrator.md`, #500) is one front door for work: it knows what
needs you, proposes actions you settle with go or no, asks only when it is your call, and hears you
from anywhere. This is the same shape for everything else, inside Asterion. It is a separate system
(#14): nothing personal goes on babylon's board, the house never sees a ticket, and the two never
share a channel, a count or a hotkey. They share words, so the two front doors read alike.

Held to arena's `docs/principles.md`, above all rule 8: only decisions interrupt.

## Words

The same words as arena, each with one meaning in both:

| word | in the house |
| --- | --- |
| **needs you** (`▲ N`) | the count of items that are the person's move, and nothing else |
| **your move** | the list of those items: asks, proposals and look-ats, each settled in place |
| **ask** | a question from the house to the person: numbered options, or an answer in words; open until answered |
| **proposal** | one suggested action, what then why, settled with **go** (it runs) or **no** (it is dropped for good) |
| **look at** | an ask that opens something to read, settled with **looks good** or **change** |
| **notice** | a desktop or phone message, raised only for a new ask or proposal, once |
| **tell** | a line from the person to the house, as their word |

Two words the house already uses differently:

- **Money's "Ask about your money"** is the person asking the house, which is a tell. It
  becomes the chat (below), so in the house "ask" means only the house asking you.
- **Money's "Noticed" rows** are things seen in the bank, not notices. They stay where they are and
  are not your move. The heading is the one place left where the word means something else. It is
  open to rename (see the end).

A ringing reminder is not your move: it already has its ring, its banner and its buttons. A to-do is
not your move either: it is the list. `▲ N` stays small because it counts only what waits on a
decision.

## What it is, in one line

**The house is the orchestrator.** There is no new character or pane. Code keeps a list of your
moves from the sources, Home shows it first, the chat is where you talk to it, and Telegram and a
desktop notice carry a new item to you when you are not looking. It runs in Asterion's own process,
in background mode too, and it works with no model at all.

## 1. What needs you

There is one list across sources, built by code from rules. The model never adds to it.

| source | becomes | example |
| --- | --- | --- |
| money: a bill due before the next deposit, and available short of it | proposal | Move $120 from savings by Thu · rent $1,200 is due Fri and checking has $1,080 |
| money: a new recurring charge, or one that rose | ask | Spotify is $13.99 now, was $11.99. 1 keep it · 2 remind me to cancel · 3 it isn't a bill |
| list: a waiting-on past its date | proposal | Nudge Sam about the invoice · waiting since Tue |
| list: a to-do untouched for 14 days | proposal | Put "Renew passport" on someday · open since 3 Nov, never moved |
| mail (#314, if it is built): a mail that wants a reply | proposal | Reply to Dana about Saturday · she asked a question on Wed |
| money, weekly (#510): where it went | look at | This week's money · opens Money |

**Order:** asks first, then proposals and look-ats by their date, soonest first. Inside the same
date, the oldest comes first. Each item is one line, with its why small under it, as Home's Proposed
rows are today.

**Limits that keep it small:**

- At most five new items a day across every source. The rest wait for the next day, ranked by date.
- A **no** is final for that item's key: the same rent on the same date, the same waiting-on. The
  next month's rent is a new key.
- An answer is kept as a fact (`Flex is rent`). The house never asks the same thing twice.
- An item whose cause is gone takes itself back, quietly: the money arrived, or the waiting-on was
  ticked.

## 2. Proposals: what go does

**Go only ever changes the house's own list, or opens a link.** The bank link is read-only (Plaid,
`bank_plaid.gd`) and stays so. The house sends no mail and messages no one but its own person. So
every action is one of a closed set, run by code:

| go does | for |
| --- | --- |
| add a to-do, a reminder or a waiting-on, its text and time given | "move $120 by Thu" is a reminder Wed 18:00; "nudge Sam" is a to-do today; "reply to Dana" is a to-do with the mail's link |
| move a thing to someday, or to a day | a stale to-do |
| record an answer as a fact | an ask |
| open a link in the browser | look at, a mail, the bank's own site |

**What it does on its own, with no go:** it reads its sources, computes, keeps its own file, words
its items and sends the person's own Telegram the day's card and notices. It never ticks, deletes or
moves a thing, never changes a reminder, never moves money and never sends anything to anyone else.

"Remind someone" is therefore a to-do for you, with the message drafted in its text. The house
never writes to Robyn.

## 3. When it asks instead of proposing

It proposes when there is one clear action that most people would take, and **no** costs nothing.
It asks when:

- the right action depends on something only you know (is this charge a bill? is Flex rent?), or
- there are two reasonable ways out and they differ in kind: the rent is short, and savings cover
  it, but so would skipping a bill. Then the ask lists both, numbered, and "something else" opens
  the chat.

It never asks what it can work out, and never asks something already answered. At most two asks are
open at once. A third waits.

## 4. Talking to it

**In the window: the chat is the orchestrator.** Every line goes through `main.gd` `_tell`, as
today: the reader files it, or answers it. The chat gains three things:

- **Questions get answers from the house's state.** A money question goes to the money engine
  (`ask.gd`: a model plans, code computes, the model phrases). Money's own ask line goes, and the
  Money view says "ask in the chat". A question about the list ("what's left this week") is answered
  from the list.
- **Items can be settled in words.** "go", "no to the Spotify one", "2". A line that settles the item
  shown last does so. One that names no item is read as a tell, as before.
- **A new item is said in the chat once**, as a house line with its buttons, the way a told
  reminder is today.

**Away from the computer: Telegram**, which already exists. The day's card gets a "Your move" block,
lettered, with go and no (it absorbs #325's Proposed design). A new urgent item is its own message.

**From the desktop: one hotkey, `Super+Shift+U`.** It opens a one-line prompt, and the line goes to
the running house as a tell: `asterion --tell "<line>"`, through the one-house handshake that
`--background` already uses (a second launch drops a file the running house reads and quits). The
reply is a desktop notice, and it also lands in the chat.

I recommend the separate key and **not a prefix on `Super+U`**. A forgotten prefix would put a
personal line on the work board, which is exactly what #14 forbids. Two keys fail safe: the worst a
slip does is send a line to the wrong place by your own hand, never by a parser's guess. The
operator's bar keeps showing work's `▲ N` only. The house's count stays in the house and its tray
tooltip, so the two numbers never mix.

`--tell` is a command, so a script can say anything a click can (principles, rule 7). The family's
Macs and Windows machines get no hotkey. Their from-anywhere is Telegram.

```
 ┌ Super+Shift+U ───────────────────────────────────┐
 │ › remind me to call the dentist tomorrow 9       │
 └──────────────────────────────────────────────────┘
        ↓ asterion --tell
 ╭ Asterion ────────────────────────────────────────╮
 │ Reminder: call the dentist, tomorrow 09:00       │
 ╰──────────────────────────────────────────────────╯
```

## 5. Notices

A notice is raised only for a **new** ask or proposal, once, and only when:

- the item has a date within the next 48 hours, or it is about money short before the next deposit.
  Anything else waits for the day's card, unannounced;
- the window is not in front. With the window in front, the chat line is enough;
- it is outside quiet hours: from the evening card's time to the morning card's, nothing is raised.
  It waits for the morning card. Ringing reminders keep their own rules.

**Where it goes:** to Telegram when it is paired, because that reaches the person anywhere and its
buttons settle the item in place. Settling the item anywhere edits that message, as a told reminder
is edited today. With no Telegram, it is a desktop notice (`notify-send` on Linux, `osascript` on a
Mac, and on Windows the taskbar flash, `window_request_attention`), plus the chat line. It is never
both.

Nothing else raises a notice: there is no "all clear", no daily total and no streak.

## 6. Who sees what

**Each Asterion is one person's.** There is no shared server and no channel between houses, so
nothing crosses between them. That is the whole rule, and nothing has to enforce it.

| | the operator | Jude, Robyn |
| --- | --- | --- |
| list, reminders, waiting-ons, chores | their own | their own |
| money | their own bank, read-only | nothing, unless they link their own (#307: each brings their own accounts) |
| mail (#314) | their own, if built and switched on | the same, if they set it up |
| Telegram | their own bot and chat | their own, if they set it up |
| the model | their own `claude` CLI and account | the same, if installed; else the rules reader |
| your move | from their sources | from their list alone, which is overdue waiting-ons and stale to-dos |

The operator's money never names another person to that person. A transfer to "Robyn M." is a line
in the operator's own bank and nothing more. A house that two people share on one machine is not
designed here.

## 7. The model behind it

**Code decides, and the model words.** Your move, its order, its limits, every action and every
dollar amount are code, checked in `logic_*.gd`. The orchestrator works fully with no model. The
model only does what rules cannot:

| job | model | sees | when |
| --- | --- | --- | --- |
| read a loose line (exists: `reader_claude.gd`) | haiku | the line, the time and up to 40 open things as `id: text` | each tell |
| answer a money question (exists: `ask.gd`) | haiku | the plan's figures, computed by code | a money question |
| answer a question about the list | haiku | the open things and the next 7 days | a list question |
| read a mail into a proposal (#314) | haiku | that one mail's sender, subject and text | each new mail |

**Where it runs:** the person's own `claude` program, one-shot, `--tools ""`, with stdin closed and
killed at 45 s, exactly as `ask_model.gd` runs it today. It is off until the `claude` setting is on.
The settings say what is sent ("your messages are sent to your own Claude account"). It never sees a
token, an account number, the bank file or another source's data in the same call.

**What it keeps:** nothing. Each call is fresh. The house keeps the chat (the last 300 lines), a
money thread for two hours (as now) and `user://house_moves.json`: the open items, every settled
key with go or no and when, and the facts from answers. That file is 0600 and never goes into a
log or a test. The tests use fixtures.

No model larger than haiku is needed for any job above. If an answer is too poor, the fix is to give
it better figures, not a bigger model.

## Mockups

The window at its 1100x700 size. The room is on the left, and the 360 px sidebar is on the right.
Home leads with Your move. It draws nothing at all when there is nothing, as every Home section
does.

```
┌──────────────────────────────────────────────────────────────┬────────────────────────────────────────────┐
│                                                              │ ‹   Home                    ▲ 3    +   ⚙   │
│                                                              │────────────────────────────────────────────│
│                                                              │ Your move                                  │
│                     (the room, as today:                     │  Spotify is $13.99 now, was $11.99         │
│                      nothing new is drawn;                   │   1 keep   2 remind me to cancel   3 not…  │
│                      no number in the room)                  │  Move $120 from savings by Thu             │
│                                                              │   rent $1,200 due Fri, checking $1,080     │
│                                                              │                              go      no    │
│                                                              │  Nudge Sam about the invoice               │
│                                                              │   waiting since Tue          go      no    │
│                                                              │ Now                                        │
│                                                              │  Fix the bike light   Done  Something else │
│                                                              │ Today                                      │
│                                                              │  09:00  Standup                            │
│                                                              │  14:00  Call the dentist                   │
│                                                              │ Open                                       │
│                                                              │  Renew passport                            │
│                                                              │  Book the vet · 2 more...                  │
│                                                              │────────────────────────────────────────────│
│                                                              │ Say something to the house…                │
└──────────────────────────────────────────────────────────────┴────────────────────────────────────────────┘
```

- `▲ 3` sits in the header's right group, before the plus, in every view. It is not there at all
  at zero. A click opens the Your move view. It is the only new thing in the header.
- Home shows three items, then "N more..." in place, as Proposed does now. The Proposed section
  goes, because its rows are now proposals in Your move, with **go** for its "add".
- An ask's options are quiet buttons. The first is never primary, so no choice is pushed.

**The Your move view** has every item, the keys written at its foot (principles, rules 1 and 2),
and the chat's input line under it:

```
┌────────────────────────────────────────────┐
│ ‹   Your move               ▲ 4    +   ⚙   │
│────────────────────────────────────────────│
│ Asks                                       │
│ ▌Spotify is $13.99 now, was $11.99         │
│ ▌ since Mon                                │
│ ▌ 1 keep   2 remind me to cancel   3 not…  │
│                                            │
│ Proposals                                  │
│  Move $120 from savings by Thu             │
│   rent $1,200 due Fri · checking $1,080    │
│   → a reminder Wed 18:00     go      no    │
│  Nudge Sam about the invoice               │
│   waiting since Tue                        │
│   → a to-do today            go      no    │
│  Put "Renew passport" on someday           │
│   open since 3 Nov                         │
│   → someday                  go      no    │
│                                            │
│ Look at                                    │
│  This week's money                         │
│   opens Money        looks good   change   │
│────────────────────────────────────────────│
│ j k pick  ⏎ go  x no  1-9 answer  esc back │
│────────────────────────────────────────────│
│ Say something to the house…                │
└────────────────────────────────────────────┘
```

- Each proposal says what go will do (`→ a reminder Wed 18:00`), so go is never a guess.
- **change** on a look-at opens the chat with the item quoted.
- Empty, the view says `nothing needs you` in its middle, the same words as arena.

**The chat**, with a new item said once and settled in words:

```
┌────────────────────────────────────────────┐
│                    how am i doing on rent? │
│ Rent $1,200 is due Fri. Checking has       │
│ $1,080 and Chime Savings $2,400, so moving │
│ $120 covers it.                            │
│ ▲ Move $120 from savings by Thu            │
│                              go      no    │
│                                         go │
│ Reminder: move $120 from savings, Wed      │
│ 18:00.                                     │
│────────────────────────────────────────────│
│ Say something to the house…                │
└────────────────────────────────────────────┘
```

**Telegram**, with the day's card and its Your move block (#325's design, lettered):

```
Today · Mon 23 Nov
Your move
 A. Move $120 from savings by Thu
 B. Nudge Sam about the invoice
To do
 1. Fix the bike light
 2. 14:00 Call the dentist
[ Go A ] [ Go B ] [ Pick… ] [ ✓ Tick… ]
```

"go A", "no B" or "go all" typed works too. Once settled, the block reads "Done: A · Dropped: B".

## Build steps

Each is a tlon ticket under #14 (ficciones #524 aside), filed in backlog until this design is approved. The order is the
dependency order. The orchestrator lives over the house's own list only, as Telegram and the Claude
reader do. Over a tlon server, Home keeps today's Proposed.

1. **#516 Your move, the model** (`moves.gd`, `logic_moves.gd`): items `{key, kind: ask|proposal|look_at,
   source, text, why, options | action, date}`, `user://house_moves.json`, settle (go, no, answer),
   no is final for the key, the five-a-day and two-asks limits, the closed action set and
   self-retraction. `LocalList.status()` answers `moves` in place of `proposals: []`.
2. **#517 Your move on screen:** Home's "Your move (N)" section first, the Your move view with its keys,
   and `▲ N` in the header. It replaces Proposed over the local list. A soak section `moves`.
3. **#518 The list's own sources:** overdue waiting-ons and stale to-dos (step 1's rules). This is all
   Jude and Robyn's houses get, and it is enough to prove the loop with no bank or model.
4. **#519 Money's sources:** the short-before-deposit proposal and the new-or-raised-charge ask, whose
   answers are kept as facts ("Flex is rent"). It waits on #509 and #510 and uses #510's
   safe-to-spend figures.
5. **#520 The chat is the orchestrator:** money questions go through `ask.gd` from the chat, Money's own
   ask line goes, list questions are answered, items are settled in words, and a new item is said
   once. It delivers #510's point 4 ("advice comes through the ask") in the chat.
6. **#521 Telegram's Your move:** the day card's lettered block and an urgent item as its own message,
   edited when settled. **Absorbs #325**: its Proposed block becomes this, and its Notices line and
   deliveries stay #325's design, carried here.
7. **#522 Notices off Telegram:** the desktop notice (`notify-send`, `osascript`, the taskbar flash),
   quiet hours and the window-in-front rule.
8. **#523 `asterion --tell`:** a line handed to the running house through the one-house handshake. Then
   **ficciones #524**: `Super+Shift+U` opens a one-line prompt and runs it.
9. **Mail (#314)** stays its own spike. If it is built, it is a source for step 1: a mail that wants
   a reply becomes a proposal, and a delivery becomes a notice line on the card (#325). Its
   `proposals` gap becomes "moves from mail". If it is dropped, nothing above changes.

## Open for the human

- Approve the shape: the house is the orchestrator, code builds Your move, go never leaves the
  house, and `Super+Shift+U` is the desktop hotkey.
- Money's ask line moves into the chat (step 5). Is that all right?
- Money's "Noticed" heading: keep it, or rename it so "notice" has one meaning?
