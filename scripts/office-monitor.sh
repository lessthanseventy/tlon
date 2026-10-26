#!/usr/bin/env bash
# Watch the live office for workflow trouble and print one line per new event, forever — a feed for
# a background watcher (Claude Code's Monitor), so a session learns of trouble without polling:
#
#   office-monitor.sh            # every 45 s; TLON_MONITOR_EVERY=<s> to change
#
# NEED   a new operator need (ask, rollout, alert…), keyed so each is said once
# HEALTH a new problem in /api/office's health
# JOB    an Oban job that failed (retryable or discarded) since the watch began
# TLON   a message the server itself posted about a failure since the watch began
# LOG    an error-priority line from the tlon unit's journal
# DOWN / UP  the service stopped or came back answering
#
# Reads the service over loopback and the live db with psql, so from a sandboxed shell it sees
# nothing: run it on the host.
set -uo pipefail

url="${TLON_URL:-http://127.0.0.1:4040}"
db="${TLON_DB:-tlon}"
every="${TLON_MONITOR_EVERY:-45}"
since=$(date -u +%FT%TZ)
declare -A seen
down=0

say() { [ -n "${seen[$1]:-}" ] && return; seen[$1]=1; echo "$2"; }

while :; do
  if office=$(curl -sf -m 10 "$url/api/office"); then
    [ $down = 1 ] && echo "UP     the service answers again"; down=0
    while IFS=$'\t' read -r key line; do
      [ -n "$key" ] && say "need:$key" "NEED   $line"
    done < <(curl -sf -m 10 "$url/api/office/needs" | jq -r '.[]? | [.key, "\(.level) \(.kind) #\(.thread_id // "-") \(.text | gsub("\\s+";" ") | .[0:200])"] | @tsv')
    while IFS= read -r p; do
      [ -n "$p" ] && say "health:$p" "HEALTH $p"
    done < <(jq -r '.health.problems[]? | if type=="string" then . else tostring end | .[0:200]' <<<"$office")
  elif [ $down = 0 ]; then
    down=1; echo "DOWN   $url/api/office does not answer"
  fi

  while IFS='|' read -r id rest; do
    [ -n "$id" ] && say "job:$id" "JOB    $rest"
  done < <(psql -d "$db" -At -c "select id, state||' '||queue||' '||worker||' attempt '||attempt||': '||left(regexp_replace(coalesce(errors[array_length(errors,1)]->>'error',''),'\s+',' ','g'),200) from oban_jobs where state in ('retryable','discarded') and attempted_at > '$since' order by id" 2>/dev/null)

  while IFS='|' read -r id rest; do
    [ -n "$id" ] && say "msg:$id" "TLON   $rest"
  done < <(psql -d "$db" -At -c "select id, '#'||thread_id||' '||left(regexp_replace(body,'\s+',' ','g'),200) from message where author='tlon' and created_at > '$since' and body ~* '(fail|refused|red on|stuck|crash|timed out|conflict)' order by id" 2>/dev/null)

  while IFS= read -r l; do
    [ -n "$l" ] && say "log:$l" "LOG    ${l:0:240}"
  done < <(journalctl --user -u tlon -p err --since "$since" -o cat --no-pager 2>/dev/null)

  sleep "$every"
done
