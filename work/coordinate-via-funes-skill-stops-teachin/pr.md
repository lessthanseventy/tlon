coordinate-via-funes: stop teaching coworkers `consult_peer` (#689)

Coworker profiles exclude `consult_peer` (only the sheriff and tertius keep it), yet the
skill told every coworker to call it. The skill now says to @mention a coworker on your own
thread, and to answer a cross-thread wake where its notice says (lead/@mentioned →
`post_message thread_id: N`, else answer here and @mention the author) — the wording 92b821e
gave the wake notice. Docs only: `adapters/skills/coordinate-via-funes/SKILL.md`.

Closes #689. Checked: no other adapter doc teaches `consult_peer`
(`grep -rn consult_peer adapters`: only a tool→"delegate" mapping in doing.test.ts);
adapters check run.
