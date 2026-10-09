#!/usr/bin/env bash
# ollama-usage — read the ollama.com plan meters: GET /api/balance (what is left this period)
# and GET /api/usage?range=7d (requests, and spend + tokens where the plan reports them).
#
# Credit plans get included credits in USD per monthly period (`balance_usd` of `allowance_usd`,
# resetting at `period.until`), billed per model per token. Legacy plans instead get a short
# session window and a weekly cap as `remaining_percent` + `resets_at`, and /api/usage omits
# cost and tokens for their requests. Neither endpoint breaks usage down by model yet
# (docs.ollama.com/api/cloud-usage: "coming soon"). Both allow 10 requests/minute per user.
set -euo pipefail

: "${OLLAMA_API_KEY:?OLLAMA_API_KEY is required (mise.toml [env] sets it from the agenix secret)}"

get() { curl -fsS -H "Authorization: Bearer $OLLAMA_API_KEY" "https://ollama.com$1"; }

balance="$(get /api/balance)"
usage="$(get '/api/usage?range=7d')"

python3 - "$balance" "$usage" <<'PY'
import json, sys

b = json.loads(sys.argv[1])
u = json.loads(sys.argv[2])
inc = b.get("included") or {}

def usd(x):
    if not isinstance(x, (int, float)):
        return "?"
    return f"${x:,.2f}" if x >= 1 or x == 0 else f"${x:.4f}"

if "allowance_usd" in inc:
    allowance, left = inc["allowance_usd"], inc.get("balance_usd")
    used = allowance - left if isinstance(left, (int, float)) else None
    pct = f"{used / allowance * 100:.1f}%" if used is not None and allowance else "?"
    period = inc.get("period") or {}
    print("== included credits (this period) ==")
    print(f"  used {usd(used)} of {usd(allowance)} ({pct})   left {usd(left)}")
    print(f"  period {(period.get('from') or '?')[:10]} → resets {period.get('until') or '?'}")
elif "session" in inc or "weekly" in inc:
    print("== legacy plan limits (no credits on this account yet) ==")
    for name in ("session", "weekly"):
        w = inc.get(name) or {}
        rem = w.get("remaining_percent")
        used = f"{100 - rem:.2f}%" if isinstance(rem, (int, float)) else "?"
        print(f"  {name:8} used {used:>7}   resets {w.get('resets_at', '?')}")
else:
    print(f"== included: unrecognised /api/balance shape: {json.dumps(inc)} ==")

print(f"  purchased credits left: {usd((b.get('purchased') or {}).get('balance_usd'))}")

t = u.get("totals") or {}
print(f"\n== last 7 days ({(u.get('from') or '?')[:10]} → now) ==")
line = f"  requests {t.get('request_count', '?')}"
if "usage_usd" in t:
    line += (f"   spend {usd(t['usage_usd'])}   tokens in {t.get('input_tokens', '?')}"
             f" (cached {t.get('cached_input_tokens', '?')}) out {t.get('output_tokens', '?')}")
else:
    line += "   (no spend/token counts: ollama.com omits them for legacy-plan requests)"
print(line)
for k in u.get("buckets") or []:
    cost = f"  {usd(k['usage_usd'])}" if "usage_usd" in k else ""
    mark = " (so far)" if k.get("partial") else ""
    print(f"    {(k.get('from') or '?')[:10]}  {k.get('request_count', 0):>6} reqs{cost}{mark}")
print("  per-model breakdown: not exposed by ollama.com's API yet")
PY
