import { describe, expect, test } from "bun:test";
import {
  parseArgs,
  parseToolArgs,
  extractText,
  serializeEntries,
  isImageOmittedResult,
  inferMime,
  buildVisionPrompt,
  extractUserFraming,
  initConsultStream,
  reduceConsultEvent,
  consultResult,
} from "./extension.ts";
import type { ConsultStreamState } from "./extension.ts";
import type { SessionEntry, ToolResultEvent } from "./pi.ts";

// ── parseArgs: [model] <prompt> ──────────────────────────────────────────────────────────

describe("parseArgs — [model] <prompt>", () => {
  test("an explicit known model id is peeled off the front", () => {
    expect(parseArgs("deepseek-v4-pro am I on track?")).toEqual({
      model: "deepseek-v4-pro",
      prompt: "am I on track?",
    });
  });

  test("no model arg → default minimax-m3, whole string is the prompt", () => {
    expect(parseArgs("am I on track?")).toEqual({
      model: "minimax-m3",
      prompt: "am I on track?",
    });
  });

  test("empty → default model, empty prompt (the command surfaces usage)", () => {
    expect(parseArgs("")).toEqual({ model: "minimax-m3", prompt: "" });
    expect(parseArgs("   ")).toEqual({ model: "minimax-m3", prompt: "" });
  });

  test("a first token that isn't a known model is kept as part of the prompt", () => {
    expect(parseArgs("review the plan")).toEqual({
      model: "minimax-m3",
      prompt: "review the plan",
    });
  });
});

// ── extractText: string | content-block array ───────────────────────────────────────────

describe("extractText", () => {
  test("a plain string passes through", () => {
    expect(extractText("hello")).toBe("hello");
  });

  test("text blocks are joined, non-text blocks dropped", () => {
    expect(
      extractText([
        { type: "text", text: "line one" },
        { type: "image", data: "..." },
        { type: "text", text: "line two" },
      ]),
    ).toBe("line one\nline two");
  });

  test("non-array, non-string content → empty", () => {
    expect(extractText(undefined)).toBe("");
    expect(extractText({})).toBe("");
    expect(extractText(42)).toBe("");
  });
});

// ── serializeEntries: the /consult transcript renderer ───────────────────────────────────

describe("serializeEntries — the /consult context builder", () => {
  const entry = (role: string, text: string): SessionEntry => ({
    type: "message",
    message: { role, content: [{ type: "text", text }] },
  });

  test("user + assistant text turns become a framed transcript", () => {
    const out = serializeEntries([
      entry("user", "let's fix the bug"),
      entry("assistant", "looking at cockpit.ex"),
    ]);
    expect(out).toContain("You are being consulted mid-session");
    expect(out).toContain("### user\nlet's fix the bug");
    expect(out).toContain("### assistant\nlooking at cockpit.ex");
  });

  test("tool results and system messages are dropped (noise for a review)", () => {
    const out = serializeEntries([
      { type: "message", message: { role: "toolResult", content: [{ type: "text", text: "big blob" }] } },
      entry("user", "the real prompt"),
    ]);
    expect(out).toContain("### user\nthe real prompt");
    expect(out).not.toContain("big blob");
  });

  test("prior [/consult] and [/fresh] injections are skipped (no recursion in the transcript)", () => {
    const out = serializeEntries([
      entry("user", "[/consult minimax-m3] old question\n\nold answer"),
      entry("user", "[/fresh glm-5.1] another\n\nanother answer"),
      entry("assistant", "the real turn"),
    ]);
    expect(out).not.toContain("[/consult minimax-m3]");
    expect(out).not.toContain("[/fresh glm-5.1]");
    expect(out).toContain("### assistant\nthe real turn");
  });

  test("no usable text turns → empty string (no framing preamble)", () => {
    expect(serializeEntries([])).toBe("");
    expect(
      serializeEntries([{ type: "message", message: { role: "toolResult", content: [] } }]),
    ).toBe("");
  });

  test("only the most recent 40 entries are considered", () => {
    const entries: SessionEntry[] = [];
    for (let i = 0; i < 50; i++) entries.push(entry("user", `turn-${i}`));
    const out = serializeEntries(entries);
    expect(out).not.toContain("turn-9\n");
    expect(out).toContain("turn-49");
  });
});

// ── isImageOmittedResult: the auto-vision detector ──────────────────────────────────────

