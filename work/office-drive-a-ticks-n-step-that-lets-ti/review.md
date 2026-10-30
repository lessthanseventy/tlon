APPROVE.

Read the full diff against origin/main (script, test, skill doc, drive_smoke keys doc, pr.md). Ran `bash scripts/office-drive.test.sh` myself: all cases ok, including `ticks:3` (no keys), `ticks:20` (3 captures) and the seen-union listing the balloon. I did not run the server tests the pr.md cites.

- No `set -e` in the script (`set -uo pipefail`), so the `[ … ] && capture` tail in the loop can't abort it.
- Seen-union is deduped (`awk '!s[$0]++'`): a balloon across several captures lists once; static room text lists once too. Noisy but fine.
- Scope matches the ticket decision: no TUI change, no balloon export.
- Docs are in the same commit (SKILL.md, script header, tool description).