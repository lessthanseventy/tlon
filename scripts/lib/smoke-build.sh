# Sourced by release-smoke.sh. Two smokes (or a smoke and a gate) building at once starve Postgres of
# connections and fail at a migration's pool timeout, so the heavy step — mix release, the database's
# drop/create, the migration — runs under one machine-wide lock; a built smoke runs on beside others.

# smoke_build_lock <lockfile> <who>: blocks until no other build holds the lock (fd 5), saying whose
# build it waits for. The kernel frees the lock with the holder, so a killed build blocks no one.
smoke_build_lock() {
  exec 5>>"$1"
  if ! flock -n 5; then
    echo "smoke: waiting for $(head -n 1 "$1" 2>/dev/null | grep . || echo someone)'s build"
    flock 5
  fi
  printf '%s\n' "$2" >"$1"
}

# the build is done: let the next one in
smoke_build_unlock() { exec 5>&-; }

# smoke_pool_cause <log>: what a build's log tail says when Postgres ran out of connections, else nothing
smoke_pool_cause() {
  if tail -n 20 "$1" | grep -qE 'DBConnection\.ConnectionError|too_many_connections'; then
    echo "Postgres ran out of connections during the migration (another smoke or gate was building): wait for it, then re-run"
  fi
}
