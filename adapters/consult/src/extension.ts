// adapters/consult — delegate a question to a different model, then hand its answer back to
// the main session via sendUserMessage. /consult includes the recent session transcript as
// context (a rich second opinion); /fresh is a clean one-shot with just the prompt.
//
// Both spawn a transient `pi --mode json --no-session --model <id>` with no TLON_* env, so
// the adapters adapter stays quiet and no funes thread is registered by the delegate. `--mode
// json` (not `-p`) makes pi emit one JSON event per line AS IT WORKS, so the peer's answer
// streams in token-by-token instead of arriving in one lump when the delegate exits.
//
// Default model is `minimax-m3` (the one cloud model declared image-capable in flake.nix),
// so a bare `/fresh describe this` works for a pasted screenshot with no model arg.

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { Type } from "./pi.ts";
import type {
  CommandOptions,
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
  SessionEntry,
  SessionManager,
  ToolExecuteContext,
  ToolResult,
  ToolResultEvent,
  ToolResultPatch,
  ToolUpdateCallback,
} from "./pi.ts";

// Pure helpers below are exported and pinned by delegate.test.ts; the spawn/inject and
// vision-fetch seams are side-effects and untested here.

const DEFAULT_MODEL = "minimax-m3";
const PROVIDER = "ollama-cloud";

// The cloud model ring from flake.nix — used only to recognize an explicit model arg as
// the FIRST token (`/consult deepseek-v4-pro …`). If the first token isn't one of these,
// it's part of the prompt and the default model is used.
const KNOWN_MODELS = [
  "glm-5.2",
  "glm-5.1",
  "deepseek-v4-pro",
  "deepseek-v4-flash",
  "kimi-k2.7-code",
  "minimax-m3",
  "qwen3-coder",
];

// Cap the session transcript we hand to /consult, so a long session doesn't blow the
// delegate's context. ~20k chars is a rough 5k-token budget — enough to review the arc
// without footing the whole history. The most recent turns win (we slice from the tail).
const MAX_TRANSCRIPT_CHARS = 20_000;

// Both commands get the same tools — the thin/thick axis is context, not tools.
const DELEGATE_TOOLS = "read,grep,bash";

export default function consult(pi: ExtensionAPI): void {
  const consultOpts: CommandOptions = {
    description:
      "Delegate to another model WITH the current session as context (rich second opinion). /consult [model] <prompt>",
    handler: (args, ctx) => delegate(pi, args, ctx, true, "consult"),
  };
  const freshOpts: CommandOptions = {
    description:
      "Delegate to another model with NO session context (clean one-shot). /fresh [model] <prompt>",
    handler: (args, ctx) => delegate(pi, args, ctx, false, "fresh"),
  };

  pi.registerCommand("consult", consultOpts);
  pi.registerCommand("fresh", freshOpts);

  // Mechanism 2 (tlon-workspace-design §2): the SAME delegate as /consult, but a tool the
  // MODEL calls mid-turn. The command hands its answer back via sendUserMessage (a new turn,
  // hence the mid-turn refusal); the tool RETURNS the answer as its result — no new turn, so
  // it's mid-turn-safe by construction, dissolving that limit. Same engine, two doors.
  pi.registerTool({
    name: "consult",
    description:
      "Ask a different (or smarter) model for a second opinion and get its answer back " +
      "immediately as this tool's result. Use it to escalate a hard call to a stronger model " +
      "or get a fresh perspective mid-task. `context: transcript` (default) shows the peer your " +
      "recent session; `context: none` is a clean one-shot.",
    parameters: CONSULT_TOOL_PARAMS,
    execute: consultToolExecute,
  });

  // Auto-vision: transparently delegate image reads a text-only model can't ingest. See
  // onToolResult below.
  pi.on("tool_result", (event, ctx) => onToolResult(event, ctx));
}

