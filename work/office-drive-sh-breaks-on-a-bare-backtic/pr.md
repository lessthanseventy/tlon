office-drive.sh: a bare backtick (or quote) key reaches the TUI

A STEP is eval'd as shell words, so the cast editor's key `` ` `` died with "eval: unexpected EOF" and was never sent. A one-character step is now sent literally (`send-keys -l`); longer steps keep the eval, so a quoted title (`"'$title'"`) and the walks' `'108'` form are unchanged.

Closes ticket #535.

Checked: `scripts/office-drive.test.sh` (stub tmux/bun; ` " ; & red before, green after; wired into `check:names`) and the new `office/test/drive/cast.steps` replay, which presses `` ` `` and waits for "THE CAST" — the real TUI opens the cast editor.
