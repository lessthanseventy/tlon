# The roster — fifteen names, one coworker — design

**Date:** 2026-10-07
**Status:** approved by Andrew (calls in §7); nothing built. Six steps in §8.
**Asked:** Andrew: *"make sure hronir is doing what he should, that everyone has a clearly defined
role, and that we aren't missing any roles/SMEs/different personalities amongst the same role.
juniors vs. greybeards for like haiku->fable? … let's just use what we have and like make it what
it was supposed to be."*
**Beside:** `2026-10-07-pm-and-release-design.md` (the PM role and the release pointer).

---

## 0 · The call

The spec already says what a role is (`server/docs/spec.md` §5b): **a model, a mandate, and
the facts scoped to it.** What made the first reviewer valuable was *"a fresh context, a
different model family and an adversarial brief"*. A role states a **capability requirement**
and never a product (§8); configuration maps the requirement to a model.

Today, only the mandate half is built. There are fifteen names on the Machine bench, and each
one is its archetype's prompt on the same model, `@sonnet`, which every archetype defaults to
(`profiles.ex`). Five builders are one builder. The reviewer runs the same weights as the builder
it reviews. And the default-lead rule turns the first builder, hronir, into the place every
thread without an owner ends up.

Making it what it was supposed to be means three fields on a seat, plus fixing the routing that
ignores them:

1. **Grade**: junior, senior or greybeard. It's a capability requirement, and the operator's
   config maps it to a model.
2. **Specialty**: the area whose facts are scoped to the seat (server, office, ...). This is
   the spec's "facts scoped to it", and it's what makes someone an SME.
3. **Temperament**: presentation only, a voice. The dollhouse design already reserves this for
   coworkers, on the seat's row (that doc's §9).

Then tertius and intake route by grade and specialty, and nothing lands on a coworker by
default.

## 1 · What is there today (2026-10-07, `tlon` db)

| Archetype | Seats | Led a thread this week | Messages this week |
|---|---|---|---|
| surveyor | tertius | 1 | 28 |
| builder | hronir, daneri, emma, ireneo, nolan | hronir 7, daneri 4, emma 1 | daneri 62, ireneo 14, hronir 12, emma 2, nolan 2 |
| reviewer | lonnrot, tzinacan, ulrikke, runeberg | lonnrot 7, tzinacan 2, ulrikke 1, runeberg 1 | lonnrot 12, tzinacan 8, 1 each |
| planner | yu, averroes, beatriz | 0 | yu 30, averroes 3, beatriz 2 |
| researcher | ashe | 0 | 0 |
| sheriff | scharlach | 1 | 21 |

## 2 · What's wrong, with the evidence

- **Every seat runs the same model.** No archetype sets anything but `@sonnet`. The one override
  in `~/.config/tlon/config.json` sits under `coworkers_imported`, but `OperatorConfig` reads
  `coworkers`, so even tertius's `glm-5.2` override is never applied. The reviewer's
  "different model family" is not true of any review on this bench.
- **hronir is the catch-all, not the builder.** `Channel.designated_lead/1` gives every thread
  opened without a lead to the roster's first builder. hronir's seven threads this week include
  three of tertius's "(scratch)" checks (#128, #129, #135). For each of them hronir replied that
  it had no context, because there wasn't any: #129's question came with no banner attached.
  Meanwhile #122 "nightly gate on main" has sat open since 10-05, and #134 (Dollies step 6) is
  at build with no posts from hronir in it.
- **hronir is blocked by a tool, not by judgment.** On #131 it held `intent.md` because
  `search_history` returns only a snippet of the operator's opening message. It was right not
  to write the intent from a fragment, but a builder shouldn't have to ask for its own brief.
- **Same-role seats can't be told apart.** tertius is told to pick the lead "by fit", but
  nothing distinguishes daneri from emma, so the work goes to whoever was picked first.
  ashe hasn't led a thread or posted a message this week, and planners lead nothing because
  worklines start at `build` more often than at `plan`.
