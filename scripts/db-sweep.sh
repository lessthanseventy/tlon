#!/usr/bin/env bash
# Drop the databases a killed or red server.eval left behind, and say how many:
#
#   db-sweep.sh [prefix]        (default tlon_eval_; an empty argument is refused, not defaulted)
#
# A database goes if its name is exactly <prefix><digits> and nothing is connected to it: a running
# eval holds its connection, so pg_stat_activity is the liveness check. The prefix is lowercase
# letters, digits and underscores, with at least `tlon_` and a trailing `_`, so `tlon`, `tlon_dev`,
# `tlon_test` and `tlon_test_main` (no digits after an underscore-ended prefix) are out of reach.
set -uo pipefail

prefix="${1-tlon_eval_}"
if ! [[ "$prefix" =~ ^tlon_[a-z0-9_]+$ && "$prefix" == *_ ]]; then
  echo "db-sweep: refused prefix '$prefix' (want tlon_<letters/digits/underscores>_)" >&2
  exit 2
fi

pg() { psql -h "${PGHOST:-/run/postgresql}" -d postgres -XAtq "$@"; }

# the name pattern is checked twice: in SQL to list, again here before a name reaches DROP
pattern="^${prefix}[0-9]+\$"
dropped=0
while read -r db; do
  [[ "$db" =~ $pattern ]] || continue
  pg -c "DROP DATABASE IF EXISTS \"$db\"" >/dev/null && dropped=$((dropped + 1))
done < <(pg -c "select d.datname from pg_database d where d.datname ~ '$pattern'
                and not exists (select 1 from pg_stat_activity a where a.datname = d.datname)")
echo "db-sweep: dropped $dropped ${prefix}* database(s)"