// Shared path for /consult and /fresh: parse args, build the task, spawn the delegate,
// inject its output back as a user message.
async function delegate(
  pi: ExtensionAPI,
  args: string,
  ctx: ExtensionCommandContext,
  withContext: boolean,
  verb: "consult" | "fresh",
): Promise<void> {
  const { model, prompt } = parseArgs(args);
  if (!prompt.trim()) {
    ctx.ui.notify(`Usage: /${verb} [model] <prompt>  (default model: ${DEFAULT_MODEL})`, "warning");
    return;
  }
  // Refuse while the main agent is mid-turn: sendUserMessage triggers a turn, and stacking
  // a delegate onto a running turn would deadlock or interleave. The operator waits.
  if (!ctx.isIdle()) {
    ctx.ui.notify(`Can't /${verb} while the agent is running — wait for it to settle.`, "warning");
    return;
  }

  const contextBlock = withContext ? serializeSession(ctx) : "";
  const task = contextBlock ? `${contextBlock}\n\n---\n\n${prompt}` : prompt;

  // A slash command has no live tool-result box to stream into, but a status heartbeat still
  // tells the operator the delegate is alive (thinking → streaming) rather than silently hung.
  const startedAt = Date.now();
  const onProgress = (s: ConsultStreamState) =>
    ctx.ui.setStatus("consult", consultHeartbeat(`/${verb} ${model}`, s, startedAt));

  ctx.ui.setStatus("consult", `/${verb} ${model}: running…`);
  try {
    const out = await runPi(model, task, undefined, onProgress);
    ctx.ui.setStatus("consult", "");
    const trimmed = out.trim();
    if (!trimmed) {
      ctx.ui.notify(`/${verb} ${model}: delegate returned no output.`, "warning");
      return;
    }
    // Inject as a user message so it lands in the transcript and triggers the main agent
    // to react; the [/verb model] prefix marks it as a delegate, not operator input.
    pi.sendUserMessage(`[/${verb} ${model}] ${prompt}\n\n${trimmed}`);
  } catch (err) {
    ctx.ui.setStatus("consult", "");
    ctx.ui.notify(
      `/${verb} ${model} failed: ${err instanceof Error ? err.message : String(err)}`,
      "error",
    );
  }
}

// `/consult deepseek-v4-pro am I on track?` → model=deepseek-v4-pro, prompt="am I on track?".
// `/consult am I on track?`               → model=minimax-m3 (default), prompt="am I on track?".
export function parseArgs(args: string): { model: string; prompt: string } {
  const trimmed = args.trim();
  if (!trimmed) return { model: DEFAULT_MODEL, prompt: "" };
  const first = trimmed.split(/\s+/)[0] ?? "";
  if (KNOWN_MODELS.includes(first)) {
    return { model: first, prompt: trimmed.slice(first.length).trim() };
  }
  return { model: DEFAULT_MODEL, prompt: trimmed };
}

export type ToolArgs =
  | { ok: true; model: string; context: "none" | "transcript"; prompt: string }
  | { ok: false; error: string };

// The consult TOOL's named params (vs the command's positional [model] <prompt> string).
// Because the model passes `model` as a distinct field — not a leading token that could be
// prose — an explicit unknown model is a hard error, not the command's silent fall-through to
// the default. `context` defaults to "transcript" (the /consult behavior); "none" is /fresh.
// Pure + exported so the validation rules are pinned by tests, independent of the tool runtime.
export function parseToolArgs(params: Record<string, unknown>): ToolArgs {
  const prompt = typeof params.prompt === "string" ? params.prompt.trim() : "";
  if (!prompt) return { ok: false, error: "consult: `prompt` is required." };

  let model = DEFAULT_MODEL;
  const m = params.model;
  if (m !== undefined && m !== null && m !== "") {
    if (typeof m !== "string" || !KNOWN_MODELS.includes(m)) {
      return {
        ok: false,
        error: `consult: unknown model "${String(m)}" — known models: ${KNOWN_MODELS.join(", ")}.`,
      };
    }
    model = m;
  }

  const context = params.context === "none" ? "none" : "transcript";
  return { ok: true, model, context, prompt };
}

