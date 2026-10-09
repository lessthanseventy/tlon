Reviewed by tzinacan — no free reviewer was at the builder's grade (greybeard); this is a lower-grade review. Gate green per the recorded checks; I read the diff, did not re-run the suite.

# Verdict: request_changes (3 small fixes)

## Blocking

1. **`Persona.edit/3` stores unvalidated JSON** (`server/lib/server/persona.ex`, `edit/3`). `Map.take(attrs, ~w(backstory voice))` and the quirk values accept any type. `PATCH …/persona {"backstory": 5}` stores a number; `personaLines` (`office/kit/persona.ts`) then calls `p.backstory.split` and throws on every render of that card. A non-map `"quirks"` makes `Map.take(attrs["quirks"] || %{}, …)` raise (500). Fix: keep only binary values (trimmed, length-capped), ignore the rest, treat a non-map `quirks` as `%{}`; add tests for `{"backstory": 5}` and `{"quirks": "x"}`.
2. **`reroll` destroys a good or hand-edited persona when the generator is off or capped** (`reroll/2` → `generate/3` → `ask/3` falls back, then an unconditional `Repo.update`). With banter off, E → "draw a new one" replaces a model-written or edited persona with a handwritten fallback, with no way back. Fix: on reroll, if the generator did not return a model persona, return `{:error, reason}` and keep the stored one (TUI/CLI show the refusal). `ensure` on a seat with none may still store the fallback.
3. **A seat hired through the office or operator API gets no persona.** Spec: "generated once at hire"; check: "a hired seat gets a persona". Only `tlon-cli hire` calls `Persona.ensure`; `POST /api/workspaces/:id/coworkers` and the TUI hire do not, so the card is empty until someone presses E. Fix: call `Persona.ensure/2` after the seat in the API hire handler, off the request path (a supervised Task) so the model call does not block the 201.

## Not blocking (filed as follow-ups)

- `ToyPool.refresh_due/2` has no caller; nothing schedules the weekly visitors refresh or reaction generation (the builder named this).
- A `{:reactions, seat}` refresh with no valid event stores an empty map, which counts as fresh for 7 days.
- TUI reroll has no confirm though it wipes hand edits.
- `tlon-cli persona` is verified only by the names gate, not on a live node.

## Checked, fine

- `Generator.take_slot/0`: atomic upsert, counts failures, survives restart; banter gate and cap order correct.
- Pool and persona reads never call the model, so the render path stays model-free.
- Migrations, snapshot plumbing (`Coworker`/`Office`), AGENTS.md and design-doc entries are in sync.
