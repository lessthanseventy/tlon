APPROVE. Right then: the spots read clean.

Verified: diff vs origin/main (publish.ex, workline_publish_test.exs, pr.md); `run_verb test test/server/workline_publish_test.exs` → 40 passed, 0 failed.

- pr_title takes the first non-blank trimmed line, slug when none, so no empty --title. Over 256 it is cut on a word (≤255 chars + "…").
- The full title heads the body only when the PR title differs, so a short title is not repeated. Tests cover the long, short, blank-first-line and all-blank cases.
- Minor, not blocking: if the 256th char lands exactly on a space, cut_title drops one whole word it could have kept.
- Not verified: the full `check` gate (verify runs it on the server).