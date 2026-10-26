Closes #631.

One `oneshot_model` knob in `OperatorConfig` (a `provider/model` from `Profiles.model_choices`, default
`ollama-cloud/deepseek-v4.1-flash`) is now the only model every one-shot reads: `Generator`, `Office.Writer`
(pools become `[knob ×3]` / `[haiku, haiku, knob]`; the kimi literal goes), `Recall.Judge`,
`Import.ClaudeSessions`, the oracle's `:ollama` side (loses `deepseek-v4-pro:high`) and Bootstrap's quain seed.
`Profiles.model_name/1` is public for the knob's validation. `docs/models.md` updated.

Checked: new tests in `operator_config_test` and `writer_test` (red first), `grep -rn ollama-cloud server/lib`
leaves only the profiles ring, the knob's default and ollama_window; full `menard run check --in server` below.
Hand-back: the operator sets `oneshot_model` → `anthropic/claude-haiku-5-5` in the live config.
