#!/usr/bin/env bash
# Run a machine-wide script from the shared root checkout (kept at main), not from the checkout
# that launched the task:  run-from-root.sh <script-in-scripts/> [args...]
#
# A lobby/seat worktree on an old base carries old copies of the scripts the smokes and checks
# share the box through, and an old copy can sweep another run's live build. The root's copy is
# main's, so a launch from any checkout this wrapper is in runs the current one. (A checkout old
# enough to lack this wrapper still runs its own task: only a rebase fixes that one.)
set -euo pipefail
script="$1"
shift
root="$(cd "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
exec "$root/scripts/$script" "$@"
