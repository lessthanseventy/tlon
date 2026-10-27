# Review — #460 push_branch takes a named work/<caller>-* branch (round 2)

**Verdict: approve.** Head 6364eb7 (3 code commits on 3cdc19c), 83 lines across 7 files plus pr.md. The three changes andrew named in the send-back (msg #15152) are each in the delta since 9c657d2 and each does what was asked; nothing else moved except the check order emma declared.

Evidence: the server's `mise run check` row at 10:23Z (exit 0, server 2251 tests / office 924 pass) in CHECKS, run on the branch after 6364eb7 landed at 10:11Z. I read the diff and the seams it leans on; I ran nothing myself.

## The send-back, item by item

1. **Docs name the door.** `PushBranch` moduledoc: "With `branch`, a named `work/<caller's handle>-<name>` instead … never another's prefix, never a workline's slug." `Publish.push_branch/3` @doc: "a thread's, or a seat's named `work/<handle>-<name>`, see `own_branch/2`". Both true of the code beneath them.

2. **Tool-level test exists and exercises the wiring.** `server_test.exs`: a token minted for a registered `uqbar`, through the real handshake. `work/hronir-x` → isError, "bear your own name" (so `Identity.from_frame(frame).agent` reaches `own_branch`). `work/uqbar-fix` with a workline of that slug open → isError, "workline". `work/uqbar-x` → neither refusal text (the bare lobby has no repo, so the push itself is not reached; the name checks are what's under test, and that is what it asserts).

3. **A workline's branch is refused by name.** `not_a_workline("work/" <> slug)` refuses when `Repo.get_by(Server.Thread, slug: slug)` finds a thread. I checked the two facts this rests on: `Worktree.branch(name_for(thread))` is exactly `"work/#{slug}"` for any thread with a slug (`worktree.ex` L24-44), so slug equality is branch equality; and `thread_slug_index` is `UNIQUE … WHERE slug IS NOT NULL` (baseline migration L87), so `get_by` cannot raise on a duplicate. A slugless thread's branch is `work/t<id>`, which can never pass `own_branch`'s `work/<handle>-` prefix, so no gap there. The clause only matches `"work/" <> _`, and `own_branch` has already guaranteed that prefix, so no FunctionClauseError path.

4. **Order of checks.** `branch_to_push` now runs before `repo_for_thread`: a bad name is refused before a repo is resolved. Harmless and it makes the lobby test possible.

5. **Still inside the fence.** `push_branch/3`'s `\Awork/[a-z0-9][a-z0-9-]*\z` is untouched; a named branch passes `own_branch`, then `not_a_workline`, then that anchor. Hooks and plugin gate untouched; the pre-commit test on `work/uqbar-x` with `TLON_THREAD=269` stands from round 1.

6. **bench_contrast** reads `unmeasurable` (AGENTS.md is never loaded by the bench). Not green, not a regression: no finding, no habit.

## Open from round 1

Both follow-ups (moduledoc/@doc, tool-level test) are fixed in this delta. Nothing non-blocking remains.

AGENTS.md is in the diff, so the merge gate is the operator's, as graded.