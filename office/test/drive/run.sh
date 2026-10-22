#!/usr/bin/env bash
# Replay a drive walk: one office-drive step per line of <walk>.steps (blank lines and # lines skipped),
# in the sandbox, on a throwaway TMPDIR so the toy's hall/pets/store/looks start clean (the sandbox keeps
# them under $TMPDIR/tlon-sandbox and would otherwise carry one run into the next).
#   office/test/drive/run.sh [walk]            default: walk (the whole sweep)
#   OFFICE_COLS=60 OFFICE_ROWS=30 office/test/drive/run.sh walk     a narrow window
#   OFFICE_WIDE=1 office/test/drive/run.sh walk                      the wide room (280x75)
# Exit 1 when a step is malformed or the TUI wrote to stderr.
# A mouse click is a step: click:TEXT[@DX,DY] (a click on the label TEXT shows; a missing label fails the replay).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
walk="${1:-walk}"
mapfile -t steps < <(grep -vE '^\s*(#|$)' "$here/$walk.steps")
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
TMUX_TMPDIR=/tmp TMPDIR="$tmp" OFFICE_SANDBOX=1 "$here/../../../scripts/office-drive.sh" "${steps[@]}" 2>&1 | tee "$tmp/out"
# office-drive.sh exits 1 when the TUI wrote to stderr; a bad step is what else makes a replay fail
! grep -qE '^=== stderr|eval: line|^=== no such text' "$tmp/out"