- **Etiquette drift.** Many of daneri's 62 messages on #140 are "still waiting on check"
  posts, the filler `@chat_etiquette` forbids. This is the persona-persistence gotcha: a running
  coworker keeps its old prompt until it is respawned.
- **Missing roles**, each with a night's evidence:
  - **PM**: the other doc.
  - **QA**: three of tonight's bugs (`R` relaunch, office tests in UTC, evals writing into the
    live db) were invisible to review and only found by using the product.

## 3 · Grade: junior, senior, greybeard

Grade is a requirement, written the spec's way:

| Grade | Requirement | Gets |
|---|---|---|
| junior | cheap enough to run every turn, all night | grade-1 tickets, scratch checks, mechanical fixes, first-pass review of low-risk diffs |
| senior | the strong default; long enough context for a whole module | most builds, plans and reviews |
| greybeard | the hardest reasoning on hand; scarce | grade ≥ 4 or hard-limited worklines (migrations, gates, spec), anything a senior escalated, final review of what a greybeard didn't build |

The mapping to models is configuration. **Out of the box every grade is Claude**, so a fresh
install, including a work laptop, needs one subscription and nothing else:

```json
"grades": {
  "junior":    {"provider": "anthropic", "model": "claude-haiku-4-5", "thinking": "low"},
  "senior":    {"provider": "anthropic", "model": "claude-sonnet-5", "thinking": "medium"},
  "greybeard": {"provider": "anthropic", "model": "claude-fable-5-1", "thinking": "high"}
}
```

Those are the compiled defaults. A machine with more endpoints overrides them in its own
`config.json`. This box can put juniors or a seat on the ollama bucket (pi, glm and the rest),
but never by default on a fresh install. Precedence: a seat's own `coworkers.<name>` override,
then the config's grade, then the compiled grade default.

**Two rules come with grade:**
- **A reviewer is never the builder's model.** When a workline reaches review, the reviewer
  picked must differ in model from the builder (a different family where config has one) and be
  at least the builder's grade. When no seat qualifies, the review still runs and says so in
  review.md's first line, per the spec's rule to degrade honestly.
- **Escalation goes up a grade.** A junior that runs out of nudges (`Workline.Continuation`) or
  gets a request_changes twice hands the workline to a senior of the same specialty, instead of
  only going to the sheriff.

## 4 · Specialty: the SMEs

A specialty is a tag on the seat, `server`, `office` or `general`, and it does two things.
Routing prefers a seat whose specialty matches the paths a ticket or workline touches (`server/`,
`office/`). And memory recall boosts facts banked in that area, so the office SME remembers the
office. No new archetype is needed; an SME is a builder or reviewer with a specialty.

There are deliberately only two areas plus `general`, because that is where the code is.
`adapters` joins when it has steady work. An **a11y** specialty (WCAG, contrast, the office's
`wcag.test.ts`) is the one Andrew's own expertise argues for. It's proposed as a reviewer
specialty that gets pulled onto any office diff touching palette or rendering.

## 5 · The seats, made distinct

The proposal keeps every name and archetype, gives each a grade, specialty and temperament
(Borges-shaped, since the names already are), and repurposes two surplus seats into the
missing roles:

| Seat | Archetype | Grade | Specialty | Temperament (voice) |
|---|---|---|---|---|
| tertius | surveyor | senior | general | the dry orchestrator |
| **hronir** | builder | **greybeard** | general | quiet, makes the thing real |
| ireneo | builder | senior | server | remembers everything, cites it |
| emma | builder | senior | office | precise, executes the plan as written |
| daneri | builder | junior | office | (ironically) terse; his respawn is the etiquette fix |
| lonnrot | reviewer | greybeard | general | the detective, adversarial |
| tzinacan | reviewer | senior | server | reads the script slowly |
| runeberg | reviewer | senior | office + a11y | the contrarian |
| ulrikke | reviewer | junior | general | quick first pass on low-risk diffs |
| yu | planner | senior | general | forking paths: names the alternatives |
| averroes | planner | junior | general | small plans, asks what he hasn't seen |
| ashe | researcher | senior | general | the encyclopedist |
| scharlach | sheriff | senior | general | knows where the bodies are |
| **beatriz** | planner → **pm** | senior | general | owns the release (other doc) |
| **nolan** | builder → **qa** | senior | office | stages the play and watches the audience |

