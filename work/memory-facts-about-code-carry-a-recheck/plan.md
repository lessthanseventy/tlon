# Plan — facts about code carry a recheck (ticket #88)

## Already on main (checked at 1a56791)
- `Server.Recall.Strength` weighs `check_passed` +2 / `check_failed` -2; `Server.Recall` reads them from events correlated `fact:<id>`.
- `Dossier.recheck_fact/2` records a check for a fact — but only from an AGENT who ran the fact's own `check_cmd`. 0 live facts have one, so it never fires.
- `Maintain.Sweep.run/1` (Oban, every 30 min) is the periodic hook; it already does `embed_missing`.
- NOT on main: any server-side check, any extraction of symbols from fact text.

## Design (decisions)
1. **Who writes the check: a rule, not an extractor/LLM, and not the author.** `Server.Recall.CodeRefs.extract/1` is a pure function of the fact text; nothing is stored (no migration), so a rule change applies to every fact on the next sweep. Authors keep `check_cmd` for claims that need a real command.
2. **Side-effect free: the server never runs `check_cmd`** (agent-written shell). It runs only its own fixed probes, argv-only (no shell): `git cat-file -e origin/main:<path>` and `git grep -q -F -e <needle> origin/main`. Read-only, milliseconds.
3. **Refs** (only these, to keep false positives low): module `Server.Foo.Bar` → needle `defmodule Server.Foo.Bar`; path under `server/ office/ adapters/ tasks/ docs/ scripts/` → cat-file; backticked `mod.fun/N` or `Mod.fun` → needle `def fun`; `mise run a:b` → task name in `tasks/`/`mise.toml`.
4. **Verdict:** every ref found → `check_passed`; any ref gone → `check_failed`; no refs → nothing recorded. Facts that assert an absence ("no caller", "does not exist", "never", "missing", "without") are SKIPPED — a pass would boost a claim the code now contradicts. A failed recheck decays on strength's 2-week half-life, so a symbol that comes back heals.
5. **When:** in `Sweep.run`, a batch of 25 live (not forgotten/superseded) facts per sweep with a thread, never rechecked in the last 24h, least-recently-rechecked first. New facts are covered within 30 min, so there is no bank-time hook (YAGNI; revisit if sweep lag matters).
6. **Repo:** fact → thread → project → `repos` entry (`path`); first repo whose probe finds a ref counts it found; no project/repos → skip.
7. Recorded via `Dossier.record_check` (`correlation: "fact:<id>"`, cmd = `server recheck: <probe summary>`), so briefs, strength and `get_facts` need no change.

## Tasks (each one commit, test first, run in `server/`: `mise run server:test -- <file>`; final gate `mise run check`)

### 1. CodeRefs.extract — `server/lib/server/recall/code_refs.ex`, test `server/test/server/recall/code_refs_test.exs`
Red first:
```elixir
test "module, path, function and task refs" do
  t = "Server.Maintain.Sweep.run/1 in `server/lib/server/maintain/sweep.ex`; `mise run office:golden`; Server.Fact"
  assert CodeRefs.extract(t) |> Enum.sort() == Enum.sort([
    {:module, "Server.Maintain.Sweep"}, {:function, "run"}, {:path, "server/lib/server/maintain/sweep.ex"},
    {:task, "office:golden"}, {:module, "Server.Fact"}])
end
test "prose gets no refs", do: assert CodeRefs.extract("Forgetting is asymmetric in cost.") == []
test "an absence claim is skipped", do: assert CodeRefs.extract("Sim.catLetter had no caller in office/sim.ts") == []
```
Green: `@module ~r/\bServer(?:\.[A-Z][A-Za-z0-9]*)+/`, `@fun ~r/\b[A-Z][\w.]*\.([a-z_][\w?!]*)\/\d+/`, `@path ~r/\b(?:server|office|adapters|tasks|docs|scripts)\/[\w.\/-]+\.\w+/`, `@task ~r/mise run ([\w:-]+)/`, `@absence ~r/\b(no caller|does not exist|doesn't exist|never|missing|without|absent|not exist)\b/i` → `[]`. Strip trailing `.`/`,` from paths. `uniq`. Done: test green.

### 2. Probe — `server/lib/server/recall/probe.ex`, test `server/test/server/recall/probe_test.exs`
Red: build a tmp git repo in the test (`git init`, commit `server/lib/a.ex` containing `defmodule Server.A do\n def go, do: 1\nend`, `update-ref refs/remotes/origin/main HEAD`); assert `Probe.found?(repo, {:module,"Server.A"})`, `{:function,"go"}`, `{:path,"server/lib/a.ex"}` true and `{:module,"Server.Gone"}`, `{:path,"server/nope.ex"}` false.
Green: `found?/2` shells via `System.cmd("git", ["-C", repo, ...], stderr_to_stdout: true)` — argv only; exit 0 ⇒ true. `:task` greps `mise.toml tasks/` for the name (`git grep -q -F -e name origin/main -- mise.toml tasks`). Needle for function: `def #{name}`. Done: test green.

### 3. Recheck one fact — `server/lib/server/recall/recheck.ex`, test `server/test/server/recall/recheck_test.exs`
Red (uses the tmp repo from task 2 as the project's `repos: [%{name: "t", path: repo}]`; thread in that project): fact "`Server.A` exists" → `Recheck.run(fact)` returns `{:ok, :passed}` and a `check_passed` event correlated `fact:<id>`; fact naming `Server.Gone` → `{:ok, :failed}` + `check_failed`; prose fact → `:skipped`, no event; fact with no thread/project → `:skipped`; a second `run` within 24h → `:skipped` (no second event). Also assert `Recall` strength of the failed fact < the passed one (existing path, proves no strength change needed).
Green: `run/1` = refs ← `CodeRefs.extract`; `[]`⇒skip; repos ← thread→project; `Enum.all?(refs, fn r -> Enum.any?(repos, &Probe.found?(&1["path"], r)) end)`; `Dossier.record_check(%{thread_id: fact.thread_id, exit: 0|1, cmd: "server recheck: " <> refs_summary, tail: missing refs, correlation: "fact:#{fact.id}"})`. 24h dedupe: query `Event` kind in check_*, `detail["cmd"]` starts `server recheck:`, correlation, `created_at > now-24h`. Done: test green.

### 4. Sweep it — edit `server/lib/server/maintain/sweep.ex` (+ moduledoc bullet), test in the existing sweep test file
Red: two live code-shaped facts (one stale, one fine) and one forgotten → `Sweep.run()` records exactly one `check_failed` and one `check_passed`, none for the forgotten; with 30 facts only 25 rechecked per run.
Green: `sweep_fact_rechecks()` called in `run/1` before `embed_missing`: `Fact` where `is_nil(forgotten_at)`, `not is_nil(thread_id)`, not superseded (`id not in subquery(select f.supersedes ...)`), order by last recheck asc nulls first (left join latest event) , `limit 25`, `Enum.each(&Recheck.run/1)`. Wrap each in `try/rescue` so one bad fact never aborts the sweep. Done: `mise run check` green.

## Out of scope / open
- Absence-claim skip is a keyword list; a smarter negation test is future work.
- Facts naming symbols in repos outside the thread's project are skipped, not failed.
- Non-Elixir symbols (TS `catLetter`) are not extracted in v1 (only the paths and tasks they sit in); add a rule when a stale one is seen.
