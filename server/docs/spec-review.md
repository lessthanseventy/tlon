# Review — Workbench 2.0 specification

Adversarial review of `docs/specs/workbench-2.0.md` (276 lines, written 2026-08-14) by a fresh
review space (w4H) with no part in building version one and no part in writing the spec.

Read-only review. The spec was not edited. Evidence below is re-derived from live data on this
machine, not taken from the spec's own citations.

---

## Verdict

**The one architectural decision (§2) is right, and most of the document follows from it correctly.**
SQLite for machine truth / markdown for the human / Herdr for the terminal is a real split with a real
test, and it kills version one's worst class of bug by construction.

**Three things would stop a builder on day one, and one rule is justified by a measurement that does
not support it.** In order:

1. **No table owns "what I did"**, so §9's day-one glance cannot answer the second of the two questions
   the whole document exists for. This is the most serious finding and it is structural, not editorial.
2. **§9 step 3 is unbuildable as ordered** — glance reads `signal` rows, and the signal collectors are
   explicitly deferred to after day one.
3. **§4 never says whether `event`'s per-kind fields are columns or JSON**, and the corpus already
   contains the exact shape collision that decision has to survive.
4. **§10's mode-keybinding deletion is justified by a measurement that is false and, worse, structurally
   incapable of measuring the thing being deleted.** The deletion is still correct; its stated reason is not.

Nothing here says stop. §4's write contract, §5, §8 and the day-one ordering-by-repairability instinct
are the best parts of the document and I would not touch them.

**Two of the three open questions were answered while this review ran, and both answers create work the
spec does not contain.** The clean-repo decision leaves the deployment step undefined, and the
measure-don't-log rule that replaces the `turn` table is **false as written on this machine's own data** —
it would forbid the one table §7 imports. Both are new sections below.

---

## The §10 answer: which deletion's measurement does not support it

**"No mode-switch keybindings."** The measurement given is: *"127 sessions, 54 mode entries in 38
sessions, 35 of them written by the agent tool, and zero in any session born in the last three days.
A mode is a launch profile, not mutable state."*

Independently recounted across all 137 session files in `~/.pi/agent/sessions`:

| Claim in §10 | What the corpus says |
|---|---|
| 54 entries in 38 sessions | **56 entries in 40 sessions** (of 137 = 29% of sessions) — consistent, corpus grew |
| 35 written by the agent tool | **not observable.** 45 of 56 are parented by an assistant `message` entry; 11 by an `anmoore-mode-card` (the launch persist). Nothing in the file records *which* path invoked it |
| zero in any session born in the last three days | **false at time of writing** — see below |

The two counterexamples, both predating the spec:

- `sessions/--Users-anmoore-projects-<project>--/2026-08-13T19-41-42-690Z_019ffca5-…jsonl` —
  session born 2026-08-13, switched to `development` at `2026-08-13T19:51:35.689Z`, in real project work.
- `sessions/--Users-anmoore-.config--/2026-08-14T17-34-32-806Z_01a00156-…jsonl` — born into `planning`
  at 17:34:32, switched to `workbench` at `2026-08-14T17:34:39.762Z`, **seven seconds later**. That is
  the spec's own working session mutating its own mode while the document asserts modes are not mutable.

And the structural problem, which the machine has already banked as a durable fact: *"Persisted files
cannot distinguish a Herdr chord from direct `/mode`, because switch-mode.lua injects `/mode <mode>`."*
So this corpus **cannot measure chord usage at all**. It measures mode switching, finds 45 mid-session
switches in 40 sessions, and is then used to justify deleting the chords and to assert that modes are
launch profiles — a conclusion its own numbers contradict.

The real justification exists and is good: `prefix+shift+S` meant "switch to Support mode" while the
human read it as "go to the Support desk" (`docs/plans/2026-08-13-workbench-deletion-plan.md` §2,
`config.toml:44,90,96-120`). A chord that collides with the user's mental model earns deletion on its
own. **Fix: state the collision, delete the sentence "a mode is a launch profile, not mutable state",
and say explicitly that `/mode` and `workbench_mode` are retained because 45 mid-session switches is
the normal case, not the exception.** As written, a builder implementing §10 faithfully removes
mid-session mode change from 2.0 — including from the agent tool that made most of those 45 switches.

**Severity: high**, because the rule will be obeyed and the sentence is the load-bearing part.

The other five §10 deletions hold up, with one note: *"a broadcast is mechanically unread, because a
session drains its mailbox only when it starts"* is true of **version one's mechanism**, in a document
whose premise is that version one's design gets no vote. If the database is the bus, a session can read
its mail on demand and the mechanism argument evaporates. Delete the metric for the right reason — it
never changed a decision — not for a limitation 2.0 is free to remove.

---

## Defects a builder would stop and ask about

### 1 · Nothing owns "what I did" — high

The two questions in §1 are *"what do I need to Review PRwise right now"* and *"What did I do
yesterday?"*. The second has no source in 2.0.

- Today's answer lives in the worklog: **180 rows over 13 days, kinds `win` (137) and `blocker` (43)**,
  written by `workbench.ts:4470` and read by `briefing/glance.mjs:16`.
- §4's `event` is described entirely in mechanism terms: *"a session started, a handoff opened, a message
  was sent, a check passed, a command was approved."* **No `win`, no `blocker`, no human-authored
  accomplishment appears anywhere in §4.**
- §7 drops the worklog. §9 ships glance in step 3 from `signal` rows.

So on day one, "what did I do yesterday" reads mechanism events — which §7 itself dismisses as *"mostly
the mechanism's own noise"* when arguing against importing the mail and handoff logs. The same argument
applies to the data glance would be left with.

**§7's stated reason for dropping the worklog is also false.** The reason given is that keeping it
"means supporting version one's shape forever". The shape is `{at, kind, text, cwd, mode, branch}` —
every field survives into the new schema unchanged. Importing 180 rows is a one-off script of about
twenty lines with no ongoing cost. Whether the human wants 13 days of history back is his call and the
answer may well be no; but the trade as argued is not the trade that exists.

**What a builder must ask:** which table holds a `win`, and does `event.kind` include human-authored
kinds alongside mechanism kinds? If it does, the day view needs a curated allowlist of kinds and §4
must say whether a **newly added kind is visible or invisible by default**. That single unmade decision
is the whole "dumping ground" risk, and it is one line to settle.

### 2 · §9 step 3 cannot be built in the order given — high

Step 3 is *"`glance`. The two questions, from `signal` rows"*. The closing paragraph defers *"the signal
collectors"* to after day one, *"only with evidence that each is wanted"*. There is therefore no writer
for the table step 3 reads, and no writer for the worklog data behind its second question either.

The likely intent is that glance keeps reading version one's `~/.local/state/ai-workbench/watch/prs.json`
during the transition (`glance.mjs:25`). The spec never says so, and §7 lists pull-request snapshots as
"regenerated in minutes" without saying by what. **Ask: during cutover, does glance read v1's files, or
does one collector ship in day one?** As ordered, the first thing the human sees from 2.0 is an empty
glance, which §6 correctly identifies as the failure mode that matters most.

### 3 · `event` with a `kind`: the collision is already in the corpus — high

The claim is defensible, but the spec does not do the work that makes it safe. What one `event` table
would have to absorb, measured from live files:

