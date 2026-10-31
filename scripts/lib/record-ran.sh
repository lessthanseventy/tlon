# Sourced by the gates that name the commit they checked (check-main.sh, release-smoke.sh) to report
# the result to the service: `release:status` reads a run recorded there, and a gate run by hand has
# no schedule to record it. Best effort — a service that is down never fails the run that reported.
# A scheduled run (TLON_SCHEDULE_RUN, set by Server.Schedules) is recorded by its schedule from its
# `ran-on:` line; posting too would add a second, output-less row. Read at source time: check-main.sh
# unsets TLON_* before it reports.
scheduled="${TLON_SCHEDULE_RUN:-}"
record_ran() { # check sha exit
  [ -z "$scheduled" ] || { echo "not posted: the schedule records this $1 run"; return 0; }
  local url="${TLON_URL:-http://127.0.0.1:4040}" answer
  if answer="$(curl -sf -m 5 -X POST -H 'content-type: application/json' \
      -d "{\"check\":\"$1\",\"sha\":\"$2\",\"exit\":$3}" "$url/api/release/ran")" && [ -n "$answer" ]; then
    echo "recorded: $1 $2 exit $3 ($answer)"
  else
    echo "not recorded: $url/api/release/ran did not answer; release:status won't see this $1 run"
  fi
  return 0
}
