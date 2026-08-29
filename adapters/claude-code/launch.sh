#!/usr/bin/env bash
# mise run funes:claude [thread-id] — launch Claude Code as a funes citizen.
# No thread-id: open a fresh thread. A numeric thread-id: join that thread (resume across
# a /clear).
#
# The funes MCP server (Door 1), the brief hook (Door 2), and the capture reflex (a Stop
# hook that banks durable facts back to funes each turn) are scoped to THIS session via
# `--mcp-config`/`--settings`, not installed into ~/.claude, so a normal `claude` stays
# untouched.
#
# The token is never frozen: the MCP server's `headersHelper` mints a fresh token per
# connect/reconnect (POST /mint at TLON_MCP_URL's origin), so auth survives a funes
# restart, a token-model change, or a secret regeneration.
set -euo pipefail

adapter="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$adapter/../../.." && pwd)"
cli="$repo/scripts/funes-cli.sh"

# If the environment already carries a funes identity (e.g. aleph's Tlön pane exported it
# before exec'ing this launcher), keep it as-is — per-connect minting targets TLON_MCP_URL's
# origin, so the token is always minted in the same world that serves /mcp.
if [ -z "${TLON_MCP_URL:-}" ] || [ -z "${TLON_THREAD:-}" ] || [ -z "${TLON_AUTHOR:-}" ]; then
  # Optional leading numeric thread-id → join; otherwise open a fresh thread.
  join_id=""
  if [ -n "${1:-}" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    join_id="$1"
    shift
  fi

  if [ -n "$join_id" ]; then
    block="$("$cli" spawn --join "$join_id" claude-code 2>/dev/null || true)"
  else
    branch="$(git -C "$PWD" branch --show-current 2>/dev/null || true)"
    block="$("$cli" spawn "claude-code @ $(basename "$PWD")${branch:+ ($branch)}" claude-code 2>/dev/null || true)"
  fi

  # Degrade gracefully: no live channel (or no such thread) → launch a PLAIN claude, so
  # the harness is never held hostage to funes being up.
  if [ -z "$block" ]; then
    echo "funes: channel not up${join_id:+ or no thread #$join_id} — launching plain claude (start it with 'mise run funes:restart')" >&2
    [ "${TLON_LAUNCH_DRYRUN:-}" = "1" ] && { echo "exec: claude $*"; exit 0; }
    exec claude "$@"
  fi
  eval "$block" # exports TLON_MCP_URL / TLON_THREAD / TLON_AUTHOR (no TLON_TOKEN — minted per connect)
fi

mcp_json="{\"mcpServers\":{\"funes\":{\"type\":\"http\",\"url\":\"$TLON_MCP_URL\",\"headersHelper\":\"$cli token\"}}}"

# A write-fenced role (aleph's claude_code driver sets TLON_PERMISSIONS_DENY, e.g.
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

# Presence (thinking counts as working): UserPromptSubmit declares thinking, Stop clears it
# (parallel to the capture reflex, so a slow extraction never delays the idle), SessionEnd is
# the exit/crash safety net. PostToolUse carries the heartbeat (funes thread #3, cadence-gated
# check-ins during a long turn — heartbeat-hook.sh) AND auto-track (reshape slice B: a landed
# `git commit` promotes the thread into the stage machine — track-hook.sh).
settings_json="{\"hooks\":{\"SessionStart\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$adapter/brief-hook.sh\"}]}],\"UserPromptSubmit\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$adapter/thinking-hook.sh\"}]}],\"PostToolUse\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$adapter/heartbeat-hook.sh\"},{\"type\":\"command\",\"command\":\"$adapter/track-hook.sh\"}]}],\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$adapter/capture-hook.sh\"},{\"type\":\"command\",\"command\":\"$adapter/thinking-hook.sh idle\"}]}],\"SessionEnd\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$adapter/thinking-hook.sh idle\"}]}]}$perms_json}"

# The funes-citizen protocol, as a system prompt. Without it Claude Code treats a teammate's message
# (injected into its input as "[funes thread #N] <author>: ...") like the human talking and answers in
# its own window — which no one else can see, so the reply is lost and the peer is never woken. Spell
# out that a reply is a post_message tool call that @-mentions the sender.
sys_prompt="You are a funes citizen posting as \"$TLON_AUTHOR\" on thread #$TLON_THREAD, working alongside other agents. Messages from teammates arrive in your input prefixed \"[funes thread #N] <author>:\" — these are from other agents, NOT the human operator, and your terminal output is invisible to them. To reply so the sender actually receives it and takes their turn, call the funes post_message tool and @-mention the sender by handle (for example @pi-machine); answering only in your own window reaches no one."

# A coworker ROLE (archetype persona) rides in as a file via TLON_ROLE_PROMPT_FILE (aleph's
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

exec claude --permission-mode auto --append-system-prompt "$sys_prompt" --mcp-config "$mcp_json" --settings "$settings_json" "$@"