describe("isImageOmittedResult — detect a read that dropped an image", () => {
  // The exact shape pi's read tool emits for an image when the model can't ingest it.
  const omitted = (path: string, mime = "image/png"): ToolResultEvent => ({
    toolName: "read",
    toolCallId: "call_1",
    input: { path },
    content: [
      {
        type: "text",
        text:
          `Read image file [${mime}]\n` +
          "[Current model does not support images. The image will be omitted from this request.]",
      },
      { type: "image", data: "" },
    ],
  });

  test("a read that omitted an image → {path, mime}", () => {
    expect(isImageOmittedResult(omitted("/tmp/pi-clipboard-abc.png"))).toEqual({
      path: "/tmp/pi-clipboard-abc.png",
      mime: "image/png",
    });
  });

  test("the mime is read from the [image/...] marker", () => {
    expect(isImageOmittedResult(omitted("/x.jpg", "image/jpeg"))).toEqual({
      path: "/x.jpg",
      mime: "image/jpeg",
    });
  });

  test("a non-read tool is never an image-omitted result", () => {
    expect(
      isImageOmittedResult({ ...omitted("/x.png"), toolName: "bash" }),
    ).toBeNull();
  });

  test("a read that succeeded (no omission marker) is left alone", () => {
    expect(
      isImageOmittedResult({
        toolName: "read",
        toolCallId: "c",
        input: { path: "/src/foo.ts" },
        content: [{ type: "text", text: "export function foo() {}" }],
      }),
    ).toBeNull();
  });

  test("a read with no resolvable path is left alone (can't delegate without a file)", () => {
    expect(
      isImageOmittedResult({
        toolName: "read",
        toolCallId: "c",
        input: {},
        content: [{ type: "text", text: "[Current model does not support images.]" }],
      }),
    ).toBeNull();
  });
});

// ── inferMime ───────────────────────────────────────────────────────────────────────────

describe("inferMime", () => {
  test("the [image/...] marker wins over the extension", () => {
    expect(inferMime("Read image file [image/gif]", "/x.png")).toBe("image/gif");
  });

  test("fall back to the extension when there's no marker", () => {
    expect(inferMime("no marker here", "/tmp/shot.jpg")).toBe("image/jpeg");
    expect(inferMime("no marker", "/tmp/shot.webp")).toBe("image/webp");
    expect(inferMime("no marker", "/tmp/shot.bmp")).toBe("image/bmp");
  });

  test("unknown extension → image/png (the clipboard paste default)", () => {
    expect(inferMime("no marker", "/tmp/pi-clipboard-abc")).toBe("image/png");
    expect(inferMime("no marker", "/tmp/xyz.unknown")).toBe("image/png");
  });
});
// ── buildVisionPrompt: targeted vs generic ──────────────────────────────────────────────

describe("buildVisionPrompt — target the vision call at the user's framing", () => {
  test("with framing: embeds the user's message and asks for relevance + full coverage", () => {
    const out = buildVisionPrompt("that tlon space is supposed to be two windows, one pi one claude");
    expect(out).toContain("The user pasted this screenshot in the context of the following message");
    expect(out).toContain("that tlon space is supposed to be two windows");
    expect(out).toContain("Focus on what's relevant to the user's message");
    expect(out).toContain("cover the full screen");
  });

  test("null framing → the generic describe-everything prompt (no message preamble)", () => {
    const out = buildVisionPrompt(null);
    expect(out).not.toContain("The user pasted this screenshot in the context");
    expect(out).toContain("Describe this screenshot precisely");
  });

  test("whitespace-only framing → generic (a bare paste with no words)", () => {
    expect(buildVisionPrompt("   ").includes("Describe this screenshot precisely")).toBe(true);
  });
});

// ── extractUserFraming: latest user message, image paths stripped ───────────────────────

describe("extractUserFraming — the operator's words around the paste", () => {
  const u = (text: string): SessionEntry => ({
    type: "message",
    message: { role: "user", content: [{ type: "text", text }] },
  });
  const a = (text: string): SessionEntry => ({
    type: "message",
    message: { role: "assistant", content: [{ type: "text", text }] },
  });

  test("returns the most recent user message with image-path tokens stripped", () => {
    expect(
      extractUserFraming([
        u("/tmp/pi-clipboard-abc.png that tlon space is supposed to be two windows"),
      ]),
    ).toBe("that tlon space is supposed to be two windows");
  });

  test("a .jpg reference is stripped too, the words around it kept", () => {
    expect(extractUserFraming([u("/tmp/shot.jpg why is this only one window?")])).toBe(
      "why is this only one window?",
    );
  });

  test("skips assistant turns and earlier user turns — the LATEST user message wins", () => {
    expect(
      extractUserFraming([
        u("older question about something else"),
        a("an answer in the middle"),
        u("/tmp/x.png the real current question"),
      ]),
    ).toBe("the real current question");
  });

  test("a bare paste (only a path, no words) → null (auto-vision uses the generic prompt)", () => {
    expect(extractUserFraming([u("/tmp/pi-clipboard-abc.png")])).toBeNull();
    expect(extractUserFraming([u("  /tmp/a.png   /tmp/b.jpg  ")])).toBeNull();
  });

  test("no user entries → null", () => {
    expect(extractUserFraming([])).toBeNull();
    expect(extractUserFraming([a("just an assistant")])).toBeNull();
  });
});

// ── parseToolArgs: the model-invocable `consult` tool's params ────────────────────────────
// Mechanism 2 (tlon-workspace-design §2): the same delegate as /consult, but a TOOL a model
// calls mid-turn. Unlike the slash command (which peels a bare [model] token off a string),
// the tool takes named params — so validation is stricter: an explicit unknown model is an
// error, not a silent downgrade to the default.

