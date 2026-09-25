#!/usr/bin/env bash
# server CLI — operate/script the LIVE channel from the shell: the human + Claude Code
# peer to the agents' MCP tools, and the identity handoff the launchers (server:claude,
# pi:*) use.
#
# Most subcommands run through `bin/server rpc` INTO the running service node — a token
# minted anywhere else dies with its node and 401s, and roster/presence is in-memory
# there, so a fresh `eval` node would see neither. The service must be up. EXCEPTIONS:
# `token`/`bearer` POST to the /mint HTTP endpoint at TLON_MCP_URL's origin, so they mint
# in the RIGHT world for any node (console's 4041 or the service's 4040) — bin/server rpc
# would only reach the service node and split a console-handed pane into the wrong world.
# `dossier` follows the same rule: with TLON_MCP_URL set it calls the `get_dossier` MCP
# tool over HTTP at that URL (the brief hook's world), rpc only when unset.
#
# Subcommands:
#   spawn "<title>" <agent>        open a fresh thread, staff+mint, print the export block
#   spawn --join <id> <agent>      JOIN an existing thread instead of opening one
#   token                          headersHelper: mint a FRESH token for (TLON_THREAD,
#                                  TLON_AUTHOR) from the env → {"Authorization":"Bearer …"}
#   roster                         who's on the clock (warm ●/cold ○)
#   shell-status                   roster + open threads + counts as JSON, for the desktop shell
#   shell-dossier <id>             a thread's brief as JSON, for the shell's AGENTS pane
#   dossier <id>                   render a thread's brief — over MCP at TLON_MCP_URL when set
#                                  (JSON, the world that spawned the pane), else via rpc
#   post <id> <text…>              post as the operator
#   delete-thread <id>             operator hard delete (messages go too; facts survive unlinked)
#   forget-fact <id>               operator tombstone — out of recall, row kept
#   resolve-issue <id> [why…]      close a stack issue (BLOCKERS), recording the resolution
#   workline "<title>" <slug>      open a workline at stage intent (operator kickoff)
#   track <id>                     promote a plain thread into a workline at build (opt-in)
#   advance <id>                   advance a workline past its current stage (verifier green path)
#   record-verify <id> <slug> <exit> <cmd> <tail…>  record verify-stage CHECK evidence
#   approve <id>                   complete a workline's parked gate (awaiting: andrew)
set -euo pipefail

SERVER="$(dirname "$0")/../server/_build/prod/rel/server/bin/server"
# `bin/server rpc` boots a throwaway client node; with a scheduler per core busy-waiting it
# cost ~2 s CPU for a 0.3 s call (the shell's 30 s agents poll: 7% of a core). One scheduler,
# no spin: ~0.25 s CPU. Only these client nodes see it; the service node is started elsewhere.
export ERL_FLAGS="${ERL_FLAGS:-} +S 1:1 +SDcpu 1:1 +SDio 1 +A 1 +sbwt none +sbwtdcpu none +sbwtdio none"
# Every rpc subcommand shells into `bin/server rpc` and needs the release. `token`/`bearer`
# do NOT — they mint purely over HTTP (/mint at TLON_MCP_URL's origin), so they must work
# without a local release (that's the whole point of per-connect minting: any node, any
# world). Gating them on the release strands every MCP headersHelper when no release is built.
# `dossier` needs no release either when TLON_MCP_URL points it at a node over HTTP.
case "${1:-}" in
  token | bearer) ;;
  dossier) [ -n "${TLON_MCP_URL:-}" ] || [ -x "$SERVER" ] || { echo "no release at $SERVER and no TLON_MCP_URL — run 'mise run server:release' or launch via a server launcher" >&2; exit 1; } ;;
  *) [ -x "$SERVER" ] || { echo "no release at $SERVER — run 'mise run server:release' first" >&2; exit 1; } ;;
esac

# TLON_CLI_CURL swaps the HTTP client (a stub in tests — nothing here can reach a node from a
# sandbox); every HTTP call goes through it.
CURL="${TLON_CLI_CURL:-curl}"

# Escape a string for embedding as an Elixir "..." literal: backslash first, then quote,
# then `#{` — gate output routinely contains interpolation syntax (compiler errors, test
# diffs), and an unescaped `#{` would EXECUTE inside the rpc eval on the service node.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/#{/\\#{/g'; }
int() { case "$1" in ('' | *[!0-9]*) return 1 ;; (*) return 0 ;; esac; }