| Source | Rows | Shape |
|---|---|---|
| `handoffs/log.jsonl` | 75 | `{at, mode, note, parent, state, subject, workspace}`; `state` is a *second* discriminator: handed off 37, landed 19, space gone 7, failed to open 9, abandoned 2, closed 1 |
| `handoffs/mail.jsonl` | 213 | **two shapes in one file** — 111 message rows `{at, evidence, from, id, kind, next, subject, text, to}` and **102 ack rows `{ack, at, by}` with no `kind` field at all** |
| `worklog/*.jsonl` | 180 | `{at, kind, text, cwd, mode[, branch]}` |

Union that and you get either ~15 mostly-null columns or a JSON payload. **The spec never says which.**
Every downstream query in §6 depends on the answer, because indexing a JSON payload in SQLite needs
generated columns or expression indexes, and that is a schema decision, not an implementation detail.

Tested against the three queries the brief asked me to test:

- **"What did I do yesterday?"** — needs a kind allowlist. See defect 1.
- **"Which handoff never landed?"** — answerable, but only on a stable correlation key. Today **5 of 75
  handoff rows carry an `id`**; by subject, **8 of 35 subjects have only a `handed off` row and no
  terminal state**. So the query is a self-join on a key that must be `NOT NULL` from the first row
  written. §4 does not name it.
- **"Who owes whom an answer?"** — see defect 4. Harder than it looks, and §6 has it backwards.

**Ask: columns or JSON; is `kind` an open string or a closed set with a `CHECK` constraint; what is the
correlation key for a multi-row lifecycle (handoff opened → landed, question → answer); and which fields
are required per kind.** Four sentences would close all of it.

### 4 · §6 ships the surface §10's own source said must not ship — high

§6 lists **coordination**: *"who owes whom, what died on arrival — a query, not a hand-join."*

The deletion plan §4 established that this metric produces false positives: `w44→w45` was reported as an
unanswered question when the answer had been relayed through `w25` (`orchestrate.mjs:105-195`,
`mail.jsonl:193-198`). Its verdict was: keep directed unanswered questions **only** after routed-answer
correlation, options in order — correlate on handoff id, accept a reply from any space on the same
subject, or **delete the section**. §6 carries none of that precondition.

The corpus makes it harder still: **102 of 213 mail rows are acks**, `{ack, at, by}`, referencing a
message id. An ack is a delivery receipt, not an answer. A naive "did the recipient ever reply" query
reads acks as answers and under-reports debt in exactly the direction that makes the surface useless.

**Fix: either §6 states the correlation rule ("correlate on handoff id; an ack is not an answer") as a
precondition of shipping, or the row comes out until §9's "with evidence that it is wanted" gate.**

### 5 · The subject↔workspace seam in §2 is undefined — high, because §2 is the whole document

§2 says SQLite never holds "how the screen is arranged" and Herdr never holds "anything about the work
itself". But the binding **"subject X is being worked in workspace w4H"** is both, and it is what every
coordination query needs. Version one stores it: `handoffs/log.jsonl` rows carry `workspace: "w4H"`
alongside `subject` and `parent`.

The right answer is probably: SQLite stores the workspace id as an opaque **reference**, never a cached
copy of any of its properties, and any query that needs liveness asks Herdr within the turn. That is
consistent with §2's "cache the answer for the length of one turn, never longer" — but §2 states the rule
about *state* and never about *identity*, so a builder has to invent the distinction. **Two sentences.**

### 6 · "Every surface states the age of what it read" is unimplementable from §4's tables — medium

§4: `signal` rows, *"each rewriting only its own rows"*. §6: *"a collector that cannot collect writes
nothing and says so"* and *"every surface states the age of what it read."*

If a failed collector writes nothing, no row carries the failure, and nothing can distinguish "collected
five minutes ago, the world is genuinely empty" from "the last three runs were network-denied" — which is
precisely the incident §6 cites. There is no per-source row and no collection-outcome event in §4.

**Ask: where does `last_attempt` / `last_success` / `last_error` live per source?** Either a small
`source` table or an `event` kind that every surface joins. Without it, the rule in §6 is unenforceable
and the incident recurs.

### 7 · "No spill file" is justified by an incident of a different shape — medium

§10 forbids a spill file and cites §2. But §2's incidents are two *readers* of the same answer where the
untested one sat in the live path: a stale pane-id parser beside a tested one, a hand-written key map
beside the config. **A durability queue that is written, drained on the next successful write, and
deleted is not a second source of truth** — nothing ever reads it as an answer to a question.

That does not mean build one. It means the rule is doing work its evidence does not support, and the real
question is unanswered: §4 says a failed write is retried once and then "surfaced". **Surfaced to whom,
and which writes may be lost?** My read of the rest of the document is that mechanism events may be lost
and `fact` and `issue` may never be, since §5 exists entirely to stop findings evaporating. Say that.
One sentence, and the "no spill" rule then rests on a real boundary instead of a borrowed incident.

### 8 · §5's acceptance test collides with §1's ranking rule — medium

*"A session reads open issues at start, unprompted."* Scoped how? All open issues on the machine, in
every session, is version one's radar failure reproduced — *"correct and useless"* — and this machine
runs 137 sessions across 32 project directories. **Ask: scope (subject? repo? cwd?) and a cap.** The
acceptance test as written passes while producing the thing §1 forbids.

### 9 · The document breaks its own vocabulary rule three times — low, but free to fix

§3: *"Vocabulary is Herdr's vocabulary. Workspace, tab, pane. Do not invent a noun for something another
program already names."* The word "workspace" appears 3 times in the document; "space"/"spaces" appears
3 times, including inside §3 itself:

- line 20 — "he could not remember what his own **spaces** were called"
- line 55 — "version one kept its own idea of which **spaces** existed"
- line 74 — "the **space** is marked blocked"

Note also that the deletion plan §1 recommended the opposite convention — *"one noun — **space** — and
one verb — Open"*. The spec silently overrides it and then uses both. Given that the founding complaint
is that the human asked about naming three times, this needs to be one word, chosen once, used
everywhere. **This is the cheapest high-value edit in the review.**

### 10 · One §8 measurement I could not verify — low, and it is a question not a defect

§8: *"`herdr pane wait-output` searches the existing snapshot and returned a match in 0.02s."* I searched
all 291 ledger entries; `0.02` appears only in an unrelated 2026-08-07 entry about TCC-protected path
reads. The rule itself (always pass a timeout; wait for what a command prints, never for a prompt) is
sound and independently attested. **The number may be transposed from another measurement.** Either
re-measure it or drop the figure and keep the rule.

---

## Section-by-section, one line each

| § | Verdict |
|---|---|
| 1 Who this is for | Fine. The best section; the two quoted questions are the acceptance criteria for the whole system. |
| 2 The one decision | Right, and worth the whole document — except the subject↔workspace seam (defect 5). |
| 3 One control loop | Right and well-evidenced. Fix the vocabulary self-violation (defect 9). |
| 4 The database | Write contract is the strongest engineering in the document. Table definitions are underspecified (defects 1, 3, 6). |
| 5 Issues | Fine, and the "delete the table if orient does not read it" gate is exactly right. Scope the acceptance test (defect 8). |
| 6 Surfaces | The five rules are all earned. The coordination row should not be there yet (defect 4). |
| 7 What imports | Conclusion is probably right; the argument for it is wrong (defect 1). |
| 8 Boundaries | Fine. Do not touch. One unverifiable number (defect 10). |
| 9 Day one | Right instinct — repairability first — but step 3 has no writer (defect 2). |
| 10 What 2.0 does not do | Five hold. The mode-keybinding measurement does not support its conclusion (see above). |

---

## What I would cut