const CONSULT_TOOL_PARAMS = Type.Object({
  prompt: Type.String({ description: "The question to ask the consulted model." }),
  model: Type.Optional(
    Type.String({
      description: `Which model to consult (default ${DEFAULT_MODEL}). One of: ${KNOWN_MODELS.join(", ")}.`,
    }),
  ),
  context: Type.Optional(
    Type.Union([Type.Literal("none"), Type.Literal("transcript")], {
      description:
        "How much of your session the peer sees: 'transcript' (your recent session — a rich " +
        "second opinion, the default) or 'none' (a clean one-shot with just the prompt).",
    }),
  ),
});

// The tool's engine is the command's engine: build the task (optionally with the session
// transcript), run the same transient `pi -p` delegate, and RETURN its output as the result —
// no sendUserMessage, no isIdle() refusal (returning-as-result is mid-turn-safe). `signal` is
// the model's turn-abort: Esc kills the delegate mid-flight.
async function consultToolExecute(
  _id: string,
  params: Record<string, unknown>,
  signal: AbortSignal,
  onUpdate: ToolUpdateCallback,
  ctx: ToolExecuteContext,
): Promise<ToolResult> {
  const parsed = parseToolArgs(params);
  if (!parsed.ok) return { content: [{ type: "text", text: parsed.error }], isError: true };
  const { model, context, prompt } = parsed;

  const contextBlock = context === "transcript" ? serializeSession(ctx) : "";
  const task = contextBlock ? `${contextBlock}\n\n---\n\n${prompt}` : prompt;

  // Stream the peer's answer into the tool's live result box as it arrives, and keep a status
  // heartbeat going during the (possibly long) reasoning pause before the first answer token —
  // so the operator sees it's alive, not hung, the whole way through.
  const startedAt = Date.now();
  const onProgress = (s: ConsultStreamState) => {
    if (s.visible) onUpdate?.({ content: [{ type: "text", text: s.visible }] });
    ctx.ui.setStatus("consult", consultHeartbeat(`consult ${model}`, s, startedAt));
  };

  ctx.ui.setStatus("consult", `consult ${model}: running…`);
  try {
    const out = await runPi(model, task, signal, onProgress);
    ctx.ui.setStatus("consult", "");
    const trimmed = out.trim();
    if (!trimmed) {
      return { content: [{ type: "text", text: `consult ${model}: delegate returned no output.` }], isError: true };
    }
    return { content: [{ type: "text", text: trimmed }] };
  } catch (err) {
    ctx.ui.setStatus("consult", "");
    return {
      content: [
        { type: "text", text: `consult ${model} failed: ${err instanceof Error ? err.message : String(err)}` },
      ],
      isError: true,
    };
  }
}

// Pull entries from the session manager and hand them to the pure renderer below. Typed on
// just the session-reader so BOTH the command ctx and the tool ctx (both carry sessionManager)
// can build context the same way.
function serializeSession(ctx: { sessionManager: SessionManager }): string {
  let entries: SessionEntry[];
  try {
    entries = ctx.sessionManager.buildContextEntries();
  } catch {
    return "";
  }
  return serializeEntries(entries);
}

// The pure core of /consult's context-building: render the recent session as a transcript
// the delegate can review. Exported so the rendering rules (which roles, the recursion skip,
// the tail-cap) are pinned by tests independent of the live session manager.
export function serializeEntries(entries: SessionEntry[]): string {
  const recent = entries.slice(-40);
  const blocks: string[] = [];
  for (const e of recent) {
    const role = e.message?.role;
    if (role !== "user" && role !== "assistant") continue;
    const text = extractText(e.message?.content);
    if (!text) continue;
    if (text.startsWith("[/consult ") || text.startsWith("[/fresh ")) continue;
    blocks.push(`### ${role}\n${text}`);
  }

  if (blocks.length === 0) return "";
  let joined = blocks.join("\n\n");
  if (joined.length > MAX_TRANSCRIPT_CHARS) {
    // Keep the most recent tail — the arc's end matters more for a consult than its start.
    joined = joined.slice(-MAX_TRANSCRIPT_CHARS);
  }
  return (
    "You are being consulted mid-session by another agent that hit a question it wants a " +
    "second opinion on. Here is the recent transcript of that session for context:\n\n" +
    joined +
    "\n\n---\n\nNow answer the consulting agent's question below as a specialist."
  );
}

