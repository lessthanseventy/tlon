#!/usr/bin/env bash
# watch — re-run a command every time watched files change, printing cap's signal each run.
# Register it once, then just edit: you get pass/fail automatically, with no turn spent
# re-running tests by hand. The point (root AGENTS.md): stop manually re-running after every
# change — let the watcher tell you when something goes red.
#
#   scripts/watch.sh mise exec -- mix test              # watch cwd, run the suite on change
#   scripts/watch.sh -w modules/funes -- mise exec -- mix test
#   scripts/watch.sh bun test path/to/thing.test.ts     # a narrower scope
#
# For an AGENT: run it in the background (Claude Code: Bash run_in_background — the harness
# re-invokes you when it emits a result; pi: run it in a pane). Edit, and you're pinged
# red/green. Kill it when you're done. Knobs pass through to cap (CAP_TAIL, CAP_SIGNAL).
#
# Uses watchexec when present (declared in the flake): it runs once at start, re-runs on
# change, debounces, restarts a run superseded by a newer change, and respects .gitignore —
# so _build/, deps/, node_modules/, .logs/ and result/ self-exclude with no hand-kept list.
# Falls back to a portable mtime poll where watchexec is absent.
set -uo pipefail

dirs=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -w) dirs+=("$2"); shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
[ "${#dirs[@]}" -gt 0 ] || dirs=(.)
[ "$#" -gt 0 ] || { echo "watch: give me a command to run on change" >&2; exit 2; }
cmd=("$@")

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cap="$root/scripts/cap.sh"

if command -v watchexec >/dev/null 2>&1; then
  watch_args=()
  for d in "${dirs[@]}"; do watch_args+=(-w "$d"); done
  printf 'watch (watchexec): %s   on change in: %s  (ctrl-c to stop)\n' "${cmd[*]}" "${dirs[*]}"
  exec watchexec --debounce 300ms --restart --project-origin "$root" "${watch_args[@]}" -- "$cap" "${cmd[@]}"
fi

# --- zero-dep fallback: no watchexec present ---
run() { printf '\n═══ change @ %s ═══\n' "$(date +%H:%M:%S)"; "$cap" "${cmd[@]}"; }
printf 'watch (poll): %s   on change in: %s  (ctrl-c to stop)\n' "${cmd[*]}" "${dirs[*]}"
run
stamp="$(mktemp)"; trap 'rm -f "$stamp"' EXIT
while :; do
  sleep 1
  if find "${dirs[@]}" -type f -newer "$stamp" \
       -not -path '*/.git/*' -not -path '*/_build/*' -not -path '*/deps/*' \
       -not -path '*/node_modules/*' -not -path '*/.logs/*' -not -path '*/result/*' 2>/dev/null | grep -q .; then
    touch "$stamp"; run
  fi
done
