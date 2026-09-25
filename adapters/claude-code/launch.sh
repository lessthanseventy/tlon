#!/usr/bin/env bash
# mise run server:claude [thread-id] — launch Claude Code as a citizen of a server thread.
# No thread-id: open a fresh thread. A numeric thread-id: join that thread (resume across
# a /clear).
#
# The tlon MCP server (Door 1), the brief hook (Door 2), and the capture reflex (a Stop
# hook that banks durable facts back to the server each turn) are scoped to THIS session via
# `--mcp-config`/`--settings`, not installed into ~/.claude, so a normal `claude` stays
# untouched.
#
# The token is never frozen: the MCP server's `headersHelper` mints a fresh token per
# connect/reconnect (POST /mint at TLON_MCP_URL's origin), so auth survives a server
# restart, a token-model change, or a secret regeneration.
set -euo pipefail

adapter="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$adapter/../../.." && pwd)"
cli="$repo/scripts/tlon-cli.sh"

# If the environment already carries a server identity (e.g. the console's Tlön pane exported it
# before exec'ing this launcher), keep it as-is — per-connect minting targets TLON_MCP_URL's
# origin, so the token is always minted in the same world that serves /mcp.
if [ -z "${TLON_MCP_URL:-}" ] || [ -z "${TLON_THREAD:-}" ] || [ -z "${TLON_AUTHOR:-}" ]; then
  # Optional leading numeric thread-id → join; otherwise open a fresh thread.
  join_id=""
  if [ -n "${1:-}" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    join_id="$1"
    shift
  fi

  # The CLI's stderr passes through: its own error (no release, service down, no such
  # thread) is the diagnosis, so nothing here guesses at one.
  if [ -n "$join_id" ]; then
    block="$("$cli" spawn --join "$join_id" claude-code || true)"
  else
    branch="$(git -C "$PWD" branch --show-current 2>/dev/null || true)"
    block="$("$cli" spawn "claude-code @ $(basename "$PWD")${branch:+ ($branch)}" claude-code || true)"
  fi

  # Degrade gracefully: spawn failed → launch a PLAIN claude, not as a citizen, so the
  # harness is never held hostage to the server being up.
  if [ -z "$block" ]; then
    echo "tlon: spawn failed${join_id:+ for thread #$join_id} (see above) — launching plain claude, not as a citizen. If the service is down: 'mise run server:restart'" >&2
    [ "${TLON_LAUNCH_DRYRUN:-}" = "1" ] && { echo "exec: claude $*"; exit 0; }
    exec claude "$@"
  fi
  eval "$block" # exports TLON_MCP_URL / TLON_THREAD / TLON_AUTHOR (no TLON_TOKEN — minted per connect)
fi

# The MCP server key is `tlon` on every harness (flake.nix's mcpServers.tlon for pi), so the
# tools read as mcp__tlon__post_message etc. Nothing reads the key back; it is a label.
mcp_json="{\"mcpServers\":{\"tlon\":{\"type\":\"http\",\"url\":\"$TLON_MCP_URL\",\"headersHelper\":\"$cli token\"}}}"

# A write-fenced role (the console's claude_code driver sets TLON_PERMISSIONS_DENY, e.g.
# "Write,Edit,NotebookEdit" for the reviewer) lands as a real permissions.deny in --settings —
# a structural fence, not a persona request.
perms_json=""
if [ -n "${TLON_PERMISSIONS_DENY:-}" ]; then
  deny_list=""
  IFS=',' read -ra _deny_tools <<<"$TLON_PERMISSIONS_DENY"
  for tool in "${_deny_tools[@]}"; do
    deny_list="$deny_list\"$tool\","
  done
  perms_json=",\"permissions\":{\"deny\":[${deny_list%,}]}"
fi

# The workline gate (gate-hook.sh) runs FIRST on Stop: exit 2 bounces the stop once when the
# stage's artifact is missing. Presence (thinking counts as working): UserPromptSubmit declares thinking, Stop clears it
# (parallel to the capture reflex, so a slow extraction never delays the idle), SessionEnd is
# the exit/crash safety net.
settings_json="{\"hooks\":{\"SessionStart\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$adapter/brief-hook.sh\"}]}],\"UserPromptSubmit\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$adapter/thinking-hook.sh\"}]}],\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$adapter/gate-hook.sh\"},{\"type\":\"command\",\"command\":\"$adapter/capture-hook.sh\"},{\"type\":\"command\",\"command\":\"$adapter/thinking-hook.sh idle\"}]}],\"SessionEnd\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$adapter/thinking-hook.sh idle\"}]}]}$perms_json}"

# The citizen protocol, as a system prompt. Without it Claude Code treats a teammate's message
# (injected into its input as "[tlon thread #N] <author>: ..." — Console.Mention's prefix) like the
# human talking and answers in its own window — which no one else can see, so the reply is lost and
# the peer is never woken. Spell out that a reply is a post_message tool call that @-mentions the sender.
sys_prompt="You are a citizen of tlon thread #$TLON_THREAD posting as \"$TLON_AUTHOR\", working alongside other agents. Messages from teammates arrive in your input prefixed \"[tlon thread #N] <author>:\" — these are from other agents, NOT the human operator, and your terminal output is invisible to them. To reply so the sender actually receives it and takes their turn, call the tlon post_message tool and @-mention the sender by handle (for example @pi-machine); answering only in your own window reaches no one."

# A coworker ROLE (archetype persona) rides in as a file via TLON_ROLE_PROMPT_FILE (console's
# claude_code harness driver sets it) and is APPENDED to the citizen protocol — a second
# --append-system-prompt flag would replace it, not add to it.
if [ -n "${TLON_ROLE_PROMPT_FILE:-}" ] && [ -f "$TLON_ROLE_PROMPT_FILE" ]; then
  sys_prompt="$sys_prompt

$(cat "$TLON_ROLE_PROMPT_FILE")"
fi

if [ "${TLON_LAUNCH_DRYRUN:-}" = "1" ]; then
  printf 'identity: TLON_THREAD=%s TLON_AUTHOR=%s\n' "$TLON_THREAD" "$TLON_AUTHOR"
  printf 'mcp-config: %s\n' "$mcp_json"
  printf 'settings:   %s\n' "$settings_json"
  printf 'system:     %s\n' "$sys_prompt"
  printf 'exec: claude --permission-mode auto --append-system-prompt <…> --mcp-config <…> --settings <…> %s\n' "$*"
  exit 0
fi

# Nobody is at the keyboard when the service spawns this window (one-brain B/3): pre-accept
# Claude Code's folder-trust dialog for the directory it starts in, or the pane sits on the
# prompt forever. The dirs Tlön spawns into are the operator's own repos and their worktrees.
if command -v jq >/dev/null 2>&1; then
  cj="$HOME/.claude.json"
  [ -s "$cj" ] || echo '{}' > "$cj"
  jq --arg d "$PWD" '.projects[$d] = ((.projects[$d] // {}) + {hasTrustDialogAccepted: true})' "$cj" > "$cj.tmp" && mv "$cj.tmp" "$cj"
fi

exec claude --permission-mode auto --append-system-prompt "$sys_prompt" --mcp-config "$mcp_json" --settings "$settings_json" "$@"