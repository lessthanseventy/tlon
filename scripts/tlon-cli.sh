#!/usr/bin/env bash
# server CLI — operate/script the LIVE channel from the shell: the human + Claude Code
# peer to the agents' MCP tools, and the identity handoff the launchers (server:claude,
# pi:*) use.
#
# Most subcommands run through `bin/server rpc` INTO the running service node — a token
# minted anywhere else dies with its node and 401s, and roster/presence is in-memory
# there, so a fresh `eval` node would see neither. The service must be up. EXCEPTION:
# `token` POSTs to the /mint HTTP endpoint at TLON_MCP_URL's origin, so it mints in the
# RIGHT world for any node (console's 4041 or the service's 4040) — bin/server rpc would
# only reach the service node and split an console-handed pane into the wrong world.
#
# Subcommands:
#   spawn "<title>" <agent>        open a fresh thread, staff+mint, print the export block
#   spawn --join <id> <agent>      JOIN an existing thread instead of opening one
#   token                          headersHelper: mint a FRESH token for (TLON_THREAD,
#                                  TLON_AUTHOR) from the env → {"Authorization":"Bearer …"}
#   roster                         who's on the clock (warm ●/cold ○)
#   dossier <id>                   render a thread's brief
#   post <id> <text…>              post as the operator
#   delete-thread <id>             operator hard delete (messages go too; facts survive unlinked)
#   forget-fact <id>               operator tombstone — out of recall, row kept
#   workline "<title>" <slug>      open a workline at stage intent (operator kickoff)
#   advance <id>                   advance a workline past its current stage (verifier green path)
#   record-verify <id> <slug> <exit> <cmd> <tail…>  record verify-stage CHECK evidence
#   approve <id>                   complete a workline's parked gate (awaiting: andrew)
set -euo pipefail

FUNES="$(dirname "$0")/../modules/server/_build/prod/rel/server/bin/server"
# Every rpc subcommand shells into `bin/server rpc` and needs the release. `token`/`bearer`
# do NOT — they mint purely over HTTP (/mint at TLON_MCP_URL's origin), so they must work
# without a local release (that's the whole point of per-connect minting: any node, any
# world). Gating them on the release strands every MCP headersHelper when no release is built.
case "${1:-}" in
  token | bearer) ;;
  *) [ -x "$FUNES" ] || { echo "no release at $FUNES — run 'mise run server:release' first" >&2; exit 1; } ;;
esac

# Escape a string for embedding as an Elixir "..." literal: backslash first, then quote,
# then `#{` — gate output routinely contains interpolation syntax (compiler errors, test
# diffs), and an unescaped `#{` would EXECUTE inside the rpc eval on the service node.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/#{/\\#{/g'; }
int() { case "$1" in ('' | *[!0-9]*) return 1 ;; (*) return 0 ;; esac; }

