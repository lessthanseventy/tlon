#!/usr/bin/env bash
# The names-exist gate: every name the glue (scripts, mise.toml, flake.nix, the adapters) points
# at must exist in the code it points at. Nothing compiles the shell→Elixir/mise/nix seams, so a
# rename that leaves a script calling a module that no longer exists, or an extension reading a
# file the flake stopped writing, fails silently at 2am — this catches it at commit time.
#
#   (a) Server.X.Y / Console.X.Y referenced in scripts/*.sh, mise.toml, flake.nix,
#       modules/adapters/**/*.{ts,sh}  →  a `defmodule` in modules/server/lib or modules/console/lib
#   (b) `mix server.<task>` / `mix console.<task>` in mise.toml, scripts, flake.nix
#       →  modules/<app>/lib/mix/tasks/<app>.<task>.ex
#   (c) `mise run <task>` in any AGENTS.md / README.md, mise.toml, scripts, flake.nix
#       →  a task `mise tasks ls` knows (`<prefix>:*` is a glob: some task must match)
#   (d) a ~/.pi/agent/<file>.json the adapters' TS reads  →  one flake.nix writes
#       (`home.file.".pi/agent/<file>"`, or a seeded `"$HOME/.pi/agent/<file>"`)
#
# grep/awk only, offline, a few hundred ms. One line per miss; exit 1 if any. docs/ is not an
# input: prose there may name a retired module on purpose.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

fail=0
miss() { echo "check-names: $*"; fail=1; }

# This file names the patterns it hunts; every other script is an input.
scripts="$(ls scripts/*.sh | grep -v '/check-names.sh$')"

# Everything modules/adapters ships as source, minus each package's node_modules.
adapter_sources() { find modules/adapters -path '*/node_modules' -prune -o -type f \( -name '*.ts' -o -name '*.sh' \) -print; }
guides() { find . -path '*/node_modules' -prune -o -path ./.git -prune -o -path ./docs -prune -o \( -name AGENTS.md -o -name README.md \) -print; }

# ---- (a) Elixir modules -----------------------------------------------------------------------
defined="$(grep -rhoE 'defmodule +[A-Z][A-Za-z0-9_.]*' modules/server/lib modules/console/lib | awk '{print $2}' | sort -u)"
n_mod=0
while IFS=: read -r file line name; do
  [ -n "$name" ] || continue
  n_mod=$((n_mod + 1))
  grep -qxF "$name" <<<"$defined" ||
    miss "(a) $file:$line references $name — no defmodule in modules/server/lib or modules/console/lib"
done < <(grep -noE '\b(Server|Console)(\.[A-Z][A-Za-z0-9_]*)+' $scripts mise.toml flake.nix $(adapter_sources) 2>/dev/null | sort -u)

# ---- (b) mix tasks ----------------------------------------------------------------------------
n_mix=0
while IFS=: read -r file line ref; do
  [ -n "$ref" ] || continue
  n_mix=$((n_mix + 1))
  task="${ref#mix }"          # server.promote_fact
  app="${task%%.*}"           # server
  [ -f "modules/$app/lib/mix/tasks/$task.ex" ] ||
    miss "(b) $file:$line runs \`$ref\` — no modules/$app/lib/mix/tasks/$task.ex"
done < <(grep -noE '\bmix (server|console)\.[a-z_]+' mise.toml flake.nix $scripts 2>/dev/null | sort -u)

# ---- (c) mise tasks ---------------------------------------------------------------------------
# Only tasks THIS repo's mise.toml defines: mise merges every mise.toml up the directory tree, so
# inside a worktree under the main checkout the parent's tasks would otherwise mask a miss.
known="$(mise tasks ls --json 2>/dev/null | jq -r --arg src "$root/mise.toml" '.[] | select(.source == $src) | .name' | sort -u)"
[ -n "$known" ] || miss "(c) \`mise tasks ls\` lists no task from $root/mise.toml — is mise on PATH and mise.toml parseable?"
n_mise=0
while IFS=: read -r file line ref; do
  [ -n "$ref" ] || continue
  n_mise=$((n_mise + 1))
  task="${ref#mise run }"
  task="${task%:}"            # a sentence-final "server:claude:" is the task, not a namespace
  case "$task" in
    *\*) grep -q "^${task%\*}" <<<"$known" || miss "(c) $file:$line names \`$ref\` — no task matches that prefix in \`mise tasks ls\`" ;;
    *) grep -qxF "$task" <<<"$known" || miss "(c) $file:$line names \`$ref\` — not a task \`mise tasks ls\` knows" ;;
  esac
done < <(grep -noE 'mise run [A-Za-z0-9:_*-]+' mise.toml flake.nix $scripts $(guides) 2>/dev/null | sort -u)

# ---- (d) pi config files the adapters read ----------------------------------------------------
n_pi=0
while IFS=: read -r file line path; do
  [ -n "$path" ] || continue
  n_pi=$((n_pi + 1))
  rel="${path#*.pi/agent/}"
  grep -qF "home.file.\".pi/agent/$rel\"" flake.nix || grep -qF "\"\$HOME/.pi/agent/$rel\"" flake.nix ||
    miss "(d) $file:$line reads ~/.pi/agent/$rel — flake.nix writes no such file (home.file / seed)"
done < <(grep -noE '\.pi/agent/[A-Za-z0-9_./-]+\.json' $(adapter_sources | grep '\.ts$') 2>/dev/null | sort -u)

if [ "$fail" -ne 0 ]; then
  echo "check-names: FAILED — a name above points at nothing (rename left a dangling reference)"
  exit 1
fi
echo "check-names: ok — $n_mod module refs, $n_mix mix tasks, $n_mise mise-task refs, $n_pi pi config files all resolve"
