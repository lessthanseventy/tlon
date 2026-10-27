# Review: 405-quota-need-detect-provider-429-402-i @ 6a937db

**Verdict: request_changes.** One defect, in the last commit: the one-shot door's quota entry does not survive the next attention sweep. Commits 1–3 are sound and match hronir's rulings (#15125). Checks: `menard run check --in server` 2239/0, `mise run check` green, `bench_contrast` unmeasurable (not a regression row; no finding).

## 1. The one-shot entry is pruned on the next tick (6a937db) — blocking

`Shifts.refused/2` → `note_oneshot/2` writes the entry under a key no pane has:

```
remember(ws, "oneshot/#{provider}", quota_entry(provider, line, %{"until" => until}), "quota_out")
```

Every attention tick ends with `Server.Shifts.prune(workspace_id, panes)` (attention.ex:117), `panes` built as `"#{tab.agent}/#{tid}/#{tab.name}"`. `prune/2`, untouched by this branch, keeps only those keys in **both** knobs:

```
for knob <- ["limits_seen", "quota_out"] do
  kept = Map.filter(seen, fn {key, _} -> MapSet.member?(panes, key) end)
```

`"oneshot/ollama-cloud"` is never a member, so the entry is deleted at the first tick after the refusal. The 30-minute lifetime the commit message, the `refused/2` doc, pr.md and AGENTS.md all promise is, in production, "until the next sweep". The ModelCli test passes because nothing calls `prune/2` in it. Read from the code, not run: I have no write seat to add the test.

Fix (one line plus a test in the existing `describe "an ollama seat's pane prints its plan's 429"`, where emma is already on ollama-cloud so `seats_on?/2` holds):

```
--- a/server/lib/server/shifts.ex
+++ b/server/lib/server/shifts.ex
@@ def prune(workspace_id, panes) do
     for knob <- ["limits_seen", "quota_out"] do
       seen = seen(workspace_id, knob)
-      kept = Map.filter(seen, fn {key, _} -> MapSet.member?(panes, key) end)
+      # a one-shot's entry (`refused/2`) is no pane's: its `until` retires it, not a pane going
+      kept = Map.filter(seen, fn {key, _} -> String.starts_with?(key, "oneshot/") or MapSet.member?(panes, key) end)
```

```
    test "a one-shot's refusal survives the pane prune: it is no pane's", %{ws: ws} do
      :ok = Shifts.refused("ollama-cloud", hd(@ollama_429s))
      :ok = Shifts.prune(ws.id, MapSet.new(["emma/1/w1"]))
      assert [%{provider: "ollama-cloud", until: %DateTime{}}] = out(ws)
    end
```

RED first (the assert gets `[]` on 6a937db), then GREEN.

## 2. What I checked and found sound

- 9bdee51 `@quota_out`: the four verbatim Claude lines match; EAI_AGAIN and "response stopped arriving" do not. Stands alone as hronir asked.
- ff70686 `@provider_limit` reads the status off `Request rejected (\d{3})` only; no 402 pattern ships. `spent_plan?/1` is 429 ∧ "usage limit", raised at once; any other status is `Logger.info`'d once per line per pane (fingerprint in `limits_seen`). `dated_at/6` gives `~N[2026-09-28 09:00:00]` for the spend-limit line.
- 29b4be7 `Needs.quota/0`: `Enum.uniq_by(claude ++ refused ++ spent, & &1.key)` — the pane line precedes the balance poll under `quota:<ws>:ollama-cloud`, so the sharper signal wins the slot. Entries written before this branch lack `"provider"` and default to `"anthropic"`: backward compatible.
- `quota_check/4`: `provider_of/2` nil → `:ok`; the old "pi pane printing the words" test still holds since the ollama path runs `provider_limit/1`, not `@quota_out`.
- `ModelCli`: `refused/2` touches the Repo only on a regex hit; every caller (judge, generator, writer, grade, retro, oracle, extractor) runs in the app. `parse_model("haiku")` → `"anthropic"`, so the guard in `refused/2` is reached as the test assumes.