// Pull the text out of a message's content (string or array of {type:"text",text} blocks).
export function extractText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  const parts: string[] = [];
  for (const block of content) {
    if (
      block &&
      typeof block === "object" &&
      (block as { type?: string }).type === "text" &&
      typeof (block as { text?: string }).text === "string"
    ) {
      parts.push((block as { text: string }).text);
    }
  }
  return parts.join("\n").trim();
}

// Auto-vision: pi's read tool emits "Read image file [image/png]\n[Current model does not
// support images. The image will be omitted from this request.]" when a text-only model
// reads an image. The tool_result middleware below catches that marker, sends the image to
// a multimodal model as a single vision API call, and swaps the omission text for the
// description — the model never learns a new tool, pasting just works.

// Two shapes: TARGETED when we can read the user's framing, GENERIC when the screenshot
// was pasted with no words. Kept here (not inlined) so wording is pinned by tests.
const VISION_PROMPT_GENERIC =
  "Describe this screenshot precisely for another AI agent that cannot see it. " +
  "Cover: overall layout and structure, ALL visible text (verbatim where readable), " +
  "UI elements and their state, colors, and anything notable or unusual. " +
  "Be specific and complete — the reader will reason about the screen from your words alone.";

// Build the vision prompt targeted at what the operator actually asked. The framing is the
// user's message text that accompanied the paste (image-path tokens stripped). Null when
// the screenshot was pasted alone with no words → the generic prompt. Pure + exported so
// the targeting logic is pinned independent of the live session.
export function buildVisionPrompt(framing: string | null): string {
  if (!framing || !framing.trim()) return VISION_PROMPT_GENERIC;
  return (
    "The user pasted this screenshot in the context of the following message:\n\n" +
    '"""\n' + framing.trim() + '\n"""\n\n' +
    "Describe what's in the image. Focus on what's relevant to the user's message — " +
    "the parts that help answer their question or address what they raised — but still " +
    "cover the full screen (layout, ALL visible text verbatim where readable, UI elements " +
    "and their state, colors, anything notable) so nothing load-bearing is missed. " +
    "Be specific and complete; the reader will reason about the screen from your words alone."
  );
}

// Pull the operator's framing out of the session: the most recent user message's text, with
// image-path tokens stripped (the vision model is looking AT the image — its own path is
// not useful context). Returns null when there's no user text beyond paths (a bare paste).
// Pure + exported so the extraction rules are pinned by tests.
export function extractUserFraming(entries: SessionEntry[]): string | null {
  for (let i = entries.length - 1; i >= 0; i--) {
    const e = entries[i];
    if (e?.message?.role !== "user") continue;
    const text = extractText(e.message?.content);
    if (!text) continue;
    const stripped = stripImagePaths(text);
    return stripped.trim() || null;
  }
  return null;
}

// Remove file-path tokens that look like images (the pasted screenshot's own path, any
// referenced image files). Leaves the operator's actual words.
function stripImagePaths(text: string): string {
  return text
    .split(/\s+/)
    .filter((tok) => !/\.(png|jpe?g|gif|webp|bmp)$/i.test(tok) && !/^pi-clipboard-.*\.(png|jpe?g|gif|webp|bmp)$/i.test(tok))
    .join(" ")
    .trim();
}

