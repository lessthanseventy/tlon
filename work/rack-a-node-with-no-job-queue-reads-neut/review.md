APPROVE.

Right then. Read the diff (origin/main...HEAD): 3 office files + pr.md.

- tui/main.ts: `jobs:false` now renders a dim `○ no job queue on this node`; the header and the server are untouched. This matches the ask (#550) and is the minimal change.
- rack-card.test.ts: a new case covers header "all green", no `✕`, the neutral row, and the dim colour. The `current` fixture swap is small and the `as unknown as` cast is explained in pr.md.
- seat-status.test.ts: the guard count goes 3→4 and the comment is updated, which is correct because the new `○` line in main.ts adds one hit.

Not verified by me: I did not re-run the tests (no tmux/bun in my review sandbox); I'm relying on the author's reported green. The verify and land gates run the full suite.

No blocking findings.