#!/usr/bin/env bash
# Self-test of .miserc.toml: a tree under another checkout (<checkout>/.worktrees/<branch>) loads
# only its own tasks, and the checkout above still loads its own.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bad=0
unset MISE_CEILING_PATHS
export MISE_TRUSTED_CONFIG_PATHS="$tmp"

# check <what holds> <what it means when it does not> <command…>
check() {
	local ok="$1" fail="$2"
	shift 2
	if "$@"; then
		echo "ok   $ok"
	else
		echo "FAIL $fail"
		bad=1
	fi
}
# shellcheck disable=SC2329 # the three below run through check
runs() { (cd "$1" && mise run "$2" >/dev/null 2>&1); }
# shellcheck disable=SC2329
not_found() { ! runs "$@"; }
# shellcheck disable=SC2329
answers() { [ "$(cd "$1" && mise run "$2" 2>/dev/null)" = "$3" ]; }

above="$tmp/checkout"
tree="$above/.worktrees/branch"
mkdir -p "$tree/sub"
printf '[tasks.removed]\nrun = "echo above"\n[tasks.kept]\nrun = "echo above"\n' >"$above/mise.toml"
printf '[tasks.kept]\nrun = "echo tree"\n' >"$tree/mise.toml"
cp "$here/../.miserc.toml" "$above/.miserc.toml"

# Without the file the leak is there: the cases below prove something only if this one holds.
check "without .miserc.toml the tree runs the checkout's task" \
	"setup: the tree did not see the checkout's task, so the test shows nothing" runs "$tree" removed

cp "$here/../.miserc.toml" "$tree/.miserc.toml"
check "a task only the checkout above has is not found in the tree" \
	"the tree still runs a task only the checkout above has" not_found "$tree" removed
check "  nor from a subdirectory of the tree" \
	"a subdirectory of the tree still runs it" not_found "$tree/sub" removed
check "the tree runs its own tasks" \
	"the tree's own task did not answer 'tree'" answers "$tree" kept tree
check "the checkout above still runs its own" \
	"the checkout's own task did not answer 'above'" answers "$above" removed above

exit "$bad"