# Mint a fresh token against TLON_MCP_URL's origin /mint (Server.MCP.Gateway) — the same
# per-connect mint adapters/pi's mcp.ts does: POST {"thread_id", "agent"} → {"token"}. The token
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
  resp=$("$CURL" -fsS -X POST "$url" -H 'content-type: application/json' -d "$body" 2>/dev/null) ||
    { echo "mint: POST $url failed — is the server node up?" >&2; return 1; }
  token=$(printf '%s' "$resp" | jq -r '.token // empty')
  [ -n "$token" ] || { echo "mint: no token in response from $url" >&2; return 1; }
  printf '%s' "$token"
}

# One JSON-RPC POST to TLON_MCP_URL, mirroring adapters/pi's mcp.ts: bearer + `Accept:
# application/json, text/event-stream`, the `Mcp-Session-Id` the initialize reply handed back on
# every later call, and a StreamableHTTP reply that is either plain JSON or a one-shot SSE stream
# (unwrapped to its first `data:` line). Leaves the decoded JSON in MCP_REPLY (empty for a
# bodiless 202) rather than printing it — a `$(…)` subshell would lose the session id;
# non-2xx returns 1 with the status on stderr.
MCP_SESSION=""
MCP_REPLY=""
mcp_post() {
  local tok="$1" msg="$2" hdr body code ctype json
  local -a sess=()
  [ -n "$MCP_SESSION" ] && sess=(-H "mcp-session-id: $MCP_SESSION")
  hdr=$(mktemp) && body=$(mktemp) || return 1
  code=$("$CURL" -sS -o "$body" -D "$hdr" -w '%{http_code}' -X POST "$TLON_MCP_URL" \
    -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' \
    -H "authorization: Bearer $tok" "${sess[@]}" -d "$msg") ||
    { rm -f "$hdr" "$body"; echo "mcp: POST $TLON_MCP_URL failed — is the node up?" >&2; return 1; }
  case "$code" in
    2??) ;;
    *) rm -f "$hdr" "$body"; echo "mcp: $TLON_MCP_URL returned HTTP $code" >&2; return 1 ;;
  esac
  [ -n "$MCP_SESSION" ] || MCP_SESSION=$(sed -n 's/^[Mm][Cc][Pp]-[Ss]ession-[Ii][Dd]:[[:space:]]*//p' "$hdr" | tr -d '\r' | head -1)
  ctype=$(sed -n 's/^[Cc]ontent-[Tt]ype:[[:space:]]*//p' "$hdr" | tr -d '\r' | tail -1)
  case "$ctype" in
    *event-stream*) json=$(sed -n 's/^data:[[:space:]]*//p' "$body" | tr -d '\r' | head -1) ;;
    *) json=$(cat "$body") ;;
  esac
  rm -f "$hdr" "$body"
  MCP_REPLY="$json"
}

