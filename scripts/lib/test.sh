# Shared by the *.test.sh self-tests, sourced: `bad` is the verdict (end with `exit "$bad"`),
# `expect <name> <got> <want>` prints ok/FAIL, `until_log <prefix>` waits for a line of "$log".
bad=0
expect() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; bad=1; fi; }
until_log() { local i=0; while ! grep -q "^$1" "$log" && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done; }