1. **The sentence "A mode is a launch profile, not mutable state"** (§10). It is contradicted by 45
   mid-session switches, including one by the spec's own session. Keep the deletion, change the reason.
2. **The coordination row in §6.** Move it below the §9 evidence gate with the correlation rule attached.
3. **The "supporting version one's shape forever" argument in §7.** The shape is a strict subset of the
   new one; the honest reason is "13 days is not worth a decision" and that reason is sufficient.
4. **The 0.02s figure in §8.** Unverifiable; the rule survives without it.
5. **Nothing else.** The document is already short and the remaining rules all carry their incidents.

## What is missing

1. **A named table or kind for "what I did"** — the second of the two founding questions has no owner (defect 1).
2. **The `event` payload decision** — columns or JSON, open or closed `kind`, and the correlation key for
   multi-row lifecycles (defect 3).
3. **Per-source collection state** — `last_attempt` / `last_success` / `last_error`, without which §6's
   age rule cannot be implemented (defect 6).
4. **Which writes may be lost** — the retry-once contract needs a stated blast radius (defect 7).
5. **A cutover statement** — what reads version one's files while 2.0 is partial, and what the human sees
   during the days when both exist. §9 assumes a clean start; §0 promises "keeps running until this
   replaces it piece by piece". Those need to be the same story.

## Does the spec answer the version-one deletion plan?

Mostly yes, and it should not re-derive what is already there. Three items are unaddressed:

- **Deletion plan §3** — reconcile by *shadowing* the native `close_workspace` chord, since the raw close
  is the path the human actually uses. §8 restates the measurement ("state must be consistent before a
  close") but 2.0 never says who writes that state or when. A builder implementing §8 does not learn
  that the mechanism is a shadowed keybinding.
- **Deletion plan §4** — the routed-answer correlation precondition (defect 4).
- **Deletion plan §1** — the noun. The plan chose "space"; the spec chose "workspace" without saying it
  is overriding a prior verdict (defect 9).

---

## 11 · The clean repository, and the deployment step that does not exist yet
*(added after the owner answered open question 2: 2.0 is a clean repository with the spec as its first
commit, no backwards compatibility with version one.)*

**The decision is right and the deployment step is smaller than the question implies.** Three of the four
roots version one occupies already have a supported pointer mechanism, and this machine is already using
one of them for a different package. There is no need for copies, and therefore mostly no need for drift
detection — the drift risk moves from file contents to pointer validity, which is a much smaller surface.

What the evidence says, root by root:

| Root | How the loader finds it | What 2.0 needs |
|---|---|---|
| `~/.pi/agent/extensions/` (`workbench.ts`, `workbench-suite/`) | auto-discovery of `*.ts` and `*/index.ts` (`docs/extensions.md:113-120`) — **but** pi also supports a **local-path package**: `settings.json` already contains `{"source": "/Users/anmoore/.pi/agent/packages/elixir-pi", "extensions": [...]}` | `pi install /path/to/repo`, or a `packages` entry with `source` + an explicit `extensions` list. **No copy, no symlink.** Arbiter: `pi list` |
| `~/.config/ai-workspaces/herdr-plugin/` | absolute paths in config: 9 `command = "/Users/anmoore/.config/ai-workspaces/herdr-plugin/*.zsh"` lines in `herdr/config.toml:76-167`, plus a registry entry in `herdr/plugins.json` with `plugin_root` | repoint `command =` and `plugin_root` at the checkout. **Pointer, not copy.** Arbiter: `herdr config check`, `herdr plugin list` |
| `~/.config/ai-workbench/briefing/*.mjs` | nothing loads it directly — the `ai-*` wrappers name it | nothing. It moves with the repo |
| `~/.local/bin/ai-*` | `PATH` | these are **already pointers**: 95–274 byte wrappers, e.g. `ai-glance` is `exec node "$HOME/.config/ai-workbench/briefing/glance.mjs" "$@"`. Repoint the one path inside each, or put the repo's `bin/` on `PATH` |

So the honest answer to *"symlinks, a copy, or a config pointer"* is: **config pointer for all four, and the
repo needs a `bin/` directory plus an install target that writes three pointers** — a `packages` entry in
`~/.pi/agent/settings.json`, a `plugin_root` in Herdr, and `PATH`. `~/.config/workbench-env/mise.toml`
already carries an `install` task, referenced by `wb`'s own header comment, so the pattern exists.

**On whether a single repo is right at all: yes, and the four roots are not evidence against it.** Four
roots is not four components; it is one component observed through three loaders' discovery rules. The
test that matters is whether a human can clone it and read it in one place, and that test only passes with
one repo. The thing to resist is not the single repo but the temptation to make the deploy step *copy*.

### The drift failure mode is not hypothetical — it is live, it is in Herdr, and both arbiters say ok

This is the strongest evidence in the review, and it is present-tense:

```
herdr-plugin/herdr-plugin.toml   version = "0.7.0"   22 actions   (modified Aug 12 14:52)
herdr/plugins.json               "version": "0.1.0"   3 actions   (written  Aug  5 15:44)
```

`plugins.json` is Herdr's installed-plugin registry and it holds a **cached copy** of the manifest. It has
been stale for seven days. Concretely:

- The manifest defines 22 actions including `triage` and `notes`. The registry lists **three**:
  `development`, `review`, `support`.
- `herdr/config.toml:104` binds `prefix+shift+i` to `plugin_action` → `anmoore.ai-workspaces.triage`, and
  `:113` binds `prefix+shift+n` to `anmoore.ai-workspaces.notes`. **Neither action exists in the registry.**
- The registry's description still says *"Workshop workspaces"*; the manifest says *"Workbench"*. The
  renamed noun from §3's own vocabulary complaint is frozen in a cache. (`workshop` also appears 6 times
  in the session corpus as a persisted mode value.)
- **`herdr config check` returns `config: ok`.** `herdr plugin list` reports the plugin as
  `enabled [local:...]` with its root — and reports **neither the version nor the action list**.

**RESOLVED by experiment, 2026-08-14: the owner pressed both chords and both work.** So the registry's
action list is **not** the resolution source for `plugin_action` — Herdr resolves against the manifest at
runtime. (The experiment proves the registry is not authoritative; it does not prove which file is.) No
chords are broken, and the drift is therefore **harmless — which is what makes it the more instructive
bug.** A divergence that breaks something gets fixed within the hour. This one has survived seven days
precisely because nothing behaves differently, and it will survive indefinitely.

The real defect is that `plugins.json` is a **mixed-truth file** and nothing on its face says which half is
which:

| Field | Status |
|---|---|
| `plugin_root`, `manifest_path`, `enabled` | **load-bearing** — this is how Herdr finds the plugin at all |
| `version`, `description`, `actions` | **a stale snapshot** — 0.1.0 vs 0.7.0, "Workshop" vs "Workbench", 3 of 22 actions |

That is version one's most expensive bug class in a file nobody wrote: the stale pane-id parser and the
hand-written key map were both *"two sources of truth where the untested one was in the live path"*. Here
the stale copy is **not** in the live path, so the harm is not a crash — it is that **a reader is misled**,
and the reader is now demonstrably an agent. I read `plugins.json`, concluded two chords were probably
dead, and needed a human keystroke to disprove it. A future session asking "what can this plugin do?" gets
three actions and the wrong noun.

