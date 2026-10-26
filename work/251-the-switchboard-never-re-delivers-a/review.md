# Review — workline 251-the-switchboard-never-re-delivers-a, round 3 (a3100f8)

**Verdict: approve.**

## Last round's finding

Fixed. `git diff 277c5f9..HEAD -- . ':!work/251-…'` is empty: a3100f8 touches only pr.md, and the file now reads exactly the replacement I escalated (message #14257): "no longer hands back a tlon-authored post that names nobody", the fixed-addressee carve-out named, and "58 tests, 0 failures". The PR body and the code agree on the point the review turned on.

## The change, as it stands

`unheard?/1` for a tlon-authored message is `reply_author(message) ++ mentioned_agents(message) != [] and unheard_by_addressees?(message)` (switchboard.ex:161); every other author goes through `unheard_by_addressees?/1` unchanged. Two tests cover both arms: the addressee-less "▶ VERIFY" notice is never handed back (0, delivered_at untouched), "@Sandra ✓ check passed" still is (1). That is the ticket's fault — the post that resolves to whoever leads *now* — and no wider.

CHECKS: `mise run check` exit 0 at 20:26:48Z on the branch at a3100f8 (the `tlon/check` status line says "not posted" because the server's checkout was dirty during the run; the gate itself passed). No bench_contrast row in the brief.

## Findings

None blocking.

Not verified by me beyond reading the diff, the callers and the CHECKS rows: I ran nothing.