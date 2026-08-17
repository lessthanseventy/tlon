#!/usr/bin/env bash
# ollama-usage — read the ollama.com plan/rate-limit dashboard.
#
# The one insight door the OLLAMA_API_KEY opens besides /v1 chat: GET /api/usage
# returns two windows that bound the $20 plan, plus paid/per-token activity:
#   session — a SHORT rolling rate-limit window. This is the one that *feels* like
#             "blowing through budget fast": a reasoning model (glm-5.2) emits enough
#             thinking tokens per request to trip it mid-session and get throttled.
#   weekly  — the rolling plan cap (the actual "run out of plan" ceiling).
# `usage` is a 0–1 fraction of the window's cap; `activity.cost` is per-token usage
# (kimi-k3 and other extra-billed models) over the last 4 weeks — should stay 0.00
# on a plan-only diet.
#
# Per-model request_count is printed so you can see WHICH model is draining a window
# — the insight layer for model choice. This is the "look at my usage" half of the
# routing decision in AGENTS.md (§ Picking a pi model); the other half is the
# `pi:*` mise task ring. Run before/after a heavy session to see what a model cost.
set -euo pipefail

: "${OLLAMA_API_KEY:?OLLAMA_API_KEY is required (mise.toml [env] sets it from the agenix secret)}"

raw="$(curl -fsS -H "Authorization: Bearer $OLLAMA_API_KEY" https://ollama.com/api/usage)"

python3 - "$raw" <<'PY'
import json, sys

d = json.loads(sys.argv[1])

def pct(x):
    return f"{x * 100:.2f}%" if isinstance(x, (int, float)) else "?"

act = d.get("activity", {})
period = act.get("period", {}) or {}
print("== paid / per-token usage (last 4 weeks) ==")
start = (period.get("starting_at") or "?")[:10]
end = (period.get("ending_at") or "?")[:10]
print(f"  cost: {act.get('cost','?')}   ({start} → {end})")
models = act.get("models", []) or []
if models:
    for m in models:
        print(f"    {m.get('name','?'):24} cost={m.get('cost','?')}  reqs={m.get('request_count','?')}")
else:
    print("    (no billable usage — plan-only 👍)")

def show(window, label):
    w = (d.get("limits", {}) or {}).get(window, {}) or {}
    print(f"\n== {label} ({window}) — {pct(w.get('usage', 0))} of cap ==")
    rows = w.get("models", []) or []
    if rows:
        for m in rows:
            print(f"    {m.get('name','?'):24} requests={m.get('request_count','?')}")
    else:
        print("    (idle)")

show("session", "short rate-limit window  ← the one that throttles mid-session")
show("weekly",  "rolling plan cap         ← the actual 'run out of plan' ceiling")
PY