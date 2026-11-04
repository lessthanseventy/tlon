Closes #718.

`adapters/skills/coordinate-via-funes/SKILL.md` said, in the "Post as you work" bullet, that a seat never passes a thread id. The wake bullet below (and the `post_message` schema) pass `thread_id` to answer on another thread a wake names, so the first bullet overstated the rule. This scopes the no-thread-id rule to the seat's own thread and says when `thread_id` is passed. Docs only; no other line touched.

Checked: `mise run check:names` (exit 0; it is the only check that reads this file).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
