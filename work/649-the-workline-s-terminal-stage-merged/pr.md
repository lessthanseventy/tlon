The workline's terminal stage `merged` is renamed `landed`. Since a516ac8 the stage is reached when the local gate passes, while the PR still waits on GitHub; the thread closes only when GitHub says MERGED. The old name claimed something that had not happened.

- Server: the stage list, transitions, brief, ledger (`summary.landed`), docs map, MCP tools, office Needs.
- Data: a migration moves existing `merged` rows to `landed` and swaps the `thread_stage_check` constraint (down reverses). Chosen over a dual-read so the stage has one spelling.
- Office: the stage ring, the desk's progress bar and the card tests.
- Docs: README, the glossary row for `landed`, and the stage ring in the cohesion plan.
- Unchanged on purpose: GitHub's MERGED state, `gh pr view` parsing, and `Workline.merged/2` (GitHub merged it).

Closes #649.

Checked: the landing, workline, ledger and brief tests went red on `"merged"` and are green on `landed`; `scripts/check-names.sh` is ok; the full `check` is run on the head (result below).
