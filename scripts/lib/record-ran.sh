# Sourced by the gates that name the commit they checked (check-main.sh, release-smoke.sh) to report
# the result to the service: `release:status` reads a run recorded there, and a gate run by hand has
# no schedule to record it. Best effort — a service that is down never fails the run that reported.
# A scheduled run (TLON_SCHEDULE_RUN, set by Server.Schedules) is recorded by its schedule from its
# `ran-on:` line; posting too would add a second, output-less row. Both are read at source time: the
# gates unset TLON_* before they report, and a TLON_URL read after that would always be the live service.
scheduled="${TLON_SCHEDULE_RUN:-}"
ran_url="${TLON_URL:-http://127.0.0.1:4040}"
record_ran() { # check sha exit
  [ -z "$scheduled" ] || { echo "recorded by the schedule: $1 run"; return 0; }
  local answer
  if answer="$(curl -sf -m 5 -X POST -H 'content-type: application/json' \
      -d "{\"check\":\"$1\",\"sha\":\"$2\",\"exit\":$3}" "$ran_url/api/release/ran")" && [ -n "$answer" ]; then
    echo "recorded: $1 $2 exit $3 ($answer)"
  else
    echo "not recorded: $ran_url/api/release/ran did not answer; release:status won't see this $1 run"
  fi
  return 0
}
ran_passed() { # check sha → the id of the passed run the service holds for it; fails when there is none
  local answer id
  answer="$(curl -sf -m 5 "$ran_url/api/release/ran?check=$1&sha=$2")" || return 1
  id="$(printf '%s' "$answer" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')"
  [ -n "$id" ] && echo "$id"
}
