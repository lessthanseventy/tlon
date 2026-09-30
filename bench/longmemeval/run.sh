#!/usr/bin/env bash
# LongMemEval via agent-memory-benchmark (AMB), pinned by commit, against the tlon_bench db.
# Extra arguments are AMB `run` flags; a later --memory overrides tlon (e.g. --memory bm25).
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
amb="${AMB_DIR:-$HOME/.cache/tlon-bench/amb}"
pin=03c1d0f
[ -d "$amb" ] || git clone -q https://github.com/vectorize-io/agent-memory-benchmark "$amb"
git -C "$amb" cat-file -e "$pin" 2>/dev/null || git -C "$amb" fetch -q origin
git -C "$amb" checkout -q "$pin"
(cd "$root/server" && TLON_DATABASE=tlon_bench mix ecto.create --quiet && TLON_DATABASE=tlon_bench mix ecto.migrate --quiet)
cd "$root"
exec uv run --no-project --python 3.12 \
  --with typer --with rich --with rank-bm25 --with tiktoken --with python-dotenv --with google-genai --with scipy --with httpx \
  python bench/longmemeval/run.py run --dataset longmemeval --split s --memory tlon --output-dir .logs/bench "$@"
