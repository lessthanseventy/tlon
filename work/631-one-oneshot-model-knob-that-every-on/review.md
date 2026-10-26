# Review — #631 one `oneshot_model` knob that every one-shot reads

**Verdict: approve.** One commit, 8b7fe01, read in full against the brief (#13279) and tertius's default ruling (#13303). The server's own gate passed on exactly this sha (`mise run check`, exit 0, 06:09Z); I did not re-run it.

## Findings

1. **Spec: every named site reads the knob, nothing else.** Generator, Writer (both pools and the `banter_cmd` stand-in default), Recall.Judge, Import.ClaudeSessions, Oracle `defaults(:ollama)` and Bootstrap's quain seed all call `Server.OperatorConfig.oneshot_model()`. The kimi literal and `deepseek-v4-pro:high` are gone, as the brief accepted.

2. **Done-criterion holds.** `grep -rn ollama-cloud server/lib` outside `profiles.ex` leaves the knob's default (operator_config.ex:134), the `warmth_seconds` doc example (lines 17, 251) and `ollama_window.ex`. The latter two are the provider's name, not a model default. Nothing to chase.

3. **Default stays `ollama-cloud/deepseek-v4.1-flash`**, per #13303; haiku is the operator's live setting after landing. The docs paragraph says exactly that. pr.md names the hand-back.

4. **Validation is sound on both doors.** `valid(%{choice: "model"}, v)` sits before the plain `string` clause, so it wins for this knob; `value/2` runs the same check on the file, so a hand-edited `"nope/none"` falls back to the default rather than reaching `ModelCli`. `put_settings` rejects with "must be a provider/model from the model choices". Both paths are in the new operator_config test; the writer test pins `[haiku, haiku, knob]` / `[knob, knob, knob]` against a non-default knob.

5. **`Profiles.model_name/1` made public** with a doc and spec, no behaviour change; its one prior caller (line 1101) still compiles.

6. **Nit, no action:** Writer's claude-pool fallback retries the knob's model after a failed haiku call. With the knob set to haiku that is a second try on the same model. Harmless.

## Follow-ups (non-blocking)

- Oracle's moduledoc still promises the other bucket; see follow_ups.
- The office settings room edits `oneshot_model` as free text; see follow_ups.