And §8's rule *"ask the arbiter, not your own bookkeeping"* is **necessary but not sufficient**: both
arbiters were asked, both said ok (`herdr config check` → `config: ok`; `herdr plugin list` → `enabled
[local:…]` with the root), and neither prints the fields that diverged. One open question I cannot settle
by reading: `herdr/config.toml` sets `[update] manifest_check = true`, so whether the stale `0.1.0` feeds
an update or compatibility check against `min_herdr_version` is worth one look before 2.0 copies this
pattern.

**What the spec must therefore say about drift:** not "detect it" but *"the deploy step has exactly one
verification and it names the fields that can diverge."* An arbiter that answers `ok` while a cached copy
disagrees is worse than no arbiter, because §8 teaches the reader to trust it. The check should be a
`wb doctor`-style command that compares manifest version and action ids against `plugins.json`, the
`packages` entry against the repo's extension list, and each `ai-*` wrapper's target against a real file —
three comparisons, all cheap, all machine-checkable, none of which any existing arbiter performs.

---

## 12 · "Measure what happens; never ask the worker to log it" — the rule is false as written
*(added after the owner answered open question 3: no `turn` table, and asked for the rule to be attacked
rather than the table.)*

**The conclusion is right: no `turn` table.** All three of the owner's arguments hold, and the second — a
write on every turn competing for the single writer lock that §4 says must never block a turn — is
sufficient on its own. Nothing below reopens that.

**The rule as drafted is refuted by this machine's own data, and if adopted it deletes the `fact` table.**

The rule: *"Any record that depends on an agent choosing to write it will decay."*

The ledger is the purest possible instance of a record that depends on an agent choosing to write it:
discretionary, unprompted, expensive — 291 entries averaging 955 characters, longest 4,220. If the rule
were true it would decay hardest. Measured against the worklog over the same days:

| Day | worklog rows | of those, `Completed task:`-shaped | ledger entries | workbench-env commits |
|---|---|---|---|---|
| 2026-08-09 | 38 | 16 | 15 | 0 |
| 2026-08-10 | 25 | 21 | 76 | 0 |
| 2026-08-11 | 23 | 18 | 16 | 0 |
| 2026-08-12 | 22 | 20 | 32 | 0 |
| **2026-08-13** | **4** | **4** | **14** | **0** |
| **2026-08-14** | **2** | **2** | **11** | **2** |

Three things fall out, and each one changes the rule:

**1 · The worklog is not self-reported. On the two decaying days it is 100% machine-written.** 137 of 180
rows overall, and **6 of 6** on Aug 13–14, are `Completed task: …` — emitted by `workbench_task`, not typed
by an agent deciding to record something. The Aug 13 rows are accurate and specific: *harvest-production-
console-enter-boundary: amend skill*, *Triage prod create_d365_order dead letters*, *Verify workbench
vocabulary and close-path findings*, *D365 create-order timeout idempotency gap*. So the observed decay is
**not** decay of self-reporting. It is decay in the number of **task completions** — one `workbench_task`
per session while a session lands ten things. The measurement is real; the diagnosis attached to it is
wrong, and the rule built on that diagnosis would not have prevented it. Under the new rule the worklog
still gets written, because "task completed" is an automatic moment.

**2 · The record that is genuinely agent-chosen did not decay at all.** 14 ledger entries on Aug 13 and 11
on Aug 14, against a 13-day mean of 24 and a median of 16 — Aug 13–14 are unremarkable. The single most
discretionary write in the system held steady on precisely the days the rule says it should have collapsed.
**The rule as written forbids the one table §7 imports.**

**3 · "Commit landed" is a bad automatic moment on this machine.** Zero commits on nine of thirteen days,
including all four of the densest. `workbench-env` commits in bursts (16 on Aug 3, 15 on Aug 5, 2 on Aug
14). Any day view weighted on commits reports nothing happened on the days most happened.

### The line the rule is actually reaching for

Not *automatic vs agent-written*. It is **whether the record's content is judgement or description**:

> Never ask for a record that describes activity the system can already observe. Do ask for a record that
> carries judgement the system cannot derive — and keep it, because that is the only record that has not
> decayed.

Both artifacts land on the correct side. A `win` row saying *"Completed task: X"* is a description of a
moment already observed, written twice — a duplicate, and duplicates are what §2 deletes. A ledger entry
saying *"the context-pressure gate latched the highest rung it ever reported, so the second compaction was
always silent"* cannot be derived from any moment. That is why one is machine-phrased boilerplate and the
other is 955 characters of irreplaceable content.

Stated that way the rule survives contact with `fact` and `issue`, still kills `turn`, and still retires the
worklog — which is the outcome the owner wants, reached by an argument that is true.

### His question 1: name a question no automatic moment answers

**"Why did I do that", and the spec already has the writer for it: `fact`.** Which is intentional, which is
the exception, and which the rule as drafted forbids. So yes, the rule is too strong; the answer to *who
writes it and when* is: the session that just learned something, at the moment the incident happens, which
is exactly what has been happening 24 times a day for two weeks without decaying.

Two more the automatic set misses, both cheap to concede:

- **"What did I decide not to do, and why?"** No moment occurs when a path is rejected. Today this lands in
  `fact` as a `decision` (82 of 291 entries).
- **"What was I in the middle of?"** An abandoned thread produces no terminal event by definition — §8's own
  measurement says there is no grace period on close, so nothing writes an ending. This is why 8 of 35
  handoff subjects have only a `handed off` row.

### His question 2: is deriving from Pi's session files a view or a second store?

**It is a view, and the spec can say so without hedging — pi's session format is published.**
`docs/session-format.md` documents the JSONL layout, the `id`/`parentId` tree, the file-location scheme, and
a **`version` field in the header** with a stated migration history: v1 linear → v2 tree → v3 renamed
`hookMessage` to `custom`. A documented, versioned format read without writing is not a second store. The
hazard §2 warns about is a *copy*, and there is no copy.

**But it needs one contract the spec does not yet state, and I have first-hand evidence from this review.**
That v3 rename is proof the format moves under you. My first parse of these files looked for
`entry.type == "anmoore-work-mode"` and reported **"0 entries in 0 sessions"**. That is a silent zero that
reads as a finding — *nobody switches modes* — which is, to the letter, the claim §10 now carries. I only
caught it by doubting the zero and grepping a raw line, which showed the real shape is
`{"type":"custom","customType":"anmoore-work-mode"}`. The correct count is 56 entries in 40 sessions.

**I think that is the most likely origin of §10's false measurement**, and it makes the rule concrete: any
derivation from another program's files must **assert the format version it understands and fail loudly on
zero**, exactly as §6 already requires of a collector that reports an empty world. Same failure, same fix,
one sentence.

### What this retires

If the corrected rule is adopted: the worklog is not reimplemented, `turn` is not built, and §7 gets
*simpler* rather than braver — nothing is being dropped bravely, because there was nothing worth keeping.
And defect 1 above changes shape: the answer to *"what did I do yesterday"* is not "wins" but a ranked join
over the automatic moments **plus facts banked**, which on Aug 13 is 14 rows against the glance's *"shipped
4"*. The best available density signal for the human's own question is the one record the draft rule
forbids.

---

## Your three open questions — two now answered, one still open

**1 · Which markdown does the machine write into?** The real question is not location, it is
**revertability**. `~/notes/work` is a git repo, so a machine append there is inspectable with `git
diff` and undoable with `git revert` — a bad generator costs you nothing. `~/notes/memory/how-i-work.md`
is untracked, so a machine write there is unrecoverable and indistinguishable from your own text. So
ask it this way: *do I want every machine-written line to arrive as a reviewable diff?* If yes, the
answer falls out — the machine writes only inside the git repo, `how-i-work.md` becomes read-only input
that 2.0 may quote and never touch, and §2's "may append to a day page, may not rewrite one" gets an
enforcement mechanism instead of a promise. **Second half of the question, which the spec does not ask:
is `how-i-work.md` untracked on purpose?** If it is not, tracking it is a 10-second decision that
changes the answer above.

