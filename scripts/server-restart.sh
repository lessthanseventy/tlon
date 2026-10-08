#!/usr/bin/env bash
# server:restart's door: restart the always-up service only when that cuts nothing off
# (Server.Rollout.busy/0: a coworker mid-turn, a verify or a landing running, whose gate script
# dies with the server). `--force` restarts anyway. A server that can't be asked (down, or not
# answering) is restarted: that is what a down server needs.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cli="${TLON_CLI:-$root/scripts/tlon-cli.sh}"

if [ "${1:-}" != "--force" ]; then
  answer="$("$cli" quiet 2>/dev/null)"
  if [ "$(printf '%s\n' "$answer" | head -n 1)" = "busy" ]; then
    echo "server:restart refused — restarting now would cut off:"
    printf '%s\n' "$answer" | tail -n +2 | sed 's/^/  /'
    echo "wait for it to finish, or restart anyway: mise run server:restart -- --force"
    exit 1
  fi
fi

# the workers hear it as a notice on their threads (it wakes nobody); a server that can't be asked is skipped
"$cli" announce-restart "${TLON_RESTART_WHY:-the operator ran server:restart}" >/dev/null 2>&1 || true

systemctl --user restart tlon && systemctl --user --no-pager status tlon | head -12
