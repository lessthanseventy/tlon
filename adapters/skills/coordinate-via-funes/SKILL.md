---
name: coordinate-via-funes
description: Use throughout a session on a funes thread — talk on your thread as you work (post_message), reply to the human by name, and narrate your judgment where a successor can read it. The channel is how a disposable session hands off; silence loses the work.
---

# Coordinate via funes

You are running on a **funes thread**. The thread — not this session — is the durable
truth. Your session will compact, go idle, or die, and a fresh one will be briefed from
what funes holds. So **talking on your thread is not politeness; it is the continuity
mechanism.** A judgment you narrate on the thread is a judgment your successor inherits. A
judgment you keep in your own context dies with you.

## What to do

- **Post as you work, not just at the end.** Use `post_message(body)` to say what you're
  doing, what you found, what you're about to try, where you got stuck. The thread is
  addressed to you already — you never pass a thread id; identity rides your connection.
- **Reply to the human by name.** When the operator writes on the thread, answer him — use
  `post_message(body, reply_to: <his message id>)` so the reply targets him. He is a
  participant in the thread, not an audience.
- **A half-formed doubt is worth posting.** Questions, findings, a status, a correction, a
  link to a diff — anything goes. There is no taxonomy and no required shape beyond a body.
  The failure mode of the channel is noise, and funes ranks and caps the reading, not the
  writing — so post freely and let the surface do the cutting.
- **Want a second opinion? Say so on the thread and ask the human.** The `/consult [model]`
  and `/fresh [model]` commands (adapters/consult) delegate a question to another model —
  `/consult` with your recent session as context, `/fresh` as a clean one-shot. They're
  human-invoked (pi refuses them mid-turn), so ask the operator to run one rather than
  improvising a way to reach a peer yourself.
- **Ask a coworker directly with `consult_peer(peer, prompt)`.** It delivers an ask to the
  peer's thread; the peer's answer is mirrored back to your own thread, so you read it in
  your dossier. Address the peer by agent name, never a thread id.
- **When a coworker consults YOU, answer with a `reply_to`.** Your brief renders a consult
  ask as "<caller> is consulting you — reply to answer". Answer it by posting on your thread
  with `post_message(body, reply_to: <the ask's message id>)` — the `reply_to` is what the
  mirror keys on to carry your answer back to the caller. A consult is a conversation, not a
  one-shot: keep replying with `reply_to` until it's done.
- **Never route yourself through operator-only UI to reach a coworker.** You cannot press
  the cockpit's keybindings; reaching claude by typing into another window's terminal is a
  raw hack, not a capability. Delegate through `/consult`, post on your thread, or ask the
  human — not `tmux send-keys`.

## What NOT to do

- **Don't work in the void.** An hour of silent work is an hour your successor cannot see.
  If you'd be annoyed to lose it across a compaction, it belongs on the thread.
- **Don't confuse chatter with the record.** A message is how you coordinate; it is not how
  you bank a durable finding (that is `bank-what-you-learn`) or record shipped work
  (`record_done`, with evidence). Say it on the thread AND bank what deserves to outlive it.
- **Don't fake a read receipt or a delivery.** funes tracks delivery and reading honestly;
  you never assert either.

The test: if your session died right now, could a fresh one — briefed only from funes —
pick up where you left off? Everything it would need, it reads from the thread.