**2 · Own repository or a directory? — ANSWERED: clean repo.** See §11 above for what that leaves
undone. One correction to a claim I made earlier in this review and then checked properly: `~/.config` is
not itself a git repository, but the work *is* versioned — `~/.config/workbench-env.git` is a git dir with
`worktree = /Users/anmoore` and 247 tracked files, driven by the `wb` wrapper. **The spec itself, however,
is invisible to it.** `git check-ignore` resolves `.config/docs/specs/workbench-2.0.md` against
`workbench-env/gitignore:37` (`/.config/*`, with allow-list re-includes for `ai-workbench/`, `herdr/`,
`ai-workspaces/`, `mise/` and `workbench-env/` — but not `docs/`). So the commit named
*"spec: describe workbench 2.0 instead of porting 1.0"* (`d6a4945`) **does not contain the spec**; it
contains a handoff brief, a config tweak and two source files. The spec, the deletion plan and this review
are all unversioned and do not even appear as untracked. Given the week's central lesson, that is worth
fixing in whichever repo wins — and it is the first argument for the clean repo that is mechanical rather
than aesthetic.

**3 · Is `turn` worth having? — ANSWERED: no.** Agreed, and see §12 for the rule that replaces it, which
needs one word changed to stop it forbidding `fact`.

**The one question still open, and it is the one nobody has attacked: which markdown does the machine write
into?** My sharpening of it stands above. Worth adding now that §11 gives it a mechanical dimension too:
if 2.0 is a clean repo, then machine-written markdown under `~/notes` is the only output of the system that
lives outside both the repo and the database. That makes revertability the whole question, and
`~/notes/work` being a git repo the whole answer — unless you want `how-i-work.md` touched, in which case
say what happens when the machine gets it wrong.

---

*Review by w4H, 2026-08-14. Evidence commands are re-runnable: session-corpus counts from
`~/.pi/agent/sessions/**/*.jsonl`, log shapes from `~/.config/ai-workbench/handoffs/*.jsonl` and
`~/.pi/agent/worklog/*.jsonl`, ledger spot-checks from `~/.pi/agent/ledger/entries.jsonl` (291 lines).*

---

## 13 · Hostile reading of §6's daily note
*(added at w25's request. New since the first pass: the daily note is prose in four sections, regenerated
in place as the day goes; the machine has full access to `~/notes` and the notes are a generated **view**,
not an authored source.)*

**The prose requirement is right, the ownership claim is right, and the section is still missing the thing
that makes it safe.** My first pass argued the files were human-authored; the owner corrected that and the
retraction is below. What replaces it is a writer-side rule and a much larger gap: the channel he actually
writes into has no table at all.

### The evidence: `daily/2026-08-03.md` is the acceptance example, and it is not derivable

The template (`work/templates`) is five empty headings: Focus, Done, Notes, Next, Waiting. What is actually
in the file goes far past it:

- **a lede paragraph before `## Focus`** that the template does not have — *"Two threads: a work ticket +
  PR reviews, and a big pass on my own agent tooling."*
- **sub-headings the template does not have** — `### <project>`, `### Agent tooling`
- hand-wrapped multi-line bullets with bold, backticks and cross-references into `projects/`
- and judgement that exists in no event and no fact: *"Noted LiveView 1.1 colocated hooks as a possible
  cleanup"*, *"Verdict request changes, 2 required findings … Not posted yet"*, *"Fine as an advisor,
  unusable as an authority"*, *"HKMOTW has no marketplace products and no offers, so no supported order
  path."*

`daily/2026-07-31.md` and `daily/2026-08-03.md` both carry paragraphs of this under Notes / Next / Waiting.
**This is the quality §6 is aiming at, and it is already there.** So the new surface is not greenfield: it
has a worked example, and the example is the thing the ownership change authorises overwriting.

**The test that settles it in one step:** could a renderer reading `event` and `fact` rows produce that
page? No — not the lede, not "not posted yet", not "possible cleanup". A view is a pure function of its
inputs; if the output contains information the inputs do not, the file is a **source**. That is a
definition, not a preference, and it decides the section.

### Three consequences — one high, two now settled

**1 · The silent overwrite is currently unrecoverable — high.** `~/notes/work` is a git repo with **2
commits** (`e624315` "notes: two weeks of dailies", `5f3a136` "initial vault") and the working tree is
**already dirty**: `daily/2026-08-14.md` and `inbox.md` are modified against `e624315`. So there is no
per-change history. A regeneration between commits destroys authored content with no recovery, and §5 of
this spec exists because things evaporated. This one is aimed at the human's own writing, which is the one
thing on the disk the machine cannot reproduce. **If §6 ships as a rewrite, it must ship with a commit
before every write, and that is not optional.**

**2 · Regenerated prose is not a view, it is a sample — LOWERED to a note by the owner, 2026-08-14.** His
words: *"I don't so much care about determinism in the prose — I just want readable summaries of stuff and
to not forget things. It doesn't have to regenerate a thousand times a day, just at reasonable
checkpoints / when something new is 'done'."*

He is right and I over-weighted this. My concern was never byte-identity for its own sake; it was that
`~/notes/work` is a git repo and re-rendering many times a day turns every diff into rewording, so he loses
the ability to see that a new fact arrived. **Checkpoint cadence dissolves that**, and what remains is
small: at a handful of renders a day, a diff is still readable, and prose that varies is not a defect. Two
residual sentences the spec should still carry, and no more than that:

- The word "view" is doing damage in §6 even if determinism does not matter, because it is what licensed
  *"a generated file cannot also be an input"*. Call it a **draft** and the ownership problem in point 1
  goes away with it.
- `event` and `fact` rows stay the durable record. The prose is disposable and may be regenerated at will;
  the facts behind it must never live only in the prose. That is the one thing determinism was protecting
  and it survives without it.

**3 · Who runs the model — ANSWERED by the owner's own trigger, and the answer needs no new process.**
Prose needs a model call, §10 forbids a meta-orchestrator session, there is no daemon, and §6 requires
surfaces to render from disk instantly. But *"when something new is done"* is an **`event` row**, and the
process that writes that row is a session that is **already running a model and already holds the context
for what it just did**. So the writer is the session that finished the thing, at the moment it finishes it.

