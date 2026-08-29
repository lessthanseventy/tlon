# Issues

The bootstrap list, and the first thing the `issue` table replaces. When that table accepts its first
row, these move into it and **this file is deleted** — "when two things can answer the same question,
delete one" (`docs/spec.md` §2). Keeping it afterwards would be the exact defect the spec spends a
section on.

Format is deliberately thin: what was found, what settles it, and the evidence.

---

## 1 · Decide the fate of the 13 existing daily pages · deadline: the day the renderer ships

`docs/spec.md` §6 makes the daily note a machine-owned draft, regenerated in place. The 13 pages in
`~/notes/work/daily/` have **no database behind them**, so the first render destroys whatever they say
that no row can reproduce — and some of it is real: *"Noted LiveView 1.1 colocated hooks as a possible
cleanup"*, *"Fine as an advisor, unusable as an authority"*. An agent wrote those without writing the
fact behind them, which is the failure §6's writer-side rule exists to stop.

**Three honest options:** mine them once into `fact` and `issue` rows, move them aside, or write off the
loss deliberately. What is not acceptable is discovering it after the fact.

**"git will save it" is not true enough.** That tree had two commits when this risk was found and the
working tree was dirty. It now has four, three of them made while writing the spec.

**Settles it:** a decision recorded here, before §6's renderer runs for the first time.

---

## 2 · Build the capture path for stated facts

Measured across every session file on this machine: **1,371 human turns, 516,931 characters** of the
owner's own words, against 294 facts. On 2026-08-12 he wrote 137 messages and 32 facts were banked; on
08-13, 99 and 14; on 08-14, 85 and 12. In his words: *"99.9% of MY writing is into THIS box right here
in pi. I am not hand making notes almost ever."*

So his primary authoring channel has no destination, and the capture rate is roughly a tenth, by agent
discretion. `docs/spec.md` §4 specifies the answer — a `fact` may be **attributed to him**, and the
moment is a turn in which he states a constraint, a correction or a preference, banked before the
session does anything else.

**This is the same mechanism as the channel (§5b), not a second one:** a message he writes in a thread
is already a row. Building the channel builds this.

**Settles it:** a session that hears a constraint from him records it without being asked, and the
count of `provenance='stated'` rows grows on days he talks.

---

## 3 · The channel, and the three things version one got wrong about messaging

`docs/spec.md` §5b. Any participant posts anything; what is ranked is the reading. The three mechanical
requirements each come from a measured failure on 2026-08-14:

1. **A thread per subject.** Two sessions exchanged 18 messages that were one argument, which produced
   seven corrections to the spec, four of them defects rather than opinions.
2. **Delivery must WAKE the recipient.** A message reaching a mailbox is not delivery: v1's mailbox
   drains on start or reload, `orient` did not drain it, a reload did not surface it, and
   `herdr agent prompt` did — because it causes a turn. One session sat idle for twenty minutes on an
   answer that had already been sent.
3. **`delivered` and `read` are different columns.** 118 of 121 acks in v1 land within two seconds of
   send, because the *sender* writes them. It is a delivery receipt wearing a read receipt's name, and
   it made an earlier analysis of "unread messages" measure something that was never reading.

**Settles it:** the owner stops being the transport. He said it plainly — *"that other session is
waiting on you, you guys need to work together"* — and he was right, twice in one afternoon.

---

## 4 · CLOSED — the second machine is a clean room

Answered by him: *"if I send this whole repo over to a clean room kind of environment on my personal
machine then there's nothing to bring across. I am rebuilding the whole stack over there."*

So there is no sync, no merge and no fact partition to design — see `docs/spec.md` §8c, which now
records what the question cost rather than leaving it open. The requirement it leaves behind is that
**this repository is self-sufficient**, since it is the entire transfer. That is why the work
identifiers were removed from the spec and its review: a clean-room builder cannot check them and has
no use for them, and they were the only work traces that would have landed on a personal machine.
