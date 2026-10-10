#!/usr/bin/env bash
# gateway.sh PROVIDER CMD… — run a Claude Code invocation against PROVIDER's endpoint: the one place
# that knows how a model provider becomes Claude Code's environment. launch.sh (a coworker's window),
# the aside, the role bench and the server's one-shots (Server.ModelCli) all exec through it.
#
# An ollama model is reached through Claude Code's gateway setting (ollama.com and the local daemon
# speak the Anthropic API), so every request the invocation makes — the model's, its subagents', the
# background ones — goes to ollama and none draws on the Claude plan. The model aliases point at
# ollama models too, or a subagent asking for "haiku" would name a model ollama doesn't serve.
# `anthropic` (or nothing) leaves the environment alone: the operator's own Claude login.
set -euo pipefail

provider="${1:-anthropic}"
shift

model=""
args=("$@")
for i in "${!args[@]}"; do
  [ "${args[$i]}" = "--model" ] && model="${args[$((i + 1))]:-}"
done

case "$provider" in
  anthropic | "") ;;
  ollama-cloud)
    key="${OLLAMA_API_KEY:-$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agenix/ollama-api-key" 2>/dev/null || true)}"
    [ -n "$key" ] || { echo "gateway: no OLLAMA_API_KEY (env or agenix) for an ollama-cloud model" >&2; exit 1; }
    export ANTHROPIC_BASE_URL=https://ollama.com ANTHROPIC_AUTH_TOKEN="$key" ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4.1-flash
    ;;
  ollama)
    export ANTHROPIC_BASE_URL=http://localhost:11434 ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_DEFAULT_HAIKU_MODEL="$model"
    ;;
  *)
    echo "gateway: unknown provider $provider" >&2
    exit 2
    ;;
esac

if [ -n "${ANTHROPIC_BASE_URL:-}" ]; then
  unset ANTHROPIC_API_KEY
  export ANTHROPIC_DEFAULT_SONNET_MODEL="$model" ANTHROPIC_DEFAULT_OPUS_MODEL="$model"
fi

exec "$@"