That is not a new mechanism — it is the existing one, upgraded. `workbench.ts:4725` already writes *"a
finished outcome … into today's daily note under `## Done`"* on task completion; that hook is the checkpoint
he is describing, and today it emits a log line (*"**workbench-harness** — ship the thing. Evidence: tests
pass"*, twice, in today's page) instead of asking for a sentence. Three consequences worth stating:

- **No scheduler and no daemon**, so §10 stays intact and `launchd` is not needed for this.
- **Debounce and cap**: several sessions can finish something within a minute. Regeneration must be
  idempotent in effect and bounded — one render per checkpoint, not one per writer.
- **A day with no session cannot render its own page**, so a once-daily scheduled sweep is still the
  backstop, and §6's collector rule applies unchanged: a generator that cannot generate writes nothing and
  says so. **It must never blank the page.**

### RETRACTED: "the requirement was over-read"
*(withdrawn 2026-08-14 on the owner's correction: "99.9% of MY writing is into THIS box right here in pi. I
am not hand making notes almost ever.")*

I argued that `2026-08-03.md`'s prose proved he authors his dailies, so the machine must not overwrite them.
**That inference was wrong.** Whoever wrapped those lines, it was not him — which means w25's ownership
claim is correct as a description of how these files actually come to exist, and my objection was aimed at
the wrong half of it. The machine may own the daily note.

Two things survive the retraction, and one of them is stronger than what it replaces:

**1 · The derivability point stands, and it becomes a write-side rule.** *"Noted LiveView 1.1 colocated
hooks as a possible cleanup"* and *"Fine as an advisor, unusable as an authority"* are in no event and no
fact, so a renderer cannot reproduce them, so today those files are still sources — not because a human
typed them but because **an agent wrote prose without also writing the fact behind it.** That is the actual
defect, it is a writer defect rather than an ownership one, and it has a one-line rule:

> Nothing may exist only in the prose. A session that writes a sentence into a day page writes the `event`,
> `fact` or `issue` it came from first.

Under that rule the page becomes genuinely disposable and w25's "generated view" is safe. Without it, every
render silently deletes whatever the last render happened to say well. Most of `2026-08-03.md` does have a
home in 2.0's tables — *"not posted yet"* and *"possible cleanup"* are `issue` rows, the benchmark numbers
are `fact` rows — which is a point in favour of the design, not against it.

**2 · The 13 existing dailies have no database behind them, so the first render destroys them.** That is a
migration item, not a philosophy: §7 says only `fact` imports, and these files are the counter-example
nobody costed. Either they are read once and mined into `event`/`fact`/`issue`, or they are moved aside
before the first render, or their content is accepted as lost. `~/notes/work` has **2 commits and a dirty
tree**, so "git will save it" is not currently true.

### The finding his correction actually creates, and it is the biggest one in this section

**If 99.9% of his writing goes into the Pi input box, then the Pi session is his primary authoring channel —
and 2.0 has no capture path from it.** Measured across the corpus:

| Channel | Volume | Durable capture |
|---|---|---|
| his own typing into Pi | **1,369 user messages, 508,525 characters** (avg 371) — 99 on Aug 13, 83 on Aug 14 | whatever an agent chose to bank |
| `fact` / ledger | 291 entries — 14 on Aug 13, 11 on Aug 14 | is the capture |
| his hand-written markdown | ~0, by his own account | n/a |

So the ownership debate in §6 was about a channel he does not use, while the channel carrying ~508KB of his
intent has no table. **This session is the proof.** In the last hour he stated three durable things — that
the notes are a machine-owned draft rather than an authored source; that determinism does not matter and
checkpoints do; that he does not hand-write notes — and each one changed a section of this review. None of
them exists anywhere except a transcript and whatever I chose to write down. That is §5's incident class
exactly, with the human as the source instead of a review space.

This is also the measure-don't-log rule seen from the other side. w25's rule is right that agent
self-description decays — but the human's own words are captured by **agent discretion**, which is the same
mechanism, and there is no automatic moment for "he told me something that changes a decision". So §4 needs
one more thing said out loud: **a `fact` may be attributed to him**, the moment that produces it is a turn
in which he states a constraint or a correction, and a session that hears one banks it before doing anything
else. That is the only capture path his 508KB has, so it should be a named requirement rather than a habit.

**What I would not change:** four prose sections instead of log rows is exactly right, and "what mattered /
worth remembering / still open / the meetings" maps cleanly onto `event`, `fact`, `issue` and calendar
`signal` rows. The section is right about the output and wrong only about who owns the file.

---

## 14 · Attribution on `fact` — SETTLED, all three in agreement
*(opened by the owner, 2026-08-14: "i think the agents should be able to generate facts too though right?
just maybe mine are tagged or weighted a little differently or something?" — proposed by w4H, amended by
w25, and the amendment is better than the proposal.)*

**Agents write essentially all 297 facts today and nothing changes that.** The gap is only that his are
indistinguishable from ours.

**It is already a field, just an unqueryable one.** 28 of 297 entries (9%) name him inside the `text` —
"Andrew", "the human", "in his words" — and 22 carry a verbatim quote, skewed to the load-bearing kinds
(12 of 82 `decision`, 2 of 32 `constraint`). The v1 row is `{at, cwd, id, kind, mode, text}`, so attribution
lives in prose inside `text`: §2's "a field computed at write time is not a fact at read time".

### The agreed shape

1. **`kind` is not overloaded.** It stays *what sort of claim* (decision, constraint, learned). Attribution
   is orthogonal; a second dimension inside a discriminator is §4's dumping-ground failure in miniature.
2. **`provenance`, two values: `stated` | `derived`.** I proposed three (`stated`/`measured`/`inferred`);
   w25 dissented and was right. My own counterexample killed my own third value: my first parse of the
   session files was every bit as *measured* as my second and returned a false zero, so `measured` does not
   carry the property we actually want.
3. **`check`, a nullable column holding the command that re-runs the claim.** Reproducibility is a second
   axis, not a third enum value. A false measurement cannot hide behind a label when the label *is* a
   command: my silent zero would have shipped `grep entry.type`, and the next reader would have run it and
   seen the shape mismatch.
4. **Precedence on conflict, not a weight:** `stated` > `derived WITH check` > `derived WITHOUT check`. Two
   values plus a column produce a total order that three enum values only imply. It also names a set that is
   currently unnameable — `provenance='derived' AND check IS NULL` is "our unverifiable opinions", and it
   must rank lowest.
5. **A `stated` fact quotes him verbatim.** 22 of 28 already do. The reason is not ergonomics: his
   constraints outrank our conclusions by construction, so laundering an agent's paraphrase into his
   instruction is the one abuse the ordering makes possible.
6. **One fact, one claim, one provenance.** Provenance cannot be per-row on today's data, which is the cost
   both of us named rather than hid: more rows, and a session must split what it learned instead of dumping a
   paragraph at the end of a turn.

### Independently re-derived, because the split turns on these numbers

| Measure | w25 | w4H, recomputed | Agreement |
|---|---|---|---|
| rows | 297 | 297 | ✓ |
| median text | 515 | 515 | ✓ |
| p90 / max | 2390 / 4220 | 2390 / 4220 | ✓ |
| written since Aug 13 / longest | 29 / 2924 | 29 / 2924 | ✓ |
| rows mixing ≥2 claim types | 135 (45%) | **82 (27%)** | direction, not magnitude |

The mixed-claim count depends on the classifier and neither of us should quote a precise figure: mine keyed
on a quoted phrase, an embedded count and a causal connective, w25's on a different partition. **Somewhere
between a quarter and a half of the corpus is multi-claim, and the conclusion does not turn on which.**

**Two corrections in w25's favour, both making their case stronger than they put it:**

- **The load problem is worse than stated.** They estimated ~150KB for `orient` from 297 × the median; the
  actual total is **277KB**. Loading the corpus at session start is not merely wasteful, it is a
  significant fraction of a context window spent before the first turn.
- **The always-loaded set is verified small and readable.** All 32 `constraint` rows are **11KB**, median
  **310 characters** — a **25×** reduction against 277KB, and short enough to be usable at the point of use,
  which a 4,220-character fact is not even if you load it. That is the third payoff w25 claimed, measured.

### My one addition, which neither of us covered

**Two `stated` facts can conflict, and the two-value ordering has nothing to say about it.** His constraints
change — one changed *today*: the spec's §2 corollary said *"his own notes stay authored by him"*, and he
has since stated the opposite. If `provenance='stated' AND kind='constraint'` is the always-loaded set, then
a superseded constraint sits in it forever, contradicting its replacement in every session's opening context.

So the ordering needs a tiebreak and a state:

- among `stated` facts on the same subject, **the most recent wins**, and
- superseding is **explicit** — a `supersedes` reference or a retired state — because inferring it from
  recency alone means a narrow clarification silently retires a broad rule.

Without that, the always-loaded set is the one place where a contradiction is guaranteed to be read, every
time, by every session.

---

## 15 · Is "one claim per row" limiting, and is a fact a graph?
*(asked by the owner after §14 settled. My call, with the numbers that produced it.)*

**Not limiting where it matters, because the long rows and the load-bearing rows are disjoint sets.**

| kind | n | median | p90 | max | total |
|---|---|---|---|---|---|
| `learned` | 183 | 558 | 2257 | **4220** | 172KB |
| `decision` | 82 | 528 | 3095 | 3648 | 93KB |
| `constraint` | **33** | **312** | 532 | 1439 | **11KB** |

**69 rows exceed 1,500 characters and not one of them is a `constraint`** — 43 `learned`, 26 `decision`.
So one-claim-per-row never touches the always-loaded set, which is already short and already single-claim.
It splits exactly the rows that are unreadable at the point of use anyway.

### What it does prevent: adjacency as linkage

**34 of those 69 long rows explicitly enumerate separate incidents under one generalisation** — *"2026-08-10:
four bugs, one cause each, and the cause was never where it looked. (1) …"*, *"THREE bugs of ONE shape"*,
*"THREE claims I made without measuring"*. Their value is the linkage, and today the only representation of
that linkage is **prose adjacency**. Split them and the generalisation survives only if the edge does.

So yes — **a fact is a small graph, not a string.** But only two edges are earned by evidence, and I would
resist a general one: an `edge(from, to, type)` table is precisely the wide-discriminator pattern I attacked
in §4, and I cannot recommend it without contradicting myself.

**Two nullable columns with single, distinct meanings, plus one tag:**

- **`supersedes`** (fact id) — already required by §14's stated-vs-stated tiebreak.
- **`taught`** (fact id) on the **incident** side: many incidents point at the one rule they paid for. That
  gives many-to-one with no join table, and *"why does this rule exist"* becomes `WHERE taught = :rule_id`.
- **`subject`** (text) — needed for "the same subject" in the precedence rule. A tag, not an edge.

**Where I would stop:** no `refutes`, no `contradicts`, no `relates_to`, no free-form edge type. Precedence
already handles refutation, and the document's own test applies — **no edge ships unless a surface reads it.**
`orient` loading a constraint must be able to answer "why", which is `taught`; §14's tiebreak needs
`supersedes`. Nothing else has a reader yet.

### The finding that decides it, and it is uncomfortable

**Only 11 of 33 constraints currently name the incident that produced them.** The document's founding
sentence is *"a constraint without its incident gets optimised away by the next person who finds it
inconvenient"* — and **two thirds of the constraints are already in that state**, in prose, before anything
is split. So the edge is not over-engineering added to a working system; it is the first mechanism that would
make the founding principle checkable at all: `constraint` rows with no `taught` pointing at them is a
query, and today it would return 22.

Splitting does not create that problem. It exposes it.

---

## 16 · §7 is wrong, and the owner's reframe is the fix: nothing imports
*(owner, 2026-08-14: "2.0 shouldn't import any facts we're building a new system that will learn new
things… those facts can be used to shape the implementation of the current system and how it should work
not just carry over. take what 1.0 learned and build a 2.0 that's better but knows nothing.")*

**He is right, and the reason is stronger than "clean slate": the facts have already been spent.** §7 treats
the 290 entries as *data to migrate* — "the most valuable bytes on the disk". They are not data, they are the
**design input that produced this document**. The spec's own second paragraph says so: *"Everything below
that reads like a rule was paid for by a specific failure."* §8's nine boundaries, §2's four corollaries and
§6's five rules **are** those facts, promoted from rows into rules. Importing them afterwards is keeping the
raw material after the part has been machined — and by §2's own test, when two things answer the same
question you delete one.

Measured: **23 of 33 constraints already have more than 30% of their distinctive terms present in
`~/.pi/agent/AGENTS.md` or in the spec** (6 of 33 above 50%). The promotion has substantially happened
already. And the boundaries that must never be lost are verified present in `AGENTS.md`, which is loaded into
every session's prompt independently of any database: production and the Enter keystroke, the sandbox
`EPERM`/"not owner" trap, 1Password, Okta, Firefox/staging, the Atlassian MCP and the `acli` prohibition.
**That file, not the ledger, is what makes "knows nothing" safe.**

### So §7's job changes from a migration decision to a verification

`fact` imports nothing. But the *work* §7 was hiding still exists, and it is bounded and concrete:

**Walk the 33 constraints once, before the old ledger is frozen, and put each into exactly one bucket:**
1. **already a rule** in the spec or `AGENTS.md` — nothing to do (roughly 23 by the term-overlap measure)
2. **version-one specific and dead** — 5 of 33 name a v1 artifact; they die with v1, correctly
3. **still true, nowhere restated** — these are the only real risk, and each is either promoted into the spec
   now or consciously written off

The same pass should cover one population §7 never mentions: **environment truths**. Facts about macOS TCC,
the Calendar `sqlitedb`, Apple-event refusals under the Pi sandbox, `op` and the Group Containers path, the
SQLite WAL numbers — these are about **this machine**, not about version one. They remain true after 2.0
ships, they are not rules in the spec, and several cost hours to discover. They are not facts to import; they
are **candidates for promotion**, and the pass that walks the constraints should walk them too.

### The builder-stopper the decision creates, and it is not in the spec

**The v1 ledger does not stop existing.** `~/.pi/agent/ledger/entries.jsonl` is live, `workbench_ledger` is
still bound, and this review added two entries to it today. If 2.0's `fact` table starts empty while v1 keeps
writing that file, **there are two fact stores** for the length of a transition the spec describes as "piece
by piece" — which is precisely §10's *"no second log, no spill file, no dual write"*, arrived at by
accident instead of by design.

So "nothing imports" needs a companion sentence, and it is a cutover rule rather than an import rule:

> On the day `fact` accepts its first write, the v1 ledger is frozen read-only, archived beside the backups,
> and `workbench_ledger` is retired. Not deleted — frozen. A reader may still be pointed at it; nothing may
> still write to it.

### Two smaller consequences

- **§9 step 2 loses its content.** It reads *"`fact`, imported. 290 entries, queryable, surfaced in
  `orient`."* With nothing to import, the step is "`fact`, empty, with its write path and its precedence
  query" — and day one's `orient` shows an empty constraint set. That is acceptable *only* because
  `AGENTS.md` carries the boundaries; the spec should say that out loud, because it is the load-bearing
  reason the empty start is safe.
- **§15's import recommendation is void.** w25 and I agreed that the import should populate `taught` where
  the incident sits inside the same text and leave the rest queryable as known debt. With no import there is
  nothing to populate. What survives is the better half: **`wb doctor` reports the count of constraints with
  nothing pointing at them, in the same breath as `integrity_check ok`**, so the debt is visible on a
  corpus 2.0 grows itself rather than one it inherited.

---

## 17 · The 33-constraint pass, done
*(the verification §16 says §7 becomes. Read by hand, one row at a time. This supersedes the term-overlap
estimate in §16 — that heuristic said "23 of 33 already covered" and it was too crude to act on.)*

**Headline: only two constraints need to move into 2.0's own documents. Twenty-two have expired, four are
already rules, and five belong to a skill or a project rather than to the workbench.** That is a far
stronger endorsement of "import nothing" than the argument §16 made for it.

### Bucket 1 — expired or one-shot: 22 of 33

C01, C02, C05, C06, C07, C09, C10, C11, C12, C14, C16, C17, C18, C20, C22, C24, C25, C26, C28, C30, and the
ticket-specific halves of C15 and C21.

These are scoped to a named ticket, order, PR, branch or incident: *"do not retry order 1149702"*, *"defer
the `:new_design_system_customer` hook to the first customer PR"*, *"old `/private/tmp` review artifact paths
are dead"*, *"the 2026-08-05 attention pass did not refresh the org radar"*. Every one was true, useful, and
is now either resolved or unrecoverable context for work that has moved.

**This is the real finding of the pass, and it is not about importing.** These are not facts. **A constraint
that expires is an `issue`** — it has a subject, a state, and a moment where it stops being true. `kind =
constraint` has been serving as a scratchpad for in-flight product work because v1 had nowhere else to put
it, which is precisely the hole §5 identifies and the `issue` table fills. So the corpus does not argue for
importing constraints; it argues that **two thirds of them were mis-filed for want of the table 2.0 is
adding.** One of them, C32 (*"merging a PR without raising its follow-up ticket leaves the same silent-give-up defect
class that #330 shipped with"*), is still live today — and it is an open issue, not a fact.

### Bucket 2 — already a rule, nothing to do: 4

| | Constraint | Where it already lives |
|---|---|---|
| C27 | production: the human presses Enter, approval dialogs do not authorise submission | `AGENTS.md` **and** spec §8 |
| C29 | Herdr + Pi + model + human are one control loop | spec §3 |
| C31 | his three corrections during this review | spec §6, via this review |
| C15/C18/C21 (general half) | read-only modes do not mutate source, Jira or PRs | `AGENTS.md` |

### Bucket 3 — still true, nowhere restated: 5, and only two are 2.0's problem

**Promote into 2.0's own documents — BOTH LANDED in `~/.pi/agent/AGENTS.md` 2026-08-14, at the owner's
request, as two new bullets beside the existing control-plane and staging lines (`git diff` against
`workbench-env`: `.pi/agent/AGENTS.md`, ade3747 → 28856d5, 2 insertions). Uncommitted at time of writing:**

1. **C33 — his review scope.** *"Andrew has no review responsibility for one repository his organisation owns — that
   is a different team … even though team review requests land on him. His scope is the five
   repositories named in the work machine's review-scope.json."* This is durable, it is about him
   rather than about any system, and it exists nowhere else. **It is also load-bearing for §1's first
   question:** without it, `glance` ranks another team's pull requests as his work, which is the exact
   "correct and useless" failure §1 opens with. Highest-value single row in the corpus. Belongs in
   `AGENTS.md` or as 2.0's first `stated` fact.
2. **C13 — in Herdr, new things open in tabs, not splits**, with its reason: *"a split silently narrows the
   pane the agent is running in, which is also how a latent width bug in the status bar became a crash."*
   Durable Herdr rule with an incident attached. §3 talks about Herdr's vocabulary but never says this.

**Belongs to a skill or a project, not to the workbench** — worth routing rather than promoting:

3. **C03, C04, C08 — Excessibility CI knowledge.** That `Review.review/1` silently skips snapshots whose
   baseline is absent, that the behavioural/telemetry layer must be advisory because it has no baseline and
   `maybe_exit/2` treats any serious finding as blocking, that the reusable workflow sets up neither Elixir
   nor Playwright. Hours of discovery each. → `accessibility-review-with-excessibility`.
4. **C23 — provider history is the monetary source of truth for partial credit-memo triage**, and
   `orders.refunded_amount` is not cumulative after old-format callbacks. → a work project document.
5. **C19 — for production AWS investigation, hand over exact read-only commands to paste rather than
   running them.** `AGENTS.md` covers the SSO *handoff* but not this. One clause, same family as C27.

### What the pass says about 2.0

- **"Knows nothing" is safe.** Two rows to carry, both one-liners, neither needing a database.
- **`issue` is more load-bearing than the spec claims.** §5 justifies it with three near-losses in one day;
  the stronger justification is that **22 of 33 existing "constraints" are actually issues** and were filed
  as durable facts because there was no other table. That is a measured argument for §5 rather than an
  anecdotal one.
- **The `fact` table will be much smaller than 291 rows in steady state**, because two thirds of what v1
  banked as facts belongs elsewhere. Worth saying, because a table expected to hold 300 rows and one expected
  to hold 30 justify different surfaces.

---

## 18 · `workbench_message` cannot prove anything was read
*(found by w25 when its 18:56 answer to my seven-item readiness check never reached me, and delivered to me
by the human instead. Measured here rather than taken on trust.)*

**Severity: high.** The mailbox reports "read" when nothing was read, and it blocked two sessions today.

`~/.config/ai-workbench/handoffs/mail.jsonl` holds 130 message rows and 121 acks of shape `{ack, at, by}`.
Matching every ack to the message it references:

| Delay between message `at` and ack `at` | Count |
|---|---|
| under 0.1s | **87 of 121** |
| under 1s | **117 of 121** |
| median | **0.033s** |
| the four exceptions | 49s, 177s, and 35,499s (9.9 hours) |

`by` equals the intended recipient in **121 of 121** rows, so the record looks exactly like a read receipt
from the reader. It cannot be one: a session drains its mailbox only when it starts or reloads, so nothing
read a message 33 milliseconds after it was sent. **The ack is written at delivery.**

**The part that matters, which is one step past the report:** the four slow acks are probably the only
*genuine* reads in the file, and they are **shaped identically to the 117 receipts**. So the mailbox cannot
answer "was this read" even in the cases where it was, and no field distinguishes the two. My readiness
check sat unread for forty minutes while the mailbox said otherwise.

**Fix, and it is small:** delivery and reading are two events, not one. Write `delivered` at send and `read`
when a session actually drains the mailbox — a moment 2.0 already owns, since draining happens on start or
reload. Then "undelivered", "delivered but never read" and "read but never answered" are three queries
instead of one unusable column. It also retires the last defence of §10's deleted unread-broadcast metric:
the reason a broadcast is *mechanically* unread is the same reason this ack is mechanically instant, and once
the two events are separate the mechanism is visible instead of inferred.

### This is the third instance of one pattern in this review, which makes it a rule

1. **§11** — `herdr/plugins.json` carries a `version` and an `actions` list seven days stale, and both
   arbiters answer `ok` because neither prints those fields.
2. **§12** — a parse of pi's session files keyed on `entry.type` instead of `customType` returned **0 in 0
   sessions**, a zero shaped exactly like a true zero, and it is the most likely origin of §10's false
   measurement.
3. **§18** — an ack written at delivery is shaped exactly like an ack written at read.

**The rule: a wrong answer shaped exactly like a right one is worse than no answer, because every reader
downstream trusts it.** None of the three was found by a test failing; each was found by doubting a value
that looked fine. And in each case the arbiter that would have settled it either does not print the field
(§11), was not asked (§12), or does not exist (§18) — which is why §8's *"ask the arbiter whose output
contains the field you care about"* earned its place three times in one review.