# Mint a fresh token against TLON_MCP_URL's origin /mint (Funes.MCP.Gateway) — the same
# per-connect mint manos/pi's mcp.ts does: POST {"thread_id", "agent"} → {"token"}. The token
# is signed with THAT node's world secret, so it verifies at /mcp on the same node (console's
# 4041 or the service's 4040); minting via `bin/server rpc` instead would only reach the service
# node and strand an console-handed pane in the wrong world. No token is frozen — a fresh one per
# connect survives restart/model/secret changes. Any failure returns non-zero so the caller
# (CC's `token` headersHelper / pi's `bearer` !command) marks the server bad rather than 401ing.
mint_token() {
  : "${TLON_MCP_URL:?mint: TLON_MCP_URL not set (launch via a server launcher)}"
  : "${TLON_THREAD:?mint: TLON_THREAD not set}"
  : "${TLON_AUTHOR:?mint: TLON_AUTHOR not set}"
  int "$TLON_THREAD" || { echo "mint: TLON_THREAD must be numeric" >&2; return 1; }
  local url="${TLON_MCP_URL%/*}/mint" body resp token
  body=$(printf '{"thread_id": %s, "agent": "%s"}' "$TLON_THREAD" "$(esc "$TLON_AUTHOR")")
  resp=$(curl -fsS -X POST "$url" -H 'content-type: application/json' -d "$body" 2>/dev/null) ||
    { echo "mint: POST $url failed — is the server node up?" >&2; return 1; }
  token=$(printf '%s' "$resp" | jq -r '.token // empty')
  [ -n "$token" ] || { echo "mint: no token in response from $url" >&2; return 1; }
  printf '%s' "$token"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  spawn)
    # Open or join a thread, staff the agent (register if new), and print the identity-only
    # export TLON_* block (TLON_MCP_URL / TLON_THREAD / TLON_AUTHOR — NO TLON_TOKEN).
    # The adapter mints a fresh token per connect against the URL's /mint (`token`/`bearer`
    # below), so no frozen token strands a pane across a restart or secret regeneration.
    if [ "${1:-}" = "--join" ]; then
      shift; id="${1:-}"; agent="${2:-}"
      { int "$id" && [ -n "$agent" ]; } ||
        { echo 'usage: tlon-cli.sh spawn --join <thread-id> <agent-name>' >&2; exit 2; }
      call="Funes.MCP.Spawn.join($id, \"$(esc "$agent")\")"
    else
      title="${1:-}"; agent="${2:-}"
      { [ -n "$title" ] && [ -n "$agent" ]; } ||
        { echo 'usage: mise run server:spawn -- "<thread title>" <agent-name>' >&2; exit 2; }
      call="Funes.MCP.Spawn.env(\"$(esc "$title")\", \"$(esc "$agent")\")"
    fi
    exec "$FUNES" rpc "{:ok, m} = $call; IO.puts(m.exports)"
    ;;

  token)
    # Claude Code's headersHelper — runs on every MCP connect/reconnect. Output is the
    # exact headers JSON CC merges into the connection. Any failure exits non-zero so CC
    # reports the server bad.
    tok=$(mint_token) || exit 1
    printf '{"Authorization":"Bearer %s"}
' "$tok"
    ;;
  bearer)
    # pi-mcp-adapter's `!command` header value (runs at connect): same per-connect /mint
    # as `token`, but outputs the BARE `Bearer <token>` value, not the headersHelper JSON.
    tok=$(mint_token) || exit 1
    printf 'Bearer %s