// Returns a content patch replacing the omission text with the vision model's description,
// or undefined to leave non-image reads (or a delegate re-entry) untouched.
async function onToolResult(
  event: ToolResultEvent,
  ctx: ExtensionContext,
): Promise<ToolResultPatch | undefined> {
  // Don't re-delegate inside a delegate spawn (runPi sets PI_CONSULT_DELEGATE=1) — a
  // /consult or /fresh subagent's own image reads stay as-is so delegation can't chain.
  if (process.env.PI_CONSULT_DELEGATE) return;
  const hit = isImageOmittedResult(event);
  if (!hit) return;
  const { path: imgPath, mime } = hit;

  // Target the vision prompt at what the operator actually asked: read the latest user
  // message from the session and hand it to the vision model as framing. Bare paste (no
  // words) → the generic describe-everything prompt.
  let framing: string | null = null;
  try {
    framing = extractUserFraming(ctx.sessionManager.buildContextEntries());
  } catch {
    framing = null;
  }
  const prompt = buildVisionPrompt(framing);

  ctx.ui.setStatus("consult", `delegating image to ${DEFAULT_MODEL}…`);
  try {
    const desc = await describeImage(imgPath, mime, prompt, ctx.signal);
    ctx.ui.setStatus("consult", "");
    return {
      content: [
        {
          type: "text",
          text:
            `Read image file ${imgPath} — this model can't see images, so the image was ` +
            `delegated to ${DEFAULT_MODEL} (${mime}) for a textual description:

${desc}`,
        },
      ],
    };
  } catch (err) {
    ctx.ui.setStatus("consult", "");
    // Leave the original omission result in place — a failed delegation must not make vision
    // worse than the status quo. The operator gets a toast and can /fresh manually.
    ctx.ui.notify(
      `image delegation failed: ${err instanceof Error ? err.message : String(err)}`,
      "warning",
    );
    return;
  }
}

// Detect an image-omitted read result and pull out {path, mime}. Pure — pinned by tests.
// Returns null for non-read tools, reads that succeeded, or reads with no resolvable path.
export function isImageOmittedResult(
  event: ToolResultEvent,
): { path: string; mime: string } | null {
  if (event.toolName !== "read") return null;
  const text = extractText(event.content);
  // The exact marker pi's read tool emits when the model can't ingest images.
  if (!text.includes("does not support images")) return null;
  const input = event.input as { path?: string } | null | undefined;
  const imgPath = input?.path;
  if (!imgPath) return null;
  return { path: imgPath, mime: inferMime(text, imgPath) };
}

// Resolve the image's MIME type: prefer the `[image/png]` marker in the read tool's text,
// else infer from the file extension. Falls back to image/png (the clipboard paste format).
export function inferMime(omitText: string, imgPath: string): string {
  const fromMarker = /\[image\/([a-z]+)\]/i.exec(omitText);
  if (fromMarker?.[1]) return `image/${fromMarker[1].toLowerCase()}`;
  const ext = imgPath.toLowerCase().split(".").pop() ?? "";
  switch (ext) {
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

// A direct vision chat-completions call — no pi spawn needed for a pure image description.
// minimax-m3 is a reasoning model, so `content` can come back empty when thinking eats the
// budget; fall back to the `reasoning` field in that case.
async function describeImage(
  absPath: string,
  mime: string,
  prompt: string,
  signal: AbortSignal | undefined,
): Promise<string> {
  const bytes = await fs.promises.readFile(absPath);
  const b64 = bytes.toString("base64");
  const key = process.env.OLLAMA_API_KEY;
  if (!key) throw new Error("OLLAMA_API_KEY not set — can't delegate image to minimax-m3");

  const res = await fetch("https://ollama.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    signal,
    body: JSON.stringify({
      model: DEFAULT_MODEL,
      max_tokens: 1024,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: { url: `data:${mime};base64,${b64}` } },
          ],
        },
      ],
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`${DEFAULT_MODEL} HTTP ${res.status}: ${body.slice(0, 300)}`);
  }
  const json = (await res.json()) as {
    choices?: Array<{ message?: { content?: string; reasoning?: string } }>;
  };
  const msg = json.choices?.[0]?.message;
  const content = msg?.content?.trim();
  const reasoning = msg?.reasoning?.trim();
  const out = content || reasoning || "";
  if (!out) throw new Error(`${DEFAULT_MODEL} returned no description (content and reasoning both empty)`);
  return out;
}

