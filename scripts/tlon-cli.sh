#!/usr/bin/env bash
# server CLI — operate/script the LIVE channel from the shell: the human + Claude Code
# peer to the agents' MCP tools, and the identity handoff the launchers (server:claude,
# pi:*) use.
#
# Most subcommands run through `bin/server rpc` INTO the running service node — a token
# minted anywhere else dies with its node and 401s, and roster/presence is in-memory
# there, so a fresh `eval` node would see neither. The service must be up. EXCEPTIONS:
# `token`/`bearer` POST to the /mint HTTP endpoint at TLON_MCP_URL's origin, so they mint
# in the RIGHT world for any node (server:dev's 4041 or the service's 4040) — bin/server rpc
# would only reach the service node and split a server:dev-handed pane into the wrong world.
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
#   shell-thread <id>              a thread's last messages + its worker's pane, for the office's wide view
#   ticket-file <ws> <proj|-> <title> [body…]   file a ticket (the shell's office)
#   ticket-start <ticket> [agent-id]            start a ticket, handed to that coworker or the lead
#   ticket-route <ticket>                       send a ticket to the workspace's manager to staff
#   hire <ws> <name> <archetype> [model [effort [ask]]]  seat a new coworker on a workspace's bench
#   coworker-set <ws> <agent-id> <model> <effort> <ask>  retarget one (from its next session)
#   workspace-new <name> [repo-path]            a new workspace, with a repo when given
#   aside <ws> <agent-id> <question…>           ask a coworker one thing, outside any thread
#   fire <seat-id>                              take a coworker off a bench (the agent survives)
#   ticket-set <id> status|title|body <value…>  change a ticket; ticket-delete <id> removes one
#   workspace-delete <id>                       delete one; its threads move to the oldest left
#   hand-off <thread-id> <agent-name>           give a running thread to another coworker
#   dossier <id>                   render a thread's brief — over MCP at TLON_MCP_URL when set
#                                  (JSON, the world that spawned the pane), else via rpc
#   post <id> <text…>              post as the operator
#   close-thread <id>              close a thread (its ticket is done; a child reports up)
#   reopen <id>                    reopen a closed thread; a queued workline re-joins the merge queue if its approval stands
#   delete-thread <id>             operator hard delete (messages go too; facts survive unlinked)
#   forget-fact <id>               operator tombstone — out of recall, row kept
#   resolve-issue <id> [why…]      close a stack issue (BLOCKERS), recording the resolution
#   workline "<title>" <slug>      open a workline at stage intent (operator kickoff)
#   track <id>                     promote a plain thread into a workline at build (opt-in)
#   advance <id>                   advance a workline past its current stage (verifier green path)
#   flag <name> on|off             turn a feature flag on or off for everyone (Server.Flags)
#   quiet                          "quiet", or "busy" and what a restart would cut off (server:restart asks)
#   releasable <sha>               the release checks on a commit (gate, smoke, quiet) and the verdict
#   announce-restart <why…>        a notice on every thread with a live session: the server is restarting
#   worktree <id>                  the thread's own checkout, as the server resolves it (its project's repo)
#   record-verify <id> <slug> <exit> <cmd> <tail…>  record verify-stage CHECK evidence
#   approve <id>                   complete a workline's parked gate (awaiting: andrew)
#     approve <id> --skip-qa <why…>  …and land a review past an owed QA pass, recorded with why
set -euo pipefail

# the release the service runs (.release, the release pointer's build), from the main checkout
# wherever this copy is; a machine that never cut a release has only the main checkout's
root="$(cd "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)"
SERVER="$root/.release/server/_build/prod/rel/server/bin/server"
[ -x "$SERVER" ] || SERVER="$root/server/_build/prod/rel/server/bin/server"
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

