# Models and benchmarks

What a session on this repo runs on, and the benchmarks that spend real quota. A seat's model is
routed by the server (`Server.Profiles`); this is for the operator and anyone launching a session by hand.

## Picking a model — the routing, as tasks

Two subscriptions, two buckets. The **$200 Claude plan** (5-hour + weekly caps) staffs every seat — a
seat runs its grade's Claude model (`Server.OperatorConfig`), unless retargeted; the **ollama.com Pro plan**
carries the server's one-shots (banter, the judge, titles, the toys) and the launchers below. ollama.com now meters plans in
monthly usage credits spent at per-model per-token rates; accounts still on a legacy plan (this one, as of
2026-10) get a short session window and a weekly cap instead. Either way "cost" means *which capped bucket
am I draining*, so the rule is: **push work down to the cheapest bucket that can still do it well.**
Every agent runs in **Claude Code**; an ollama model through Claude Code's gateway setting
(`adapters/claude-code/gateway.sh` points `ANTHROPIC_BASE_URL` at ollama.com or the local daemon), so a
session on an ollama model sends nothing — its subagents and background requests included — to the
Claude plan.

The routing is not a proxy — it's five mise tasks, each a named model profile (the loop *is* the
aliasing layer). Run `mise run ollama:usage` to see credits used of included and the reset date (or the
legacy session/weekly meters), plus daily request counts. Inside a session `/model <name>` switches to
another model on the same provider.

| Task | Model | Reach for it when |
|---|---|---|
| `mise run claude:balanced` | glm-5.2 | The strong default — Claude/GPT-alike, 976K ctx. Reach for it when the cheap one can't do the job, before escalating to claude:deep. |
| `mise run claude:deep`     | deepseek-v4-pro, effort high | Hard reasoning/logic — the escalate-before-you'd-miss-Claude tier. |
| `mise run claude:code`     | kimi-k2.7-code | Coding-heavy work; code-specialized, fewer thinking tokens. |
| `mise run claude:fast`     | deepseek-v4.1-flash, effort low | Quick/cheap throwaway, fast tier — the efficient-MoE model that drains the plan slowest. |
| `mise run claude:local`    | qwen3-coder (local daemon) | Free/offline grunt, tight iteration loops — zero cloud budget. |
| `mise run server:claude`   | the Claude plan's default | When it has to be Claude. |
| `mise run claude:operator` | the Claude plan's default | Your own session as the operator: the tlon-citizen mod's operator band (what waits on you, the release, your streak) and each coworker's ask put to you. No thread, no citizen identity. |

Every launcher but `claude:operator` also makes the session a **server citizen**: it opens a fresh server thread (or JOINs one
with a trailing id — `mise run claude:code -- 42`) and hands the session its identity, so it shows up in
`server:roster` and briefs from the thread. If the server channel is down, Claude Code still launches —
just not as a citizen.

Claude Code's own prompt is ~20k tokens a request, so on credits every turn costs more than a bare
completion; the server's one-shots (banter, the judge, titles) run `--bare` with no tools for that reason
(`Server.ModelCli`, 79 tokens in). Every one-shot reads **one** knob, `oneshot_model` in `~/.config/tlon/config.json`
(a `provider/model` from the ring above or the Claude choices; default `ollama-cloud/deepseek-v4.1-flash`): banter,
the pets, titles, the judge, the oracle's ollama side and the toys. Set it to `anthropic/claude-haiku-5-5` to run them
on the Claude plan; there is no second copy of the default. Two things that bite: **glm-5.2 is a reasoning model** (separate
`reasoning` + `content` fields) — give it token headroom or `content` comes back empty while thinking
eats the budget; and **`kimi-k3` is deliberately absent** — ollama.com serves it as *extra* usage (HTTP
402), billed per-token on top of the plan, so it's out of the model ring (`Server.Profiles`). Every model
above is plan-covered.

## Benchmarks

- `mise run bench:longmemeval` — LongMemEval (agent-memory-benchmark's harness, ollama.com answers and judges) against
  server recall on the throwaway `tlon_bench` db, never the live store; `bench/longmemeval/bridge.exs` says what each
  `TLON_BENCH_MODE` measures, and `-- --memory bm25` runs the keyword reference on the same slice.
- `mise run bench:roles -- --suite canary|full [--role R] [--model provider/model[:effort]]` — can each coworker
  role do its job on the model it is routed to, and at what cost: frozen tasks per role (`bench/roles/tasks/`),
  graded, run headless through the role's own harness; `bench/roles/README.md` is the table, newest first. It
  spends real plan quota and touches no db (`Server.Bench.Roles`).

