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

# smoke_isolated <cmd...>: runs the build's steps without the lock fd, so a child they leave running
# (an epmd the migrating node starts) cannot keep the machine-wide lock after the smoke exits
smoke_isolated() { ( "$@" ) 5>&-; }

# smoke_port_taken <port>: whether something listens on it (ss where it is, else a connect)
smoke_port_taken() {
  if command -v ss >/dev/null 2>&1; then
    [ -n "$(ss -Hltn "sport = :$1")" ]
  else
    (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
  fi
}

# smoke_pick_port <base>: the base, or the first port above it that nothing listens on. epmd's 4369
# answers no HTTP, so a curl guard passes it and the node boots on it: it and the service's 4040 are never picked
smoke_pick_port() {
  local p="$1"
  while [ "$p" = 4369 ] || [ "$p" = 4040 ] || smoke_port_taken "$p"; do p=$((p + 1)); done
  echo "$p"
}