# A coworker's policy knobs as the shell sends them: a model key (provider/model), an effort and
# ask|allow; `-` leaves a knob alone and `inherit` clears it back to the archetype default.
knobs() {
  case "$1" in -|inherit|*/*) ;; *) return 1 ;; esac
  case "$2" in -|low|medium|high|xhigh|max) ;; *) return 1 ;; esac
  case "$3" in -|ask|allow|inherit) ;; *) return 1 ;; esac
}
# A coworker knob as Server.Workspaces.retarget/3 takes it: `-` leaves it (nil), `inherit` puts it
# back to the archetype's, anything else sets it.
knob() {
  case "$1" in -) printf nil ;; inherit) printf :inherit ;; *) printf '"%s"' "$(esc "$1")" ;; esac
}

# Escape a string for embedding as an Elixir "..." literal: backslash first, then quote,
# then `#{` — gate output routinely contains interpolation syntax (compiler errors, test
# diffs), and an unescaped `#{` would EXECUTE inside the rpc eval on the service node.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/#{/\\#{/g'; }
int() { case "$1" in ('' | *[!0-9]*) return 1 ;; (*) return 0 ;; esac; }

# Mint a fresh token against TLON_MCP_URL's origin /mint (Server.MCP.Gateway) — the same
# per-connect mint adapters/pi's mcp.ts does: POST {"thread_id", "agent"} → {"token"}. The token
# is signed with THAT node's world secret, so it verifies at /mcp on the same node (server:dev's
# 4041 or the service's 4040); minting via `bin/server rpc` instead would only reach the service
# node and strand a server:dev-handed pane in the wrong world. No token is frozen — a fresh one per
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
    # One JSON blob for the office (the desktop rail; the TUI reads the same at GET /api/office):
    # Server.Office.status — every workspace's roster, benches, threads, tickets, notes, visits.
    exec "$SERVER" rpc 'Server.Office.status() |> JSON.encode!() |> IO.puts()'
    ;;

  shell-thread)
    # A thread up close, as JSON (Server.Office.thread_view; GET /api/office/threads/:id): its last
    # 60 messages, and what its worker's pane shows right now (null when nothing runs it).
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh shell-thread <thread-id>' >&2; exit 2; }
    exec "$SERVER" rpc "Server.Repo.get!(Server.Thread, $tid) |> Server.Office.thread_view() |> JSON.encode!() |> IO.puts()"
    ;;

  close-thread)
    # The operator closes a thread: its sessions end, a child reports up, its ticket is done.
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh close-thread <thread-id>' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Repo.get(Server.Thread, $tid) do nil -> IO.puts(\"no thread #$tid\"); System.halt(1); t -> {:ok, _} = Server.Channel.close_thread(t); IO.puts(\"closed thread #$tid — #{t.title}\") end"
    ;;

  reopen)
    # A closed thread opens again (Server.Workline.reopen/1): a workline closed while in the merge
    # queue goes back into it while its approval stands for its branch as it is now.
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh reopen <thread-id>' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Repo.get(Server.Thread, $tid) do nil -> IO.puts(\"no thread #$tid\"); System.halt(1); t -> case Server.Workline.reopen(t) do {:ok, r} -> IO.puts(\"reopened thread #$tid — #{r.title}#{if r.stage, do: \" (#{r.stage})\"}\"); other -> IO.puts(\"reopened thread #$tid, but: #{inspect(other)}\"); System.halt(1) end end"
    ;;

  ticket-file)
    # File a ticket from the shell's office: ticket-file <workspace-id> <project-id|-> <title> [body…]
    ws="${1:-}"; proj="${2:-}"; title="${3:-}"; shift 3 2>/dev/null || true
    { int "$ws" && [ -n "$title" ] && { [ "$proj" = "-" ] || int "$proj"; }; } ||
      { echo 'usage: tlon-cli.sh ticket-file <workspace-id> <project-id|-> <title> [body…]' >&2; exit 2; }
    [ "$proj" = "-" ] && proj=nil
    exec "$SERVER" rpc "case Server.Tickets.file(%{workspace_id: $ws, project_id: $proj, title: \"$(esc "$title")\", body: \"$(esc "$*")\"}) do {:ok, t} -> IO.puts(\"filed ticket ##{t.id} — #{t.title}\"); {:error, cs} -> IO.puts(\"refused: #{inspect(cs.errors)}\"); System.halt(1) end"
    ;;

  ticket-route)
    # Send a ticket to its workspace's manager to staff (Server.Tickets.route); no manager → the lead starts it.
    tk="${1:-}"
    int "$tk" || { echo 'usage: tlon-cli.sh ticket-route <ticket-id>' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Tickets.get($tk) do nil -> IO.puts(\"no ticket #$tk\"); System.halt(1); t -> case Server.Tickets.route(t) do {:ok, %{routed_to: m}} -> IO.puts(\"ticket #$tk sent to #{m}\"); {:ok, %{started: th}} -> IO.puts(\"no manager: ticket #$tk started as thread ##{th.id}\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\"); System.halt(1) end end"
    ;;

  ticket-start)
    # Start work on a ticket, handed to a coworker (agent id) or else the workspace's lead.
    tk="${1:-}"; agent="${2:-nil}"
    { int "$tk" && { [ "$agent" = nil ] || int "$agent"; }; } ||
      { echo 'usage: tlon-cli.sh ticket-start <ticket-id> [agent-id]' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Tickets.get($tk) do nil -> IO.puts(\"no ticket #$tk\"); System.halt(1); t -> case Server.Tickets.start_thread(t, $agent) do {:ok, th} -> IO.puts(\"started ticket #$tk as thread ##{th.id}\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\"); System.halt(1) end end"
    ;;

  hire)
    # Seat a new coworker on a workspace's bench, and its policy when given:
    # hire <workspace-id> <name> <archetype> [<provider/model>|- [<effort>|- [ask|allow|-]]]
    ws="${1:-}"; name="${2:-}"; arch="${3:-}"; model="${4:--}"; effort="${5:--}"; ask="${6:--}"
    { int "$ws" && [ -n "$name" ] && [ -n "$arch" ] && knobs "$model" "$effort" "$ask"; } ||
      { echo 'usage: tlon-cli.sh hire <workspace-id> <name> <archetype> [<provider/model>|- [low|medium|high|xhigh|max|- [ask|allow|-]]]' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Workspaces.seat($ws, %{name: \"$(esc "$name")\", archetype: \"$(esc "$arch")\"}) do {:ok, c} -> {:ok, _} = Server.Workspaces.retarget($ws, c.agent_id, %{model: $(knob "$model"), effort: $(knob "$effort"), ask: $(knob "$ask")}); IO.puts(\"hired #{c.name} (#{c.archetype}) on workspace #$ws\"); {:error, cs} -> IO.puts(\"refused: #{inspect(cs.errors)}\"); System.halt(1) end"
    ;;

  coworker-set)
    # Retarget a coworker in a workspace (from its next session): model, effort, ask/allow.
    # `inherit` puts a knob back to the archetype default; `-` leaves it as it is.
    ws="${1:-}"; agent="${2:-}"; model="${3:--}"; effort="${4:--}"; ask="${5:--}"
    { int "$ws" && int "$agent" && knobs "$model" "$effort" "$ask"; } ||
      { echo 'usage: tlon-cli.sh coworker-set <workspace-id> <agent-id> <provider/model>|inherit|- <effort>|- ask|allow|inherit|-' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Workspaces.retarget($ws, $agent, %{model: $(knob "$model"), effort: $(knob "$effort"), ask: $(knob "$ask")}) do {:ok, _} -> IO.puts(\"set coworker #$agent on workspace #$ws\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\"); System.halt(1) end"
    ;;

  aside)
    # A one-shot question to a coworker, outside any thread: its own harness, model and persona,
    # read-only tools, no saved session (Server.Harness.aside). The server builds the argv; it
    # runs HERE, in the workspace's first repo, so the service never blocks on a model call.
    ws="${1:-}"; agent="${2:-}"; shift 2 2>/dev/null || true; q="$*"
    { int "$ws" && int "$agent" && [ -n "$q" ]; } ||
      { echo 'usage: tlon-cli.sh aside <workspace-id> <agent-id> <question…>' >&2; exit 2; }
    spec=$("$SERVER" rpc "case Server.Office.aside_spec($ws, $agent, \"$(esc "$q")\") do {:ok, spec} -> spec |> JSON.encode!() |> IO.puts(); _ -> IO.puts(\"{}\") end" | tail -1)
    [ "$(jq -r '.argv | length' <<<"$spec")" -gt 0 ] 2>/dev/null ||
      { echo "no coworker #$agent on workspace #$ws" >&2; exit 1; }
    cwd=$(jq -r '.cwd // empty' <<<"$spec"); cwd="${cwd/#\~/$HOME}"; [ -d "$cwd" ] || cwd="$HOME"
    eval "set -- $(jq -r '.argv | map(@sh) | join(" ")' <<<"$spec")"
    cd "$cwd" && exec timeout 180 "$@" </dev/null
    ;;

  fire)
    # Take a coworker off a workspace's bench by its seat (row) id; the agent itself survives.
    seat="${1:-}"
    int "$seat" || { echo 'usage: tlon-cli.sh fire <seat-id>' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Workspaces.unseat($seat) do {:ok, _} -> IO.puts(\"unseated seat #$seat\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\"); System.halt(1) end"
    ;;

  ticket-set)
    # Change one field of a ticket: ticket-set <id> status <backlog|todo|doing|done> | title <text…> | body <text…>
    tk="${1:-}"; field="${2:-}"; shift 2 2>/dev/null || true; value="$*"
    { int "$tk" && case "$field" in status|title|body) true ;; *) false ;; esac; } ||
      { echo 'usage: tlon-cli.sh ticket-set <ticket-id> status|title|body <value…>' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Tickets.get($tk) do nil -> IO.puts(\"no ticket #$tk\"); System.halt(1); t -> case Server.Tickets.update(t, %{$field: \"$(esc "$value")\"}) do {:ok, _} -> IO.puts(\"ticket #$tk $field set\"); {:error, cs} -> IO.puts(\"refused: #{inspect(cs.errors)}\"); System.halt(1) end end"
    ;;

  ticket-delete)
    tk="${1:-}"
    int "$tk" || { echo 'usage: tlon-cli.sh ticket-delete <ticket-id>' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Tickets.get($tk) do nil -> IO.puts(\"no ticket #$tk\"); System.halt(1); t -> {:ok, _} = Server.Tickets.remove(t); IO.puts(\"deleted ticket #$tk\") end"
    ;;

  workspace-delete)
    # Its threads move to the oldest remaining workspace; the last workspace is refused.
    ws="${1:-}"
    int "$ws" || { echo 'usage: tlon-cli.sh workspace-delete <workspace-id>' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Workspaces.get($ws) do nil -> IO.puts(\"no workspace #$ws\"); System.halt(1); w -> case Server.Workspaces.remove(w) do {:ok, _} -> IO.puts(\"deleted workspace #{w.name}\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\"); System.halt(1) end end"
    ;;

  hand-off)
    # Hand a running thread to another coworker (Server.Staffing.hand_off), then staff it now
    # rather than at the next minute's pass.
    tid="${1:-}"; handle="${2:-}"
    { int "$tid" && [ -n "$handle" ]; } || { echo 'usage: tlon-cli.sh hand-off <thread-id> <agent-name>' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Staffing.hand_off($tid, \"$(esc "$handle")\") do {:ok, t} -> Task.start(fn -> Server.Staffing.pass(t.workspace_id) end); IO.puts(\"handed thread #$tid to $(esc "$handle")\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\"); System.halt(1) end"
    ;;

  workspace-new)
    # A new workspace, with a repo to work in when given: workspace-new <name> [repo-path]
    name="${1:-}"; repo="${2:-}"
    [ -n "$name" ] || { echo 'usage: tlon-cli.sh workspace-new <name> [repo-path]' >&2; exit 2; }
    if [ -n "$repo" ]; then repos="[\"$(esc "$repo")\"]"; else repos="[]"; fi
    exec "$SERVER" rpc "case Server.Workspaces.create(%{name: \"$(esc "$name")\", repos: $repos}) do {:ok, w} -> IO.puts(\"workspace ##{w.id} #{w.name}\"); {:error, cs} -> IO.puts(\"refused: #{inspect(cs.errors)}\"); System.halt(1) end"
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
    # With TLON_MCP_URL the brief comes from the node that spawned this pane (server:dev's :4041
    # or the service's :4040) — the get_dossier tool itself, over HTTP. Without it,
    # the same Board.brief |> Brief.scope via rpc into the service node, pretty-printed.
    if [ -n "${TLON_MCP_URL:-}" ]; then dossier_http "$tid"; exit $?; fi
    exec "$SERVER" rpc "%Server.Thread{id: $tid} |> Server.Board.brief() |> Server.MCP.Brief.scope() |> inspect(pretty: true, limit: :infinity) |> IO.puts()"
    ;;

  note)
    # Post as tlon — the server's own voice, as its stage briefs are — not as the operator: what a
    # script reports (a verify result) must not read as something the human said.
    tid="${1:-}"; shift || true
    body="$*"
    { int "$tid" && [ -n "$body" ]; } || { echo 'usage: tlon-cli note <thread-id> <message text…>' >&2; exit 2; }
    exec "$SERVER" rpc "{:ok, m} = Server.Channel.post(%{thread_id: $tid, author: \"tlon\", body: \"$(esc "$body")\"}); IO.puts(\"posted ##{m.id} to thread #$tid as tlon\")"
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

  announce-restart)
    why="$*"; [ -n "$why" ] || why="the operator ran server:restart"
    exec "$SERVER" rpc "Server.Rollout.announce_restart(\"$(esc "$why")\")"
    ;;

  flag)
    name="${1:-}"; state="${2:-}"
    { [[ "$name" =~ ^[a-z_]+$ ]] && [[ "$state" =~ ^(on|off)$ ]]; } || { echo 'usage: tlon-cli.sh flag <name> on|off' >&2; exit 2; }
    on=false; [ "$state" = on ] && on=true
    # Prints only: the expression runs inside the live node, where a halt would stop the service.
    exec "$SERVER" rpc "case Server.Flags.set(\"$name\", $on) do {:ok, f} -> IO.puts(\"#{f.name} is now $state\"); {:error, why} -> IO.puts(why) end"
    ;;

  quiet)
    # Prints only: the expression runs inside the live node, where a halt would stop the service.
    exec "$SERVER" rpc 'case Server.Rollout.busy() do [] -> IO.puts("quiet"); b -> IO.puts("busy"); Enum.each(b, &IO.puts/1) end'
    ;;

  releasable)
    sha="${1:-}"
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'usage: tlon-cli.sh releasable <full sha>' >&2; exit 2; }
    exec "$SERVER" rpc "Enum.each(Server.Release.Candidate.lines(\"$sha\"), &IO.puts/1)"
    ;;

  worktree)
    tid="${1:-}"
    int "$tid" || { echo 'usage: tlon-cli.sh worktree <thread-id>' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.worktree_for_thread($tid) do {:ok, path} -> IO.puts(path); other -> IO.puts(:stderr, inspect(other)); System.halt(1) end"
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
    tid="${1:-}"; shift || true
    int "$tid" || { echo 'usage: tlon-cli.sh approve <thread-id> [--skip-qa <reason…>]' >&2; exit 2; }
    opts="[]"
    if [ "${1:-}" = "--skip-qa" ]; then
      shift
      [ "$#" -gt 0 ] || { echo 'approve --skip-qa needs a reason' >&2; exit 2; }
      opts="[skip_qa: \"$(esc "$*")\"]"
    fi
    # Complete a workline's parked gate (awaiting: andrew) — the operator's approval verb.
    # approve RE-VERIFIES the owed artifact via git in the SERVICE node — like `advance`,
    # the service needs TLON_WORKLINE_ROOT pointed at the worktree.
    exec "$SERVER" rpc "case Server.Repo.get(Server.Thread, $tid) do nil -> IO.puts(\"no thread #$tid\"); t -> case Server.Workline.approve(t, $opts) do {:ok, a} -> IO.puts(\"approved — thread #$tid now at #{a.stage}\"); {:error, why} -> IO.puts(\"refused: #{inspect(why)}\") end end"
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
    echo "usage: tlon-cli.sh {spawn|token|roster|announce-restart|dossier|post|shell-thread|close-thread|reopen|ticket-file|ticket-route|ticket-start|hire|coworker-set|workspace-new|aside|fire|ticket-set|ticket-delete|workspace-delete|hand-off|flag|workline|track|advance|record-verify|approve|delete-thread|forget-fact|resolve-issue} [args]" >&2
    exit 2
    ;;
esac
