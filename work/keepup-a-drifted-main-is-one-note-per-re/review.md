VERDICT: approve

Re-review of 6d44d99 on top of ebc7ddf.

Prior finding (fixed): drifted/2 cleared the note and closed the ticket on {:error, _} and :skipped. It now clears only on :forwarded; any other result is a no-op. Checked against Publish.follow_main/2: its only return values are :forwarded, :skipped, {:error, _} and {:diverged, n}, so the clause set is exhaustive. Both new tests (owned and unowned repo) cover the no-op.

Spec: one keyed note per repo, updated in place; an owned repo routes to its workspace lobby plus one drift:<repo> ticket; the operator is paged only for an unowned repo; level main clears it; Rollout moduledoc says state is lost on restart. Tests cover the spec's three cases.

Verified by me: read the diff and follow_main. Not run by me: the suite; the server's verify run recorded a green `mise run check`.

Open (non-blocking, named in moduledoc): whether the operator should hear when a live session is committing to that main.