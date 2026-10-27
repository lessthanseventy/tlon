# Review: work/444-a-coworker-mentioned-on-a-thread-can @ 0b077b4

**Verdict: request_changes** — one doc line left stale by the change; the code is sound.

Read: `git diff origin/main...HEAD` (6 files, +67/−8), `Server.Mentions.names/1`, the `acting_thread/3` callers, `server/AGENTS.md`. CHECKS: `mise run check` green on 0b077b4; no `bench_contrast` row.

## Findings

1. **server/AGENTS.md:229-231 still says the retired verb.** The witness: "A mention of a coworker who isn't on the thread reaches them in their window on the workspace's standing thread; they answer with `consult_peer`." This change makes that exactly wrong — the mentioned coworker now answers on the asker's thread with `post_message thread_id: N`, and `consult_peer` is on the coworker profile's `excludeTools` (profiles.ex:328), which is the fault #573 recorded. Repo law: an AGENTS.md line the change makes stale is updated in the same change. Fix (one hunk):

```
-thread reaches them in their window on the workspace's standing thread; they answer with
-`consult_peer`.)
+thread reaches them in their window on the workspace's standing thread; the mention is the
+invitation — they answer there with `post_message thread_id: N`, `Server.MCP.Tool.may_post?/2`.)
```

## Verified, not findings

- `may_post?/2` = `steers?/2 or mentioned?/2`; `steers?/2` untouched, so `advance_stage`, `submit_review`, `push_branch` (all `leads?/2`) and close keep today's rule. Matches the pinned shape.
- `mentioned?/2`: the `ilike "%@agent%"` is a parameterized prefilter; the exact match runs through `Server.Mentions.names/1` (word-boundary regex, so `@Carl?` matches and `user@Carl` does not) with a case-folded compare. A `%`/`_` in a handle only widens the prefilter, never the match. The new test covers the near-miss (`@Carlos` refused).
- Any author's mention counts, and it never expires — by design per the tech lead's shape; noting it so nobody mistakes it for an oversight.
- Switchboard wake text drops `consult_peer`, test asserts both the presence of `post_message thread_id:` and the absence of `consult_peer`.
- Commit trailers: `Co-Authored-By: claude-sonnet-5-5`, `Tlon-Model: anthropic/claude-sonnet-5-5` — consistent.
