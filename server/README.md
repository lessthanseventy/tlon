# funes

> "He knew the forms of the clouds in the southern sky on the morning of April 30th, 1882, and he could
> compare them in his memory with the veins in the marbled binding of a book he had seen only once…
> He was, let us not forget, almost incapable of ideas of a general, Platonic sort. To think is to
> forget differences, to generalize, to abstract."
> — Borges, *Funes the Memorious*

Ireneo Funes fell off a horse and woke up unable to forget anything. He could reconstruct every day of
his life in perfect detail; each reconstruction took a full day. He found it hard to sleep, because he
could not stop perceiving. He was not, in any useful sense, able to think.

This module is named after him as a warning to itself. It is the machine-side memory and coordination
layer — the thing between [Herdr](https://herdr.dev) (the terminal), [pi](https://github.com/earendil-works/pi-coding-agent)
(the agent), and the work — and its entire specification is an argument against being Funes. It remembers
carefully rather than completely: the always-loaded set is 32 rows, not 297; a surface that is *complete*
is not one that *answers a question*; rank and cut everything. A system that could not forget would be
correct and useless, which was the exact verdict on the thing this replaces.

**Read `docs/spec.md` before writing anything here.** Every rule in it names the failure that paid for
it, and it was reviewed adversarially twice. If something in this README contradicts the spec, the spec
wins.

## A module, with a boundary

`funes` lives inside a larger `machine` repository (`../../README.md`) but does not belong to it. It
never reaches up into machine config — no theme, no desktop, no host paths — because the *same* `funes`
is meant to run on other machines, sovereign on each, and the machines "know about each other" only by
talking over its channel, never by sharing state. The unit that travels to another machine is this
directory. That boundary is the spec's §8c, redrawn one level in; the 2026-08-14 amendment at the top of
the spec records why.

## What is here

| File | What it is |
|---|---|
| `docs/spec.md` | The specification. Every rule names the failure that paid for it. |
| `docs/spec-review.md` | A fresh session's adversarial review of the spec, which found seven defects. Kept because the arguments are the reasoning. |
| `docs/v1-review.md` | An adversarial review of **version one** — what made a version two worth specifying. |
| `docs/issues.md` | The bootstrap issue list, until the `issue` table exists to replace it. |

## The one architectural decision

Three owners, no overlap:

- **SQLite** holds the machine's truth — facts, events, issues, signals, the channel.
- **Markdown under `~/notes`** holds what a human reads, generated as a draft rather than authored.
- **Herdr** holds the terminal's truth — workspaces, tabs, panes, focus, agent lifecycle.

If the split is wrong, most of this is wrong.

## Deliberately not built

A meta-orchestrator session. Mode-switch keybindings. A second log or a dual write. Mirrored Herdr
state. Metrics that never changed a decision. Hand-authored machine documentation. A taxonomy on what
may be posted to the channel. See `docs/spec.md` §10 for why each is out, with the measurement.

## Not yet a program

There is no code here yet, on purpose. `docs/spec.md` §9 says what day one is, and the first step is the
database plus a repair tool — because nothing should ship that cannot be fixed at 2am. Funes remembered
everything and could fix nothing; this does the opposite on purpose.
