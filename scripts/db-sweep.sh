#!/usr/bin/env bash
# Drop the databases a killed or red run left behind, and say how many:
#
#   db-sweep.sh [prefix]
#
# No argument sweeps every kind the machine leaves: `tlon_eval_<digits>` (server.eval) and the slug-shaped
# `tlon_land_*`, `tlon_verify_*` (a landing's or verify's gate) and `tlon_test_*` (a worktree's suite).
# `tlon_test` (the main checkout's suite) and `tlon_test_main` (check-main's) are out of reach by name.
# An argument sweeps that one prefix, `<prefix><digits>` only; it is lowercase letters, digits and
# underscores, with at least `tlon_` and a trailing `_`, and an empty one is refused, not defaulted.
#
# A database goes only if nothing is connected to it: a running eval, gate or suite holds its
# connection, so pg_stat_activity is the liveness check. Each suite recreates its database on its next run.
set -uo pipefail

if [ $# -eq 0 ]; then
  pattern='^(tlon_eval_[0-9]+|tlon_(land|verify|test)_[a-z0-9_]+)$'
  label='tlon_{eval,land,verify,test}_'
else
  prefix="$1"
  if ! [[ "$prefix" =~ ^tlon_[a-z0-9_]+$ && "$prefix" == *_ ]]; then
    echo "db-sweep: refused prefix '$prefix' (want tlon_<letters/digits/underscores>_)" >&2
    exit 2
  fi
  pattern="^${prefix}[0-9]+\$"
  label="${prefix}"
fi

pg() { psql -h "${PGHOST:-/run/postgresql}" -d postgres -XAtq "$@"; }

# the name pattern is checked twice: in SQL to list, again here before a name reaches DROP
dropped=0
while read -r db; do
  [[ "$db" =~ $pattern ]] || continue
  [ "$db" = tlon_test_main ] && continue
  pg -c "DROP DATABASE IF EXISTS \"$db\"" >/dev/null && dropped=$((dropped + 1))
done < <(pg -c "select d.datname from pg_database d where d.datname ~ '$pattern' and d.datname <> 'tlon_test_main'
                and not exists (select 1 from pg_stat_activity a where a.datname = d.datname)")
echo "db-sweep: dropped $dropped ${label}* database(s)"