// ── consult streaming: reduce pi's `--mode json` NDJSON event stream ─────────────────────
// `pi --mode json` emits one JSON event per line as the delegate runs. We fold that stream
// into a small state: the CURRENT assistant message's streamed text (for a live, in-progress
// tool-result update), the last COMPLETED assistant message's text (the authoritative final
// answer — matching `-p`'s "last assistant message" semantics), a cumulative thinking-char
// count (a liveness signal during a long reasoning pause, before any answer token), the phase,
// and any error. Pure + exported so the event semantics are pinned by tests, independent of
// the spawn/stream plumbing below.

export type ConsultPhase = "thinking" | "answering";

export interface ConsultStreamState {
  visible: string; // current assistant message's streamed text (resets each new message)
  finalText: string; // last COMPLETED assistant message's text — what runPi returns
  thinkingChars: number; // reasoning tokens seen so far — a "still alive" signal
  phase: ConsultPhase;
  error: string | null; // set when an assistant message ends in error/aborted
}

export function initConsultStream(): ConsultStreamState {
  return { visible: "", finalText: "", thinkingChars: 0, phase: "thinking", error: null };
}

// Fold one parsed event into the stream state, returning the next state (never mutates).
// Unknown or irrelevant events (and non-objects) pass through unchanged.
export function reduceConsultEvent(state: ConsultStreamState, event: unknown): ConsultStreamState {
  if (!event || typeof event !== "object") return state;
  const ev = event as Record<string, unknown>;

  // A fresh assistant message begins: reset the visible buffer so the live view shows THIS
  // message streaming (not a pile-up across tool-call turns), and reset the phase to thinking.
  if (ev.type === "message_start") {
    const role = (ev.message as { role?: string } | undefined)?.role;
    return role === "assistant" ? { ...state, visible: "", phase: "thinking" } : state;
  }

  if (ev.type === "message_update") {
    const ame = ev.assistantMessageEvent as { type?: string; delta?: unknown } | undefined;
    if (!ame) return state;
    if (ame.type === "text_start") return { ...state, phase: "answering" };
    if (ame.type === "text_delta" && typeof ame.delta === "string") {
      return { ...state, phase: "answering", visible: state.visible + ame.delta };
    }
    if (ame.type === "thinking_delta" && typeof ame.delta === "string") {
      return { ...state, thinkingChars: state.thinkingChars + ame.delta.length };
    }
    return state;
  }

  // An assistant message completed: its text blocks are the authoritative answer (last one
  // wins — the peer may narrate + call tools before its final turn). Capture an error stop too.
  if (ev.type === "message_end") {
    const msg = ev.message as
      | { role?: string; content?: unknown; stopReason?: string; errorMessage?: string }
      | undefined;
    if (msg?.role !== "assistant") return state;
    const text = extractText(msg.content);
    const error =
      msg.stopReason === "error" || msg.stopReason === "aborted"
        ? msg.errorMessage || `delegate ${msg.stopReason}`
        : state.error;
    return { ...state, finalText: text || state.finalText, error };
  }

  return state;
}

// The answer runPi returns: the last completed assistant message if we saw one, else the live
// buffer — a delegate killed mid-stream still yields whatever it had produced.
export function consultResult(state: ConsultStreamState): string {
  return state.finalText || state.visible;
}

// A one-line status string for the delegate's progress: elapsed seconds plus what it's doing.
// During the reasoning pause (before any answer text) it reads "thinking… Ns" so a long,
// silent wait still shows life; once tokens flow it reads "streaming… Ns · N chars". `label`
// is the caller's prefix (e.g. "consult glm-5.2" or "/consult glm-5.2"). Pure + exported.
export function consultHeartbeat(label: string, state: ConsultStreamState, startedAtMs: number): string {
  const secs = Math.max(0, Math.round((Date.now() - startedAtMs) / 1000));
  if (state.visible) return `${label}: streaming… ${secs}s · ${state.visible.length} chars`;
  return `${label}: thinking… ${secs}s`;
}

