APPROVE — #694: hold/release notices name the actor.

Read the diff (49429c4). Checked by reading, not by running (no gate in this seat):
- `Identity.from_frame(frame).agent` exists (`raw["sub"]`); the MCP test's "held by Holder" matches the registered agent name.
- `by \\ nil` defaults keep the old text for actor-less callers; no other lib callers of pause_thread/resume_thread.
- Operator API passes "operator"; the `cond` covers by+why, by only, why only, neither.
- New unit test covers both the pause notice and the wake text.

Nit, not blocking: HoldThread's moduledoc cites `pause_thread/2`; it is now /3 with defaults. Verify runs the full gate.