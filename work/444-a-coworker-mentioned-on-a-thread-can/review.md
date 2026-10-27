# Review: work/444-a-coworker-mentioned-on-a-thread-can @ 0c6127c (round 2)

**Verdict: request_changes** — the round-1 blocking finding is not fixed; the round-1 follow-up is.

Read: my review.md at c39c407; `git diff c39c407..HEAD -- . ':!work/444-a-coworker-mentioned-on-a-thread-can'` (3 files: server/lib/server/mcp/tool.ex, server/lib/server/mcp/tools/thread.ex, server/test/server/mcp/server_test.exs; +14/−7); `grep -n consult_peer server/AGENTS.md`; `git log -1 -- server/AGENTS.md` → 5880bd8, which predates the branch. CHECKS: `mise run check` green on 0c6127c (23:42Z row); no `bench_contrast` row.

## Findings

1. **server/AGENTS.md:230-232 still says the retired verb — unchanged since round 1.** The witness, verbatim on 0c6127c: "A mention of a coworker who isn't on the thread reaches them in their window on the workspace's standing thread; they answer with `consult_peer`." This change makes the line exactly wrong (the mentioned coworker now answers on the asker's thread with `post_message thread_id: N`; `consult_peer` is in the coworker profile's `excludeTools`, profiles.ex:328). Repo law: an AGENTS.md line the change makes stale is updated in the same change. The builder's round-2 commit addressed the two thread follow-ups (msg #15876) and not review.md's finding. Fix, one hunk:

```
-thread reaches them in their window on the workspace's standing thread; they answer with
-`consult_peer`.)
+thread reaches them in their window on the workspace's standing thread; the mention is the
+invitation — they answer there with `post_message thread_id: N`, `Server.MCP.Tool.may_post?/2`.)
```

## Verified this round, not findings

- Round-1 follow-up 1 (refusal text overclaimed for the `leads?/2` verbs) is fixed in 0c6127c: `acting_thread/4` takes `who`, defaulting to "its lead"; only PostMessage passes "its lead, or someone @mentioned on it". The added test mints a lobby token for a mentioned agent, calls `push_branch` with `thread_id`, and asserts the refusal says "only its lead" and does not say "@mentioned". The `import … only:` list carries `acting_thread: 4`. Correct and minimal.
- Round-1 follow-up 2 (adapters/skills/coordinate-via-funes/SKILL.md:30 still teaches `consult_peer`) is deferred as ticket #689 — out of this change's lines; not carried as a follow-up here since the ticket holds it.
- Everything verified in round 1 (`may_post?/2` = `steers?/2 or mentioned?/2`; `steers?/2` untouched; `mentioned?/2` prefilter + `Server.Mentions.names/1` exact match; switchboard wake text; commit trailers) is unchanged by 0c6127c.