' "$tok"
    ;;

  roster)
    # Who's on the clock (Staff.roster): every live session, warm ● / cold ○.
    exec "$FUNES" rpc '
      Funes.Staff.roster()
      |> Enum.map_join("\n", fn r ->
        mark = if r.warm?, do: "●", else: "○"
        pane = if r.pane_ref, do: " [" <> r.pane_ref <> "]", else: ""
        "#{mark} #{r.agent} — ##{r.thread_id} #{r.thread_title}#{pane}"
      end)
      |> then(fn "" -> "(no one on the clock)"; s -> s end)
      |> IO.puts()'
    ;;

  dossier)
    tid="${1:-${TLON_THREAD:-}}"
    int "$tid" || { echo 'usage: mise run server:dossier -- <thread-id> (or set TLON_THREAD)' >&2; exit 2; }
    # Same Board.in_scope |> Brief.scope the get_dossier MCP tool renders, pretty-printed.
    exec "$FUNES" rpc "%Funes.Thread{id: $tid} |> Funes.Board.in_scope() |> Funes.MCP.Brief.scope() |> inspect(pretty: true, limit: :infinity) |> IO.puts()"
    ;;

  post)
    tid="${1:-}"; shift || true
    body="$*"
    { int "$tid" && [ -n "$body" ]; } ||
      { echo 'usage: mise run server:post -- <thread-id> <message text…>' >&2; exit 2; }
    # Post as the operator (default andrew) — parity with the agents' post_message.
    exec "$FUNES" rpc "op = Application.get_env(:server, :operator, \"andrew\"); {:ok, m} = Funes.Channel.post(%{thread_id: $tid, author: op, body: \"$(esc "$body")\"}); IO.puts(\"posted ##{m.id} to thread #$tid as #{op}\")"
    ;;

  workline)
    title="${1:-}"; slug="${2:-}"
    { [ -n "$title" ] && [ -n "$slug" ]; } ||
      { echo 'usage: tlon-cli.sh workline "<title>" <slug>' >&2; exit 2; }
    # Open a workline at stage intent — the operator's kickoff. The stage machine takes it
    # from here (advance_stage / approve).
    exec "$FUNES" rpc "case Funes.Workline.open(%{title: \"$(esc "$title")\", slug: \"$(esc "$slug")\"}) do {:ok, t} -> IO.puts(\"workline ##{t.id} #{t.slug} at #{t.stage} — folder work/#{t.slug}/\"); {:error, cs} -> IO.puts(\"refused: #{inspect(cs.errors)}\") end"
    ;;

  advance)
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh advance <thread-id>' >&2; exit 2; }
    # Advance a workline past its current stage (the git artifact checker runs in the SERVICE
    # node — set TLON_WORKLINE_ROOT there). The verifier script's green-path exit.
    exec "$FUNES" rpc "case Funes.Repo.get(Funes.Thread, $tid) do nil -> IO.puts(\"no thread #$tid\"); t -> case Funes.Workline.advance(t) do {:ok, a} -> IO.puts(\"advanced — thread #$tid now at #{a.stage}\"); {:awaiting, a} -> IO.puts(\"gated at #{a.stage} — awaiting #{a.awaiting}\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\") end end"
    ;;

  record-verify)
    tid="${1:-}"; slug="${2:-}"; code="${3:-}"; cmd="${4:-}"; shift 4 || true; tail="$*"
    { int "$tid" && [ -n "$slug" ] && int "$code" && [ -n "$cmd" ]; } ||
      { echo 'usage: tlon-cli.sh record-verify <thread-id> <slug> <exit> <cmd> <tail…>' >&2; exit 2; }
    # The verifier script's evidence path: a measured check correlated workline:<slug>:verify —
    # exactly what the verify stage's owed :checks artifact looks for.
    exec "$FUNES" rpc "{:ok, e} = Funes.Dossier.record_check(%{thread_id: $tid, cmd: \"$(esc "$cmd")\", exit: $code, tail: \"$(esc "$tail")\", correlation: \"workline:$(esc "$slug"):verify\"}); IO.puts(\"recorded ##{e.id} #{e.kind}\")"
    ;;

  approve)
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh approve <thread-id>' >&2; exit 2; }
    # Complete a workline's parked gate (awaiting: andrew) — the operator's approval verb.
    # approve RE-VERIFIES the owed artifact via git in the SERVICE node — like `advance`,
    # the service needs TLON_WORKLINE_ROOT pointed at the worktree.
    exec "$FUNES" rpc "case Funes.Repo.get(Funes.Thread, $tid) do nil -> IO.puts(\"no thread #$tid\"); t -> case Funes.Workline.approve(t) do {:ok, a} -> IO.puts(\"approved — thread #$tid now at #{a.stage}\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\") end end"
    ;;

  delete-thread)
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh delete-thread <thread-id>' >&2; exit 2; }
    # The operator's hard delete: thread + its messages/todos/questions/sessions; facts survive
    # unlinked. The root machine thread is refused by Channel.delete_thread itself.
    exec "$FUNES" rpc "case Funes.Repo.get(Funes.Thread, $tid) do nil -> IO.puts(\"no thread #$tid\"); t -> case Funes.Channel.delete_thread(t) do {:ok, _} -> IO.puts(\"deleted thread #$tid — #{t.title}\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\") end end"
    ;;

  forget-fact)
    fid="${1:-}"
    int "$fid" || { echo 'usage: tlon-cli.sh forget-fact <fact-id>' >&2; exit 2; }
    # The operator's tombstone: out of every recall surface, row + provenance kept.
    exec "$FUNES" rpc "case Funes.Repo.get(Funes.Fact, $fid) do nil -> IO.puts(\"no fact #$fid\"); f -> {:ok, _} = Funes.Dossier.forget_fact(f); IO.puts(\"forgot fact #$fid — #{f.text}\") end"
    ;;

  *)
    echo "usage: tlon-cli.sh {spawn|token|roster|dossier|post|workline|advance|record-verify|approve|delete-thread|forget-fact} [args]" >&2
    exit 2
    ;;
esac
