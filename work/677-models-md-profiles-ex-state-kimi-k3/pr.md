# Say what was measured about kimi-k3's billing, not a 402 claim

Closes #677.

`docs/models.md` and the `@model_ring` comment in `Server.Profiles` said `kimi-k3` is served as extra
usage (HTTP 402) and so is kept out of the ring. That was not measured.

What changed (text only, no ring or behaviour change):

- `docs/models.md` "Two things that bite": records the 2026-10-27 measurement (HTTP 200 on the plan,
  $0 purchased, 96.8% of the session window unspent). Whether it turns 402 once the window is spent is
  marked unverified, and it stays out of the ring until that is measured.
- `server/lib/server/profiles.ex` `@model_ring` comment: the same wording.

Checked:

- `mise run check:names`: exit 0 (137 module refs, 8 mix tasks, 101 mise-task refs resolve).
- `menard run check --in server` on the committed head: see the run result posted on the thread.

No ollama.com call was made for this change; the re-measure is the operator's separate call.