// Spawn a transient `pi --mode json --no-session --model <id>` one-shot and stream its output.
// Re-enters the running pi binary — robust whether pi is a bun bundle or on PATH. `onProgress`
// (optional) is called as the peer's answer streams in, throttled; it returns the final text.
function runPi(
  model: string,
  task: string,
  signal?: AbortSignal,
  onProgress?: (state: ConsultStreamState) => void,
): Promise<string> {
  return new Promise((resolve, reject) => {
    const inv = getPiInvocation([
      "--provider",
      PROVIDER,
      "--model",
      model,
      "--no-session",
      "--mode",
      "json",
      "--tools",
      DELEGATE_TOOLS,
      task,
    ]);
    const proc = spawn(inv.command, inv.args, {
      stdio: ["ignore", "pipe", "pipe"],
      // Marks the subagent so our own tool_result hook skips it — prevents delegation
      // from chaining (a delegate reading an image would otherwise re-delegate too).
      env: { ...process.env, PI_CONSULT_DELEGATE: "1" },
    });
    // The consult TOOL passes the model's turn-abort signal so Esc kills the delegate
    // mid-flight; the slash commands pass none. Listener is removed on settle so a completed
    // delegate leaks nothing.
    const onAbort = () => proc.kill();
    if (signal) {
      if (signal.aborted) {
        proc.kill();
        reject(new Error("consult cancelled"));
        return;
      }
      signal.addEventListener("abort", onAbort, { once: true });
    }
    const cleanup = () => signal?.removeEventListener("abort", onAbort);

    let state = initConsultStream();
    let buf = "";
    let stderr = "";
    let lastEmit = 0;
    // text_delta fires dozens of times a second; throttle the (render-triggering) progress
    // callback to ~12Hz, and always flush a final one on close.
    const emit = (force: boolean) => {
      if (!onProgress) return;
      const now = Date.now();
      if (!force && now - lastEmit < 80) return;
      lastEmit = now;
      onProgress(state);
    };

    proc.stdout?.on("data", (d: Buffer) => {
      // pi emits newline-delimited JSON; buffer partial lines across chunk boundaries.
      buf += d.toString();
      let nl: number;
      while ((nl = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, nl).trim();
        buf = buf.slice(nl + 1);
        if (!line) continue;
        let event: unknown;
        try {
          event = JSON.parse(line);
        } catch {
          continue; // ignore any non-JSON noise on stdout
        }
        state = reduceConsultEvent(state, event);
      }
      emit(false);
    });
    proc.stderr?.on("data", (d: Buffer) => {
      stderr += d.toString();
    });
    proc.on("error", (err) => {
      cleanup();
      reject(err);
    });
    proc.on("close", (code) => {
      cleanup();
      emit(true);
      // A completed assistant message is the answer, even if pi exited non-zero afterward.
      if (state.finalText) {
        resolve(state.finalText);
        return;
      }
      if (state.error) {
        reject(new Error(state.error));
        return;
      }
      // No completed message but we streamed something (e.g. killed mid-answer) — better than
      // nothing. Otherwise it's a real failure: surface the exit code + stderr tail.
      if (state.visible) {
        resolve(state.visible);
        return;
      }
      const tail = stderr.trim().slice(0, 500);
      reject(new Error(`pi exited ${code ?? "?"}${tail ? `: ${tail}` : ""}`));
    });
  });
}

// Re-enter the running pi. If we were loaded as a path extension from a real script file,
// re-run that script with the same runtime; otherwise fall back to `pi` on PATH.
function getPiInvocation(args: string[]): { command: string; args: string[] } {
  const currentScript = process.argv[1];
  const isBunVirtual = currentScript?.startsWith("/$bunfs/root/");
  if (currentScript && !isBunVirtual && fs.existsSync(currentScript)) {
    return { command: process.execPath, args: [currentScript, ...args] };
  }
  const execName = path.basename(process.execPath).toLowerCase();
  if (/^(node|bun)(\.exe)?$/.test(execName)) {
    return { command: "pi", args };
  }
  return { command: process.execPath, args };
}