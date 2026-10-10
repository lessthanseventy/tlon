// /consult, /fresh and the consult tool: ask a different ollama model, with the session's recent
// transcript (consult) or without it (fresh). The pure half — argument parsing, the transcript the
// delegate reviews, the vision prompt — lives here so the mod's side effects stay thin.

export const DEFAULT_MODEL = "minimax-m3";

// The ollama.com models a first token may name (`/consult deepseek-v4-pro am I on track?`); any
// other first token is part of the prompt.
export const KNOWN_MODELS = ["glm-5.2", "deepseek-v4-pro", "deepseek-v4.1-flash", "kimi-k2.7-code", "minimax-m3", "qwen3-coder"];

// The ollama models that read images; a session on any other one gets its image reads described.
export const VISION_MODELS = ["minimax-m3"];

// ~5k tokens: enough of the arc for a review, the most recent turns winning.
const MAX_TRANSCRIPT_CHARS = 20_000;

export type Turn = { role: string; text: string };

// `/consult deepseek-v4-pro am I on track?` → that model; `/consult am I on track?` → the default.
export function parseArgs(args: string): { model: string; prompt: string } {
  const trimmed = args.trim();
  if (!trimmed) return { model: DEFAULT_MODEL, prompt: "" };
  const first = trimmed.split(/\s+/)[0] ?? "";
  if (KNOWN_MODELS.includes(first)) return { model: first, prompt: trimmed.slice(first.length).trim() };
  return { model: DEFAULT_MODEL, prompt: trimmed };
}

export type ToolArgs = { ok: true; model: string; context: "none" | "transcript"; prompt: string } | { ok: false; error: string };

// The tool's model is a named field, not a leading token that could be prose, so an unknown one is
// an error rather than the command's fall-through to the default.
export function parseToolArgs(params: Record<string, unknown>): ToolArgs {
  const prompt = typeof params.prompt === "string" ? params.prompt.trim() : "";
  if (!prompt) return { ok: false, error: "consult: `prompt` is required." };
  let model = DEFAULT_MODEL;
  const m = params.model;
  if (m !== undefined && m !== null && m !== "") {
    if (typeof m !== "string" || !KNOWN_MODELS.includes(m)) {
      return { ok: false, error: `consult: unknown model "${String(m)}" — known models: ${KNOWN_MODELS.join(", ")}.` };
    }
    model = m;
  }
  return { ok: true, model, context: params.context === "none" ? "none" : "transcript", prompt };
}

// The recent session as a transcript the delegate reviews: user and assistant text from the last
// 40 turns, earlier consult answers and the tlon brief left out, the tail kept when it is long.
export function serializeTranscript(turns: Turn[]): string {
  const blocks: string[] = [];
  for (const t of turns.slice(-40)) {
    if (t.role !== "user" && t.role !== "assistant") continue;
    const text = t.text.replace(/<tlon-brief>[\s\S]*?<\/tlon-brief>/g, "").trim();
    if (!text || text.startsWith("[/consult ") || text.startsWith("[/fresh ")) continue;
    blocks.push(`### ${t.role}\n${text}`);
  }
  if (blocks.length === 0) return "";
  let joined = blocks.join("\n\n");
  if (joined.length > MAX_TRANSCRIPT_CHARS) joined = joined.slice(-MAX_TRANSCRIPT_CHARS);
  return (
    "You are being consulted mid-session by another agent that hit a question it wants a " +
    "second opinion on. Here is the recent transcript of that session for context:\n\n" +
    joined +
    "\n\n---\n\nNow answer the consulting agent's question below as a specialist."
  );
}

// The asking seat's deny rules (launch.sh's TLON_PERMISSIONS_DENY, comma-separated) as the
// delegate's --settings, so a consult reads no file the seat itself may not.
export function delegateSettings(deny: string | undefined): string {
  const rules = (deny ?? "").split(",").map((r) => r.trim()).filter(Boolean);
  return JSON.stringify({ permissions: { deny: rules } });
}

export function isImagePath(path: string): boolean {
  return /\.(png|jpe?g|gif|webp|bmp)$/i.test(path);
}

export function mimeOf(path: string): string {
  switch (path.toLowerCase().split(".").pop()) {
    case "jpg":
    case "jpeg":
      return "image/jpeg";
    case "gif":
      return "image/gif";
    case "webp":
      return "image/webp";
    case "bmp":
      return "image/bmp";
    default:
      return "image/png";
  }
}

const VISION_PROMPT_GENERIC =
  "Describe this screenshot precisely for another AI agent that cannot see it. " +
  "Cover: overall layout and structure, ALL visible text (verbatim where readable), " +
  "UI elements and their state, colors, and anything notable or unusual. " +
  "Be specific and complete — the reader will reason about the screen from your words alone.";

// Aimed at what the operator asked when the latest user message has words beside the image path;
// the generic description for a bare paste.
export function visionPrompt(turns: Turn[]): string {
  const framing = [...turns].reverse().find((t) => t.role === "user" && t.text.trim());
  const words = framing?.text.split(/\s+/).filter((tok) => !isImagePath(tok)).join(" ").trim();
  if (!words) return VISION_PROMPT_GENERIC;
  return (
    "The user pasted this screenshot in the context of the following message:\n\n" +
    '"""\n' + words + '\n"""\n\n' +
    "Describe what's in the image. Focus on what's relevant to the user's message — " +
    "the parts that help answer their question or address what they raised — but still " +
    "cover the full screen (layout, ALL visible text verbatim where readable, UI elements " +
    "and their state, colors, anything notable) so nothing load-bearing is missed. " +
    "Be specific and complete; the reader will reason about the screen from your words alone."
  );
}
