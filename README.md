# tlon

**The name.** Borges' *Ficciones* (1944) names the machine this grew up on; this repo is named for
one story in it: **Tlön**, from "Tlön, Uqbar, Orbis Tertius" (1940), where scholars find an encyclopedia of
an invented planet and, as they study the fiction, it bleeds into reality and overwrites it. That is
exactly what the product does — you author a fictional organization (a cast of agents, workspaces,
knobs) and, through use, it becomes real work in your actual repo. The fiction overwrites reality.

Tlön is **many UIs over one memory** — a communication, planning, and coordination surface for a crew
of AI agents. Three internal apps make it up, named for what they do:

- **`server`** — the shared spine: the data model, the communication bus, the single-writer discipline,
  the always-up MCP channel. (The memory concept is *Funes the Memorious* — the man who could not
  forget — living on in the recall engine.)
- **`console`** — the TTY cockpit that renders the spine: workspaces, threads, the crew, embedded
  terminals. Launched with the `tlon` command.
- **`adapters`** — the hands: how a working agent (Claude Code, pi) reaches the spine, wakes up already
  knowing its thread, and banks what it learns.

A **workspace** is a project inside Tlön (*ficciones*, the machine, is one). The crew keep their Borges
names — **tertius** (the Orbis Tertius meta-agent), **hronir** (the builder). Cute names only for
things with personality; everything else is called what it is.


## Layout

```
tlon/
  server/     # the spine — its own spec (server/docs/spec.md), its own boundary
  console/    # the TTY cockpit, launched as `tlon`
  adapters/   # the hands: pi extensions, the Claude Code launcher + hooks, skills
  tasks/      # the mise tasks (mise.toml includes them) — `mise tasks` lists every verb
  scripts/    # the shell side of the loop (cap, watch, the reaper, the tlon CLI)
```

Start with `AGENTS.md`; the gate is `mise run check`.