describe("parseToolArgs — the consult tool's named params", () => {
  test("prompt only → default model, transcript context", () => {
    expect(parseToolArgs({ prompt: "am I on track?" })).toEqual({
      ok: true,
      model: "minimax-m3",
      context: "transcript",
      prompt: "am I on track?",
    });
  });

  test("an explicit known model is used", () => {
    expect(parseToolArgs({ prompt: "review this", model: "glm-5.2" })).toEqual({
      ok: true,
      model: "glm-5.2",
      context: "transcript",
      prompt: "review this",
    });
  });

  test("context: none is honored (a clean one-shot, the /fresh behavior)", () => {
    expect(parseToolArgs({ prompt: "q", context: "none" })).toEqual({
      ok: true,
      model: "minimax-m3",
      context: "none",
      prompt: "q",
    });
  });

  test("an explicit unknown model is an ERROR (not a silent downgrade)", () => {
    const r = parseToolArgs({ prompt: "q", model: "gpt-9" });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toContain("gpt-9");
  });

  test("a missing/empty prompt is an error", () => {
    expect(parseToolArgs({}).ok).toBe(false);
    expect(parseToolArgs({ prompt: "   " }).ok).toBe(false);
  });

  test("prompt is trimmed", () => {
    const r = parseToolArgs({ prompt: "  spaced  " });
    expect(r.ok && r.prompt).toBe("spaced");
  });

  test("an empty-string model falls back to the default (treated as absent)", () => {
    const r = parseToolArgs({ prompt: "q", model: "" });
    expect(r).toEqual({ ok: true, model: "minimax-m3", context: "transcript", prompt: "q" });
  });
});

// ── reduceConsultEvent: fold pi's `--mode json` NDJSON stream into live state ─────────────
// The delegate now runs `pi --mode json` (not `-p`), which emits one JSON event per line as
// it works, so we can stream the peer's answer instead of buffering it to the end. These
// tests pin the event semantics: which events add visible text, which count as thinking, how
// the final answer is captured, and how a mid-stream error surfaces.

describe("reduceConsultEvent — the streaming event reducer", () => {
  // Replay a sequence of events through the reducer from a fresh state.
  const run = (events: unknown[]): ConsultStreamState =>
    events.reduce<ConsultStreamState>(reduceConsultEvent, initConsultStream());

  const msgStart = (role: string) => ({ type: "message_start", message: { role } });
  const textDelta = (delta: string) => ({
    type: "message_update",
    assistantMessageEvent: { type: "text_delta", contentIndex: 1, delta },
  });
  const thinkingDelta = (delta: string) => ({
    type: "message_update",
    assistantMessageEvent: { type: "thinking_delta", contentIndex: 0, delta },
  });
  const msgEnd = (text: string, extra: Record<string, unknown> = {}) => ({
    type: "message_end",
    message: { role: "assistant", content: [{ type: "text", text }], ...extra },
  });

  test("text_delta events accumulate into the visible stream", () => {
    const s = run([msgStart("assistant"), textDelta("Hello"), textDelta(", world")]);
    expect(s.visible).toBe("Hello, world");
    expect(s.phase).toBe("answering");
  });

  test("thinking_delta counts toward liveness but is not shown as answer text", () => {
    const s = run([msgStart("assistant"), thinkingDelta("hmm let me think")]);
    expect(s.visible).toBe("");
    expect(s.thinkingChars).toBe("hmm let me think".length);
    expect(s.phase).toBe("thinking");
  });

  test("message_end captures the completed answer as finalText", () => {
    const s = run([msgStart("assistant"), textDelta("streamed"), msgEnd("the final answer")]);
    expect(s.finalText).toBe("the final answer");
    expect(consultResult(s)).toBe("the final answer");
  });

  test("a new assistant message resets the visible buffer (tool-call turn → answer turn)", () => {
    // The peer narrates ("let me check"), the message ends, a tool runs, then a fresh
    // assistant message streams the real answer — the live view shows the CURRENT message.
    const s = run([
      msgStart("assistant"),
      textDelta("let me check the file"),
      msgEnd("let me check the file"),
      msgStart("assistant"),
      textDelta("found it: the bug is X"),
    ]);
    expect(s.visible).toBe("found it: the bug is X");
    // finalText is still the last COMPLETED message until the second one ends.
    expect(s.finalText).toBe("let me check the file");
  });

  test("consultResult prefers finalText but falls back to a partial stream (killed mid-answer)", () => {
    const partial = run([msgStart("assistant"), textDelta("half an ans")]);
    expect(partial.finalText).toBe("");
    expect(consultResult(partial)).toBe("half an ans");
  });

  test("an errored/aborted message_end surfaces the error", () => {
    const s = run([
      msgStart("assistant"),
      msgEnd("", { stopReason: "error", errorMessage: "provider 500" }),
    ]);
    expect(s.error).toBe("provider 500");
  });

  test("unknown / irrelevant events pass through unchanged", () => {
    const before = initConsultStream();
    const after = run([{ type: "session", id: "x" }, { type: "turn_start" }, "not-an-object", null]);
    expect(after).toEqual(before);
  });

  test("a user message_start does not reset assistant state", () => {
    const s = run([msgStart("assistant"), textDelta("answer"), msgStart("user")]);
    expect(s.visible).toBe("answer");
  });
});
