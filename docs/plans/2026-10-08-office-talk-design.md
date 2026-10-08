# Talking in the office — say something to a coworker without a chat window

**Status:** approved by Andrew 2026-10-08 (asked for this write-up and its ticket). Office-only:
the server's plumbing (`Server.Switchboard`, mentions, home windows on the lobby) already does
the delivery; this is the porcelain over it.

## 1 · The problem

Andrew can't tell what the standing threads are or how to talk to whom. What's there:

- Each workspace has one **lobby** (`Server.Bootstrap`'s `@standing_title`): its root machine
  thread, led by the workspace's manager (tertius in Machine), where every coworker's home window
  lives. Four workspaces, four threads all titled "lobby".
- Each lobby sits in its workspace's **#general** (`Server.Channels`); the office never shows
  channels.
- A plain post on a thread wakes only its lead; an `@name` wakes that coworker in their home
  window on the lobby (`Switchboard.elsewhere/2`), started on demand if absent. There is no 1:1.
- In the room, a coworker's card offers their current thread's verbs; one on the bench offers
  nothing to say. `enter` steps into their terminal session — a chat pane, which is the thing to
  get away from.

## 2 · The shape — two kinds of talk

| Talk to | Key | Posts | Who hears it |
|---|---|---|---|
| **a person** | click (or tab to) them, `m` | `@name …` on the workspace's lobby | that coworker, in their home window |
| **the office** | `'` anywhere in the room | an unaddressed post on the lobby | the manager (intake: a want becomes a ticket) |

- **The composer is a speech box over the speaker**, not the reader: one to four lines, `enter`
  sends, `esc` drops it, `shift+enter` a new line. It reuses `office/tui/editor.ts`.
- **The answer comes back as a speech balloon over their head** (§3), and as an inbox item if you
  aren't looking at the room. The bubble fades; the words don't — they're posts on the lobby.
- **"The conversation with X"** is the lobby's messages between the operator and X (posts by X, and
  operator posts that mention X or reply to X), shown in the reader. `v` on their card opens it.
  No DM schema: it is a filter.
- **On the bench means free to chat.** `m` works on anyone, so the card never has nothing to do.

## 3 · Speech balloons — bigger, and never overflowing

Today (`office/kit/canvas.ts` `balloonLines`, `office/tui/paint.ts`) a balloon is three lines of
~26 characters. It can spill out four ways:

1. A word longer than the line (a URL, a path) is never broken, so its line runs past the box's
   own wrap width.
2. Block mode clamps the box's column but not its width: a box wider than the room's columns runs
   off the right edge.
3. Kitty mode clamps the box's x but a box wider than the canvas still runs off, and the tail is
   drawn at the speaker's `cx` even when the box was pushed away from it.
4. Two balloons near each other overlap; only the pets' exchanges wait their turn (`wide.ts`).

The law, for both render modes:

- **Every balloon fits inside the visible room**, box and tail: its wrap width is the smaller of
  the line limit and what the room's width allows, words longer than a line are hard-broken, and
  the tail is clamped to the box's span.
- **No two balloons overlap**: a later one is nudged up (or waits, as the pets' do) until clear.
- **Bigger:** up to **34 characters a line and 4 lines** (was 26 × 3), with a little more padding.
  A reply longer than that ends `... (v)` and `v` opens the conversation.

## 4 · Naming

- The room never says "lobby". The lobby is shown as **the front desk** — the manager's desk,
  where you say things to the office — and a home window as "at their desk".
- `#general` appears only once a workspace has a second channel.

## 5 · Steps

| # | Step | Check |
|---|---|---|
| 1 | **Balloons** (§3): bigger, hard-wrap, fit, no overlap | tests: `balloonLines` never yields a line over the limit or more than 4 lines (fuzzed, with 80-char words); a balloon at each room edge stays inside the canvas in kitty and block modes; two speakers side by side don't overlap |
| 2 | **Talk to a person** (`m`) and **the office** (`'`), the speech composer | test: `m` on a benched coworker posts `@name …` to the workspace's lobby; `'` posts unaddressed; drive-office shows the composer over the speaker |
| 3 | **Replies as balloons** + the inbox item | test: a lobby post by X answering the operator puts a balloon over X |
| 4 | **The conversation with X** (`v`) and the naming (§4) | test: the filter keeps X's posts and the operator's posts mentioning/replying to X, nothing else |

Step 1 stands alone and ships first; 2–4 go in order.
