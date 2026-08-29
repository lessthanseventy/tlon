// A direct out-of-band text completion against ollama.com — the same mechanism adapters/consult
// already uses (describeImage's fetch, runPi's spawn). Total-recall's cadence capture calls this
// so extraction runs WITHOUT an agent turn, dissolving the injection-timing problem. Text-only,
// with the reasoning-model fallback consult learned the hard way (content can be empty when the
// thinking budget is spent, so fall back to `reasoning`).

// Never hang forever: a capture call with no deadline wedged the whole capture path once —
// `capturing` stayed true, every later flush early-returned, and shutdown awaited the hang.
const DEFAULT_TIMEOUT_MS = 30_000;

export async function completeText(model: string, prompt: string, signal?: AbortSignal): Promise<string> {
  const key = process.env.OLLAMA_API_KEY;
  if (!key) throw new Error("OLLAMA_API_KEY not set — can't run capture extraction");

  const res = await fetch("https://ollama.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    signal: signal ?? AbortSignal.timeout(DEFAULT_TIMEOUT_MS),
    body: JSON.stringify({
      model,
      max_tokens: 1024,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`${model} HTTP ${res.status}: ${body.slice(0, 300)}`);
  }

  const json = (await res.json()) as {
    choices?: Array<{ message?: { content?: string; reasoning?: string } }>;
  };
  const msg = json.choices?.[0]?.message;
  return msg?.content?.trim() || msg?.reasoning?.trim() || "";
}