# The get_dossier tool over MCP: mint for (thread, TLON_AUTHOR), initialize → notifications/
# initialized → tools/call. Prints the brief as JSON (`jq .`). get_dossier takes no thread — the
# token IS the thread — so a foreign id mints against it; TLON_AUTHOR must be a known agent.
dossier_http() {
  local tid="$1" tok reply text
  tok=$(TLON_THREAD="$tid" mint_token) || return 1
  mcp_post "$tok" '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"tlon-cli","version":"0.1.0"}}}' || return 1
  printf '%s' "$MCP_REPLY" | jq -e '.result' >/dev/null 2>&1 ||
    { echo "mcp: initialize refused: $MCP_REPLY" >&2; return 1; }
  mcp_post "$tok" '{"jsonrpc":"2.0","method":"notifications/initialized"}' || return 1
  mcp_post "$tok" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_dossier","arguments":{}}}' || return 1
  reply="$MCP_REPLY"
  if [ "$(printf '%s' "$reply" | jq -r '.result.isError // false')" = "true" ]; then
    echo "mcp: get_dossier rejected: $(printf '%s' "$reply" | jq -r '[.result.content[]? | select(.type=="text") | .text] | join(" ")')" >&2
    return 1
  fi
  text=$(printf '%s' "$reply" | jq -r '[.result.content[]? | select(.type=="text") | .text] | first // empty')
  [ -n "$text" ] || { echo "mcp: get_dossier returned no result: $reply" >&2; return 1; }
  printf '%s' "$text" | jq .
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
      call="Server.MCP.Spawn.join($id, \"$(esc "$agent")\")"
    else
      title="${1:-}"; agent="${2:-}"
      { [ -n "$title" ] && [ -n "$agent" ]; } ||
        { echo 'usage: mise run server:spawn -- "<thread title>" <agent-name>' >&2; exit 2; }
      call="Server.MCP.Spawn.env(\"$(esc "$title")\", \"$(esc "$agent")\")"
    fi
    exec "$SERVER" rpc "{:ok, m} = $call; IO.puts(m.exports)"
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

  shell-status)
    # One JSON blob for the desktop shell's AGENTS pane (modules/desktop/shell): the roster
    # plus thread counts by state and how many are awaiting the operator. Polled every ~30s.
    exec "$SERVER" rpc '
      roster = Server.Staff.roster() |> Enum.map(fn r ->
        %{agent: r.agent, thread_id: r.thread_id, title: r.thread_title, warm: r.warm?}
      end)
      import Ecto.Query
      counts = Server.Repo.all(from t in Server.Thread, group_by: t.state, select: {t.state, count(t.id)}) |> Map.new()
      prompts = Server.Attention.open_prompts_by_thread()
      awaiting = Server.Repo.one(from t in Server.Thread, where: t.state == "open" and (not is_nil(t.awaiting) or t.id in ^Map.keys(prompts)), select: count(t.id))
      threads = Server.Repo.all(from t in Server.Thread, where: t.state == "open", order_by: [desc: t.id], select: %{id: t.id, title: t.title, stage: t.stage, awaiting: t.awaiting}) |> Enum.map(&Map.put(&1, :prompt, prompts[&1.id]))
      %{roster: roster, counts: counts, awaiting: awaiting, threads: threads} |> JSON.encode!() |> IO.puts()'
    ;;

  shell-dossier)
    # A thread's brief as JSON for the AGENTS pane's detail (the same scope get_dossier gives an agent)
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh shell-dossier <thread-id>' >&2; exit 2; }
    exec "$SERVER" rpc "%Server.Thread{id: $tid} |> Server.Board.brief() |> Server.MCP.Brief.scope() |> JSON.encode!() |> IO.puts()"
    ;;

  roster)
    # Who's on the clock (Staff.roster): every live session, warm ● / cold ○.
    exec "$SERVER" rpc '
      Server.Staff.roster()
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
    # With TLON_MCP_URL the brief comes from the node that spawned this pane (console's :4041
    # .dev world or the service's :4040) — the get_dossier tool itself, over HTTP. Without it,
    # the same Board.brief |> Brief.scope via rpc into the service node, pretty-printed.
    if [ -n "${TLON_MCP_URL:-}" ]; then dossier_http "$tid"; exit $?; fi
    exec "$SERVER" rpc "%Server.Thread{id: $tid} |> Server.Board.brief() |> Server.MCP.Brief.scope() |> inspect(pretty: true, limit: :infinity) |> IO.puts()"
    ;;

  post)
    tid="${1:-}"; shift || true
    body="$*"
    { int "$tid" && [ -n "$body" ]; } ||
      { echo 'usage: mise run server:post -- <thread-id> <message text…>' >&2; exit 2; }
    # Post as the operator (default andrew) — parity with the agents' post_message. Through
    # Server.Attention.respond: a body naming an option of an open prompt (`y`, `n`, `2`) answers
    # the coworker's dialog instead of queueing behind it.
    exec "$SERVER" rpc "op = Application.get_env(:server, :operator, \"andrew\"); {:ok, m} = Server.Attention.respond($tid, op, \"$(esc "$body")\"); IO.puts(\"posted ##{m.id} to thread #$tid as #{op}\")"
    ;;

  workline)
    title="${1:-}"; slug="${2:-}"
    { [ -n "$title" ] && [ -n "$slug" ]; } ||
      { echo 'usage: tlon-cli.sh workline "<title>" <slug>' >&2; exit 2; }
    # Open a workline at stage intent — the operator's kickoff. The stage machine takes it
    # from here (advance_stage / approve).
    exec "$SERVER" rpc "case Server.Workline.open(%{title: \"$(esc "$title")\", slug: \"$(esc "$slug")\"}) do {:ok, t} -> IO.puts(\"workline ##{t.id} #{t.slug} at #{t.stage} — folder work/#{t.slug}/\"); {:error, cs} -> IO.puts(\"refused: #{inspect(cs.errors)}\") end"
    ;;

  advance)
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh advance <thread-id>' >&2; exit 2; }
    # Advance a workline past its current stage (the git artifact checker runs in the SERVICE
    # node — set TLON_WORKLINE_ROOT there). The verifier script's green-path exit.
    exec "$SERVER" rpc "case Server.Repo.get(Server.Thread, $tid) do nil -> IO.puts(\"no thread #$tid\"); t -> case Server.Workline.advance(t) do {:ok, a} -> IO.puts(\"advanced — thread #$tid now at #{a.stage}\"); {:awaiting, a} -> IO.puts(\"gated at #{a.stage} — awaiting #{a.awaiting}\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\") end end"
    ;;

  record-verify)
    tid="${1:-}"; slug="${2:-}"; code="${3:-}"; cmd="${4:-}"; shift 4 || true; tail="$*"
    { int "$tid" && [ -n "$slug" ] && int "$code" && [ -n "$cmd" ]; } ||
      { echo 'usage: tlon-cli.sh record-verify <thread-id> <slug> <exit> <cmd> <tail…>' >&2; exit 2; }
    # The verifier script's evidence path: a measured check correlated workline:<slug>:verify —
    # exactly what the verify stage's owed :checks artifact looks for.
    exec "$SERVER" rpc "{:ok, e} = Server.Dossier.record_check(%{thread_id: $tid, cmd: \"$(esc "$cmd")\", exit: $code, tail: \"$(esc "$tail")\", correlation: \"workline:$(esc "$slug"):verify\"}); IO.puts(\"recorded ##{e.id} #{e.kind}\")"
    ;;

  track)
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh track <thread-id>' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Repo.get(Server.Thread, $tid) do nil -> IO.puts(\"no thread #$tid\"); t -> case Server.Workline.promote(t) do {:ok, w} -> IO.puts(\"tracked — thread #$tid is workline #{w.slug} at #{w.stage}\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\") end end"
    ;;

  approve)
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh approve <thread-id>' >&2; exit 2; }
    # Complete a workline's parked gate (awaiting: andrew) — the operator's approval verb.
    # approve RE-VERIFIES the owed artifact via git in the SERVICE node — like `advance`,
    # the service needs TLON_WORKLINE_ROOT pointed at the worktree.
    exec "$SERVER" rpc "case Server.Repo.get(Server.Thread, $tid) do nil -> IO.puts(\"no thread #$tid\"); t -> case Server.Workline.approve(t) do {:ok, a} -> IO.puts(\"approved — thread #$tid now at #{a.stage}\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\") end end"
    ;;

  delete-thread)
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh delete-thread <thread-id>' >&2; exit 2; }
    # The operator's hard delete: thread + its messages/todos/questions/sessions; facts survive
    # unlinked. The root machine thread is refused by Channel.delete_thread itself.
    exec "$SERVER" rpc "case Server.Repo.get(Server.Thread, $tid) do nil -> IO.puts(\"no thread #$tid\"); t -> case Server.Channel.delete_thread(t) do {:ok, _} -> IO.puts(\"deleted thread #$tid — #{t.title}\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\") end end"
    ;;

  forget-fact)
    fid="${1:-}"
    int "$fid" || { echo 'usage: tlon-cli.sh forget-fact <fact-id>' >&2; exit 2; }
    # The operator's tombstone: out of every recall surface, row + provenance kept.
    exec "$SERVER" rpc "case Server.Repo.get(Server.Fact, $fid) do nil -> IO.puts(\"no fact #$fid\"); f -> {:ok, _} = Server.Dossier.forget_fact(f); IO.puts(\"forgot fact #$fid — #{f.text}\") end"
    ;;

  resolve-issue)
    iid="${1:-}"; shift || true
    int "$iid" || { echo 'usage: tlon-cli.sh resolve-issue <issue-id> [resolution…]' >&2; exit 2; }
    if [ "$#" -gt 0 ]; then res="\"$(esc "$*")\""; else res=nil; fi
    exec "$SERVER" rpc "case Server.Repo.get(Server.Issue, $iid) do nil -> IO.puts(\"no issue #$iid\"); i -> {:ok, _} = Server.Dossier.resolve_issue(i, $res); IO.puts(\"resolved issue #$iid — #{i.summary}\") end"
    ;;

  *)
    echo "usage: tlon-cli.sh {spawn|token|roster|dossier|post|workline|track|advance|record-verify|approve|delete-thread|forget-fact|resolve-issue} [args]" >&2
    exit 2
    ;;
esac
