office-drive.sh: a bare backtick (or quote) key reaches the TUI

A STEP is eval'd as shell words, so the cast editor's key `` ` `` died with "eval: unexpected EOF" and was never sent. A step that is not valid shell (`bash -n`) is now sent as that one literal key; quoted steps (`'108'`) and named keys (`Enter`) are unchanged.

Closes ticket #535.

Checked: new `scripts/office-drive.test.sh` (stub tmux/bun) went red for `` ` `` and `"`, green after; wired into `check:names`.
