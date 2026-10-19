#!/usr/bin/env bash
# Self-test of check-glossary.sh: a clean fixture passes, each violation fails.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bad=0

fixture() { # fixture <dir>: a clean tree
  mkdir -p "$1/docs/plans" "$1/server/lib" "$1/office/tui" "$1/scripts"
  echo 'defmodule Server.Real do end' >"$1/server/lib/real.ex"
  printf '%s\n' '| term | meaning | lives in (module/field/task) | never say |' '|---|---|---|---|' \
    '| x | y | `Server.Real` | "z" |' '| w | v | pending: `Server.Gone` | "z" |' >"$1/docs/glossary.md"
  echo 'the room, funes@127.0.0.1, server:console' >"$1/AGENTS.md"
}
expect() { # expect <want-exit> <name> <dir>
  "$here/check-glossary.sh" "$3" >"$tmp/out" 2>&1; got=$?
  if [ "$got" -ne "$1" ]; then echo "FAIL $2: exit $got, wanted $1"; cat "$tmp/out"; bad=1; else echo "ok   $2"; fi
}

fixture "$tmp/clean";                                                    expect 0 clean "$tmp/clean"
fixture "$tmp/mod"; sed -i 's/`Server.Real`/`Server.Nope`/' "$tmp/mod/docs/glossary.md"; expect 1 'missing module' "$tmp/mod"
fixture "$tmp/file"; sed -i 's#`Server.Real`#`scripts/nope.sh`#' "$tmp/file/docs/glossary.md"; expect 1 'missing script' "$tmp/file"
fixture "$tmp/ck"; echo 'the cockpit' >>"$tmp/ck/AGENTS.md";            expect 1 'cockpit in AGENTS.md' "$tmp/ck"
fixture "$tmp/fn"; echo 'funes the product' >>"$tmp/fn/AGENTS.md";      expect 1 'funes in AGENTS.md' "$tmp/fn"
fixture "$tmp/co"; echo 'the console' >"$tmp/co/office/tui/a.ts";       expect 1 'console in office/tui' "$tmp/co"
fixture "$tmp/pl"; echo 'press ctrl+] lobby' >"$tmp/pl/docs/plans/2026-10-20-x.md"; expect 1 'lobby in a new plan' "$tmp/pl"
fixture "$tmp/old"; echo 'the cockpit' >"$tmp/old/docs/plans/2026-10-18-x.md"; expect 0 'old plan is exempt' "$tmp/old"
fixture "$tmp/b3"; echo 'press ctrl+] lobby' >"$tmp/b3/office/tui/a.ts"; expect 0 'tui lobby hint only warns (B3)' "$tmp/b3"
exit "$bad"