**hronir becomes what it was supposed to be:** the one greybeard builder, kept for hard
builds. It stops being the default for everything. That needs the routing fix in §6.

**QA** is a new archetype: it uses the product and doesn't read the diff. Its tools are
`drive-office` and the scratch-release smoke run (release doc §4). Its prompt: after a workline
that touches a user-visible surface passes review, drive the changed path as Andrew would, and
post what you saw, with screen text. A finding goes back to the builder like a request_changes.

## 6 · Routing, so the fields matter

- **No lead by default.** `designated_lead/1` returns tertius (the workspace manager), not the
  first builder. A thread nobody staffed is tertius's to staff, or to answer itself. This is the
  single change that frees hronir.
- **tertius and intake pick by grade × specialty.** Intake already grades risk
  (`Workline.Grade`). Grade 1–2 goes to a junior, 3 to a senior, 4–5 or hard limits to a
  greybeard. Specialty comes from the paths the ticket names, and ties go to whoever has the
  fewest open threads. `staff_child` gets the pick as a default tertius can override with a
  reason.
- **A scratch check carries its context.** tertius's crew/thread brief must carry what's being
  checked: the text, file or diff. An empty brief is refused at `staff_child`/`spawn_crew`.
- **The operator's words reach the brief whole.** `search_history` (or the brief itself)
  returns the operator's opening message in full, so a builder never has to ask for it (#131).

## 7 · Decided (2026-10-07)

- **Claude by default, all grades:** Haiku junior, Sonnet senior, Fable greybeard, compiled in.
  Ollama/pi coworkers are a per-machine opt-in in `config.json`, never a fresh install's default.
- **The seat table in §5 as written**: beatriz becomes the PM, nolan QA, daneri a junior.
- **Temperament voices later.** For now each seat gets one line of voice in its prompt; the
  rest rides the dollhouse temperament card.
- **a11y is runeberg's reviewer specialty** from the start.
- **tertius's `glm-5.2` override is live** on this box: the config key was renamed to
  `coworkers` on 2026-10-07, which leaves step 1 with only daneri's respawn.

## 8 · Steps, each gated

| # | Step | Check |
|---|---|---|
| 1 | **Respawn daneri** on the current etiquette prompt (tertius's config key is already fixed, §7) | a fresh daneri posts no "still waiting" |
| 2 | **No default lead**: `designated_lead/1` → the workspace manager; empty brief refused; full opening message in the brief | a thread opened with no lead is tertius's; a `spawn_crew` with an empty brief is refused; #131's shape gets its intent |
| 3 | **Grade + specialty on the seat**: migration on `workspace_agent`, `grades` in config, model resolution order | a junior seat resolves to the junior model; a seat override still wins |
| 4 | **Routing by grade × specialty; reviewer ≠ builder model; escalate up a grade** | intake picks a junior for a grade-1 `office/` ticket, a greybeard for a migration; a review whose only reviewer shares the builder's model says so in review.md |
| 5 | **The seat table**: seed/bootstrap and the live bench updated | `select … from workspace_agent` matches §5 |
| 6 | **QA archetype**: prompt, tools, the post-review QA pass on user-visible worklines | a driven workline with a broken `R` gets a QA finding before it lands |

Step 1 is a fix and goes first. Steps 2→3→4 stack. 5 needs 3. 6 can open after the release doc's
smoke step exists.
