# Server.Trust per model (#708)

## Problem
`Server.Trust` keys a builder's record by coworker name. A seat can be re-pointed at another model
(`Server.Profiles`), and a hired reviewer/builder inherits its peers' model, so one name's record mixes
models. The ask (#504): a record per coworker **and model**. A workline does not say which model built it.

## Decisions

1. **Where the model is recorded: the leads line.** `Server.Trust.leads_line/2` becomes
   `leads_line(name, stage, model)`: `→ ireneo leads (build stage) · anthropic/claude-sonnet-5-5 (claude_code)`,
   the model from `Server.Profiles.model_label(workspace_id, name)` at the moment `hand_to/4`
   (`workline.ex`) takes the workline for `name`. No new column or migration: the line is already how
   Trust finds a builder, and the seat's profile is what its pane launches on (`TLON_MODEL`, `mcp/spawn.ex`).
   Nil label → the line has no suffix. The `like "→ name leads (build stage)%"` matches keep working
   (the suffix and any note come after).
2. **Lead or model changes.** The builder is the last `leads (build stage)` line, as today; its model is
   that line's. A lead change posts a new line (new model). A model change under the *same* lead posts
   nothing (`hand_to` is a no-op for the current lead), so the record keeps the model the builder
   took the stage with. Accepted: only the model as launched is seen, and a mid-stage re-point is rare.
3. **`record/1` and `record/2`.** `record(name)` is unchanged (all models, unknown included).
   `record(name, model)` is the same query with the line's model suffix equal to `model`. `builder/1`
   returns `{name, model | nil}` (internal; `allowance/2` is its only caller).
4. **`allowance/2`.** Stays per coworker (operator, #16512). The approval card's evidence
   map gains `model` (the builder's model on this workline) so the card says which model earned it.
5. **Backfill: none.** Lines written before this have no suffix: model `nil` = unknown. They count in
   the per-coworker record and are excluded from every `record(name, model)` (never guessed as the seat's
   current model). No history is rewritten.
6. **Roster tie-break (#504, #417).** Not changed here. When #417 lands, Roster may call
   `record(name, model)` with the candidate seat's current `model_label` where it ranks candidates;
   the function is the whole interface. If that record is below `@earned_after` builds, fall back to `record(name)`.

## Out of scope
Grader-score averaging (dropped: they rate the change, not the builder). Trust's thresholds (window 20,
8 builds, 80%, ceiling 4) are untouched.

## Decided — operator's call (gate law), #16512: per coworker
Should `allowance/2` use `record(name, model)` instead of `record(name)`? Stricter: a re-pointed seat
loses its earned `auto_land_risk` step until it earns 8 builds on the new model. Not taken: it changes who gets
auto-approval; a later per-model allowance is a separate operator decision.

## Plan (build)
1. Red: `trust_test` — a build under two models yields `record(name, m1)` / `record(name, m2)` splits;
   a suffix-less line counts in `record(name)` only.
2. `leads_line/3`, `hand_to` passes the model, `record/2`, `builder/1` → `{name, model}`, card `model`.
3. Update `Server.Trust` moduledoc and `server/docs` mention; `mise run check`.
