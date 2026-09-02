// Total-recall slice C: boundary + cadence fact-capture. Instead of dumping the whole
// about-to-compact transcript into a cheap model (which overflows — at compaction the frontier
// context is full by definition), we capture the DELTA on a cadence: every N turns, and again at
// compaction/shutdown, we extract durable facts from only the turns since a watermark. Each call's
// input is bounded to a few turns regardless of how full the session is. The extraction runs
// out-of-band (a consult-style completion, see llm.ts) so it needs no agent turn — dissolving the
// injection-timing problem. Banked facts are `derived` (never `stated`): automation feeds the
// low-authority lanes; the human promotes (total-recall design §principle).
//
// This module is the PURE core — delta-slicing, prompt-building, tolerant parse — unit-pinned
// without a live session or model.

export interface Entry {
  message?: { role?: string; content?: unknown };
}

export interface CapturedFact {
  text: string;
  kind: "learned" | "decision";
  intent?: string;
}

export interface Extraction {
  facts: CapturedFact[];
  questions: string[];
}

// Cap a delta's serialized size — a backstop; the cadence keeps deltas small, but a long-idle
// session that compacts before its first tick could still hand over a big slice. Tail wins.
const MAX_DELTA_CHARS = 16_000;

// The default cheap model that runs cadence extraction out-of-band (ollama-cloud). Flash: efficient
// MoE, large enough context for a bounded delta, cheap enough to run on a cadence. The single
// source of truth for BOTH harness reflexes — pi's extension.ts (overridable via funes-recall.json)
// and claude-code's cc-capture.ts (fixed) — so the two never drift.
export const DEFAULT_CAPTURE_MODEL = "deepseek-v4-flash";

// The entries added since the watermark (an index into the running entry list). Returns the slice
// to capture and the new watermark to store once it's captured.
export function deltaSince(entries: Entry[], watermark: number): { slice: Entry[]; nextWatermark: number } {
  const start = Math.max(0, Math.min(watermark, entries.length));
  return { slice: entries.slice(start), nextWatermark: entries.length };
}

// Render a delta as a plain role/text transcript for the extractor. Only user/assistant text
// (tool spam and the funes brief injections are dropped); tail-capped as a backstop.
export function serializeDelta(entries: Entry[]): string {
  const blocks: string[] = [];
  for (const e of entries) {
    const role = e.message?.role;
    if (role !== "user" && role !== "assistant") continue;
    const text = extractText(e.message?.content);
    if (!text) continue;
    if (text.startsWith("[/consult ") || text.startsWith("[/fresh ")) continue;
    if (text.startsWith("<funes-brief")) continue;
    blocks.push(`### ${role}\n${text}`);
  }
  let joined = blocks.join("\n\n");
  if (joined.length > MAX_DELTA_CHARS) joined = joined.slice(-MAX_DELTA_CHARS);
  return joined;
}

// Pull text out of a message's content (string, or array of {type:"text",text} blocks).
export function extractText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  const parts: string[] = [];
  for (const block of content) {
    const b = block as { type?: string; text?: string } | null;
    if (b && b.type === "text" && typeof b.text === "string") parts.push(b.text);
  }
  return parts.join("\n").trim();
}

// The same conservative credential shapes funes' write-path scanner (Server.Secrets) refuses —
// mirrored here because capture EGRESSES the raw delta to ollama.com before funes ever sees it:
// the inbound bank_fact scan fires one network hop too late to stop a pasted key leaving the box.
// Pattern-based, not entropy-based, for the same reason as the Elixir side (SHAs and hashes are
// legitimate technical facts).
const SECRET_PATTERNS: Array<[string, RegExp]> = [
  ["aws-access-key", /\bAKIA[0-9A-Z]{16}\b/g],
  ["api-key-sk", /\bsk-(?:ant-)?[A-Za-z0-9_-]{20,}/g],
  ["github-token", /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b/g],
  ["github-pat", /\bgithub_pat_[A-Za-z0-9_]{22,}/g],
  ["google-api-key", /\bAIza[0-9A-Za-z_-]{35}\b/g],
  ["slack-token", /\bxox[baprs]-[A-Za-z0-9-]{10,}/g],
  ["private-key", /-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----/g],
];

// Replace any obvious credential in an outbound delta with a labelled placeholder. Run BEFORE the
// completion call — the redacted text still tells the extractor a credential was discussed, which
// is itself a durable fact, without the credential ever leaving the machine.
export function redactSecrets(text: string): string {
  let out = text;
  for (const [label, re] of SECRET_PATTERNS) {
    out = out.replace(re, `[REDACTED:${label}]`);
  }
  return out;
}

// The extraction prompt: durable facts + open questions from the delta, as strict JSON. Kinds are
// limited to learned/decision — a `constraint` is the operator's stated authority, never something
// an extractor infers (that's the provenance line the whole design turns on).
export function buildExtractionPrompt(delta: string): string {
  return (
    "You extract durable memory from a coding session for a successor agent. From the transcript " +
    "excerpt below, list only DURABLE facts worth remembering across sessions (a specific reusable " +
    "conclusion, a decision made and why) and OPEN questions left unresolved. Ignore chit-chat, " +
    "restatements of the task, and anything uncertain.\n\n" +
    'Output ONLY minified JSON of this exact shape, nothing else:\n' +
    '{"facts":[{"text":"...","kind":"learned","intent":"..."}],"questions":["..."]}\n' +
    'kind is "learned" or "decision". intent is a short phrase for WHY this fact is worth keeping ' +
    '(what future work it serves). If nothing durable, output {"facts":[],"questions":[]}.\n\n' +
    "TRANSCRIPT EXCERPT:\n" +
    delta
  );
}

// Parse the model's output tolerantly: find the JSON object even if wrapped in prose or ``` fences,
// validate the shape, clamp kinds (anything not "decision" → "learned" — never a constraint), and
// drop empties. Any failure yields an empty extraction — a bad capture is a no-op, never a crash.
export function parseExtraction(raw: string): Extraction {
  const empty: Extraction = { facts: [], questions: [] };
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if (start < 0 || end <= start) return empty;

  let obj: unknown;
  try {
    obj = JSON.parse(raw.slice(start, end + 1));
  } catch {
    return empty;
  }
  if (!obj || typeof obj !== "object") return empty;

  const o = obj as { facts?: unknown; questions?: unknown };
  const facts: CapturedFact[] = [];
  if (Array.isArray(o.facts)) {
    for (const f of o.facts) {
      const text = typeof (f as { text?: unknown })?.text === "string" ? (f as { text: string }).text.trim() : "";
      if (!text) continue;
      const kind = (f as { kind?: unknown })?.kind === "decision" ? "decision" : "learned";
      const intent =
        typeof (f as { intent?: unknown })?.intent === "string" ? (f as { intent: string }).intent.trim() : undefined;
      facts.push({ text, kind, intent });
    }
  }
  const questions: string[] = [];
  if (Array.isArray(o.questions)) {
    for (const q of o.questions) {
      if (typeof q === "string" && q.trim()) questions.push(q.trim());
    }
  }
  return { facts, questions };
}
