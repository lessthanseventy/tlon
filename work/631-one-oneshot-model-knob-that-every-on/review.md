# Review — #631 one `oneshot_model` knob that every one-shot reads (round 2)

**Verdict: approve.** Branch head cd62d2d8325e, read as the diff since my first verdict (f6451f4) excluding `work/631-…/`: three hunks, four files counting pr.md. The server's own gate passed on exactly this sha (`mise run check`, exit 0, 07:56Z); I did not re-run it.

## Findings

1. **Andrew's send-back (#13398) is done to the letter.** `server/lib/server/mcp/tools/oracle.ex:55` reads `defp defaults(:ollama), do: {"claude", "ollama-cloud/deepseek-v4-pro:high"}` again; the knob's doc at `operator_config.ex:136` drops "the oracle"; `docs/models.md:42` names the oracle as the exception and says why ("the other family's second opinion, not a one-shot"). No other source line changed.

2. **Done-criterion holds with the one allowed literal.** `grep -rn ollama-cloud server/lib` outside `profiles.ex`: the knob's default (operator_config.ex:134), the oracle line (oracle.ex:55, allowed by #13398), the `warmth_seconds` doc example (lines 17, 251) and provider-name mentions in `ollama_window.ex`. Nothing is a stray model default.

3. **My round-1 follow-up on the oracle moduledoc is resolved by the revert**, not by an edit: with the oracle back on its own ollama model, "the cost lands on the bucket the caller is NOT draining" is true again. Not re-raised.

4. **Round-1 findings stand unchanged**: every one-shot site (Generator, Writer both pools, Recall.Judge, Import.ClaudeSessions, Bootstrap quain seed) reads the knob; validation runs on both the file and `put_settings`; default stays `ollama-cloud/deepseek-v4.1-flash` per #13303; QA passed on the settings room (#13368).

5. **Nit, no action:** pr.md line 10-11 says the grep "leaves only the profiles ring, the knob's default and ollama_window", omitting the oracle literal that this very commit restores. ireneo's thread message #13402 has the accurate list; the PR body is one clause behind it.

## Follow-ups (non-blocking)

- Office settings edits `oneshot_model` as free text (carried from round 1); see follow_ups.
