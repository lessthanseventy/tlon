#!/usr/bin/env bash
# The glossary gate (docs/glossary.md), called by check-names.sh:
#   (g1) every `Server.*` module, `mise run <task>` and `scripts/*` file in a "lives in" cell exists
#        (a cell from `pending:` on is a rename not yet made, so it is skipped);
#   (g2) the retired words (console, cockpit, funes as a product, lobby as the screen) are absent
#        from every AGENTS.md, office/tui/*.ts and docs/plans/ file dated 2026-10-19 or later.
# Usage: check-glossary.sh [root]; exit 1 on any miss. A root without mise.toml skips the task check.
set -uo pipefail

root="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"
cd "$root" || exit 1
fail=0
miss() { echo "check-glossary: $*"; fail=1; }
warn() { echo "check-glossary: warning: $*"; }

glossary=docs/glossary.md
[ -f "$glossary" ] || { echo "check-glossary: no $glossary"; exit 1; }

# ---- (g1) "lives in" names exist --------------------------------------------------------------
defined="$(grep -rhoE 'defmodule +[A-Z][A-Za-z0-9_.]*' server/lib 2>/dev/null | awk '{print $2}' | sort -u)"
known=""
if [ -f mise.toml ]; then
  known="$(mise tasks ls --json 2>/dev/null | jq -r --arg root "$root/" '.[] | select(.source | startswith($root)) | .name' | sort -u)"
  [ -n "$known" ] || miss "(g1) \`mise tasks ls\` lists no task from $root"
fi
n_live=0
# Table rows only; the third column is "lives in".
while IFS= read -r cell; do
  cell="${cell%%pending:*}"
  term_line="$cell"
  while read -r name; do
    [ -n "$name" ] || continue
    n_live=$((n_live + 1))
    grep -qxF "$name" <<<"$defined" || miss "(g1) $glossary: $name — no defmodule in server/lib"
  done < <(grep -oE '\bServer(\.[A-Z][A-Za-z0-9_]*)+' <<<"$term_line" | sort -u)
  while read -r task; do
    [ -n "$task" ] || continue
    n_live=$((n_live + 1))
    [ -z "$known" ] || grep -qxF "$task" <<<"$known" || miss "(g1) $glossary: \`mise run $task\` — not a task \`mise tasks ls\` knows"
  done < <(grep -oE 'mise run [A-Za-z0-9:_-]+' <<<"$term_line" | sed 's/^mise run //' | sort -u)
  while read -r file; do
    [ -n "$file" ] || continue
    n_live=$((n_live + 1))
    [ -e "$file" ] || miss "(g1) $glossary: $file — no such file"
  done < <(grep -oE 'scripts/[A-Za-z0-9_./-]+' <<<"$term_line" | sort -u)
done < <(awk -F'|' '/^\|/ && NF >= 5 && $2 !~ /^ *(term|-+) *$/ {print $4}' "$glossary")

# ---- (g2) retired words -----------------------------------------------------------------------
# Spans that are not prose: plan filenames, `code.method` calls, `<ns>:console` mise tasks, and
# the server's node name `funes@`.
strip='s#[A-Za-z0-9_./-]*docs/plans/[A-Za-z0-9_.-]*##g; s#console\.[a-z]+##g; s#[a-z]+:console##g; s#funes@##g'
# Scan `files` for ERE `pat`; $1 is "fail" or "warn".
scan() {
  local mode="$1" what="$2" pat="$3"; shift 3
  local f hit
  for f in "$@"; do
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      if [ "$mode" = fail ]; then miss "(g2) $f:$hit — retired word ($what)"; else warn "$f:$hit — retired word ($what)"; fi
    done < <(sed -E "$strip" "$f" | grep -noiE "$pat" | sed -E 's/^([0-9]+):.*/\1:/' | sort -u | while IFS= read -r l; do echo "${l}$(sed -n "${l%:}p" "$f" | cut -c1-90)"; done)
  done
}

agents="$(find . -path '*/node_modules' -prune -o -path '*/deps' -prune -o -path '*/_build' -prune -o -path ./.worktrees -prune -o -path ./.git -prune -o -name AGENTS.md -print | sort)"
tui="$(ls office/tui/*.ts 2>/dev/null)"
plans="$(ls docs/plans/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-* 2>/dev/null | awk -F/ '{ if (substr($NF,1,10) >= "2026-10-19") print }')"
all="$agents $tui $plans"

scan fail 'console'  '\bconsole\b' $all
scan fail 'cockpit'  '\bcockpit\b' $all
scan fail 'funes as a product name' '\bfunes\b' $all
# The screen is the room (`ctrl+] room`). office/tui's hints and office/AGENTS.md still say lobby
# until B3 of the cohesion pass renames them: a warning here, a failure in new plans.
lobby='ctrl\+\] *\(?(is |to )?(the )?lobby|"ctrl\+\]", label: "lobby"'
scan fail 'lobby for the screen' "$lobby" $plans
scan warn 'lobby for the screen — task B3' "$lobby" $agents $tui

if [ "$fail" -ne 0 ]; then echo "check-glossary: FAILED"; exit 1; fi
echo "check-glossary: ok — $n_live \"lives in\" names exist, no retired words in AGENTS.md, office/tui or new plans"
