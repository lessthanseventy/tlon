// The claude-code adapter's mod: what makes a Claude Code session a citizen of its tlon thread,
// from inside the session. Claude Code runs it in its own process, so every call goes over the
// session's own `tlon` MCP connection (launch.sh's --mcp-config, headersHelper-authed) — no bun per
// hook, no second client, and the calls leave in the order the events fire.
//
// The server is the only state: the module's variables are per-session bookkeeping (what was last
// briefed, how far capture has read), lost on a reload, never a queue of unsent work. A slow or
// down server never holds a prompt, a tool, a turn or the session's start.

import { doingOf, summaryOf } from "./lib/doing.ts";
import { renderBrief, type Dossier } from "./lib/brief.ts";
import { detectCorrection } from "./lib/recall.ts";
import {
  buildExtractionPrompt,
  DEFAULT_CAPTURE_MODEL,
  deltaSince,
  parseExtraction,
  redactSecrets,
  serializeDelta,
  type Entry,
} from "./lib/capture.ts";
import { DEFAULT_MODEL, isImagePath, mimeOf, parseArgs, parseToolArgs, serializeTranscript, VISION_MODELS, visionPrompt } from "./lib/consult.ts";

// Below this much new transcript a turn's capture waits for the next turn instead of paying for
// an extraction call; a compaction flushes whatever is there.
const MIN_DELTA_CHARS = 2_000;
const THREAD_PANE = "tlon-thread";
// How often the session looks for wakes the server queued for it (Server.Wake). Taking them is
// not activity on the server's side, so polling never keeps an idle session warm.
const WAKE_POLL_MS = 3_000;

type Message = { author: string; body: string; at?: string };

let thread = "";
let author = "";
let cwd = "";
let dossier: Dossier | null = null;
let briefed = "";
let lastCorrection = "";
let captured = 0;
let capturing = false;
let messages: Message[] = [];
let draining = false;

function declare($, tool: string, args: Record<string, unknown> = {}) {
  $.mcp.call("tlon", tool, args).catch(() => {});
}

async function call($, tool: string, args: Record<string, unknown> = {}): Promise<unknown> {
  const r = await $.mcp.call("tlon", tool, args);
  const text = r.content.find((b) => b.type === "text")?.text ?? "";
  if (r.isError) throw new Error(text || `${tool} failed`);
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

async function refresh($) {
  try {
    dossier = (await call($, "get_dossier")) as Dossier;
  } catch {
    return;
  }
  $.ui.invalidate("ui.render");
}

// A wake (a teammate's message, an opening assignment) arrives as if typed: Claude Code holds it
// until the session is idle, so it never lands on a booting input or a half-written prompt.
async function drainWakes($) {
  if (draining) return;
  draining = true;
  try {
    const wakes = await call($, "take_wakes");
    if (Array.isArray(wakes)) for (const text of wakes) void $.prompt.submit({ text: String(text), asUser: true });
  } catch {
    // a missed poll is taken by the next one; a wake left too long is the server's to report
  } finally {
    draining = false;
  }
}

async function loadMessages($) {
  try {
    const got = await call($, "get_messages", { limit: 40 });
    if (Array.isArray(got)) messages = got as Message[];
  } catch {
    return;
  }
  $.ui.invalidate("ui.render");
}

async function ollamaKey($): Promise<string> {
  const key = await $.env.get("OLLAMA_API_KEY");
  if (key) return key;
  const runtime = (await $.env.get("XDG_RUNTIME_DIR")) ?? "";
  try {
    return runtime ? (await $.fs.read(`${runtime}/agenix/ollama-api-key`)).trim() : "";
  } catch {
    return "";
  }
}

// Side jobs (extraction, image descriptions) run on the ollama bucket, never the session's own model.
async function complete($, model: string, content: unknown): Promise<string> {
  const key = await ollamaKey($);
  if (!key) throw new Error("no OLLAMA_API_KEY");
  const res = await $.http.fetch("https://ollama.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model, max_tokens: 1024, messages: [{ role: "user", content }] }),
  });
  if (!res.ok) throw new Error(`${model} HTTP ${res.status}`);
  const msg = JSON.parse(res.text).choices?.[0]?.message;
  return msg?.content?.trim() || msg?.reasoning?.trim() || "";
}

// Claude Code's own WebSearch runs on Anthropic's side, so a session on the ollama gateway searches
// through ollama's.
async function webSearch($, query: string, max: number): Promise<string> {
  const key = await ollamaKey($);
  if (!key) return "web_search: no OLLAMA_API_KEY";
  const res = await $.http.fetch("https://ollama.com/api/web_search", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ query, max_results: max }),
  });
  if (!res.ok) return `web_search: HTTP ${res.status}`;
  const results: { title?: string; url?: string; content?: string }[] = JSON.parse(res.text).results ?? [];
  if (!results.length) return `no results for ${JSON.stringify(query)}`;
  return results.map((r) => `## ${r.title ?? r.url}\n${r.url}\n${(r.content ?? "").slice(0, 1_500)}`).join("\n\n");
}

// A consult is a one-shot Claude Code on the ollama gateway: no session saved, no tlon identity,
// and read-only tools — a bash of its own would run outside the asking session's sandbox.
async function delegate($, model: string, task: string): Promise<string> {
  const key = await ollamaKey($);
  if (!key) throw new Error("no OLLAMA_API_KEY for the delegate");
  const tools = "Read,Grep,Glob";
  const r = await $.process.run(
    ["claude", "-p", task, "--model", model, "--tools", tools, "--allowedTools", tools, "--permission-mode", "dontAsk", "--no-session-persistence"],
    {
      timeoutMs: 600_000,
      env: { ANTHROPIC_BASE_URL: "https://ollama.com", ANTHROPIC_AUTH_TOKEN: key, ANTHROPIC_API_KEY: "", ANTHROPIC_DEFAULT_HAIKU_MODEL: "deepseek-v4.1-flash", TLON_THREAD: "", TLON_AUTHOR: "" },
    },
  );
  if (r.exitCode !== 0) throw new Error(r.stderr.trim().slice(0, 300) || `${model} exited ${r.exitCode}`);
  return r.stdout.trim();
}

async function consultTask($, prompt: string, withTranscript: boolean): Promise<string> {
  if (!withTranscript) return prompt;
  const context = serializeTranscript(await $.session.messages());
  return context ? `${context}\n\n---\n\n${prompt}` : prompt;
}

async function runConsult($, verb: "consult" | "fresh", args: string) {
  const { model, prompt } = parseArgs(args);
  if (!prompt) return { text: `usage: /${verb} [model] <prompt>  (default model: ${DEFAULT_MODEL})` };
  $.ui.toast(`asking ${model}…`, { timeoutMs: 8_000 });
  try {
    const answer = await delegate($, model, await consultTask($, prompt, verb === "consult"));
    return { text: `[/${verb} ${model}] ${prompt}\n\n${answer}` };
  } catch (err) {
    return { text: `${model} could not answer: ${err instanceof Error ? err.message : String(err)}` };
  }
}

// A model that cannot see images gets its image reads described by one that can.
async function describeImage($, path: string): Promise<string | null> {
  if (!(await $.env.get("ANTHROPIC_BASE_URL")) || VISION_MODELS.includes(await $.session.model())) return null;
  const b64 = await $.process.run(["base64", "-w0", path]);
  if (b64.exitCode !== 0) return null;
  const prompt = visionPrompt(await $.session.messages());
  const description = await complete($, DEFAULT_MODEL, [
    { type: "text", text: prompt },
    { type: "image_url", image_url: { url: `data:${mimeOf(path)};base64,${b64.stdout.trim()}` } },
  ]);
  return `Read image file ${path} — this model can't see images, so ${DEFAULT_MODEL} described it:\n\n${description}`;
}

// Bank what the conversation learned since the last capture, as `derived` facts. The brief rides
// each prompt as context; it is cut out here so the record is never re-banked from its own view.
async function capture($, floor: number) {
  if (capturing) return;
  capturing = true;
  try {
    const all: Entry[] = (await $.session.messages()).map((m) => ({
      message: { role: m.role, content: m.text.replace(/<tlon-brief>[\s\S]*?<\/tlon-brief>/g, "") },
    }));
    const { slice, nextWatermark } = deltaSince(all, captured);
    const delta = redactSecrets(serializeDelta(slice));
    if (delta.length < floor) return;
    const { facts, questions } = parseExtraction(await complete($, DEFAULT_CAPTURE_MODEL, buildExtractionPrompt(delta)));
    captured = nextWatermark;
    for (const f of facts) declare($, "bank_fact", f.intent ? { text: f.text, kind: f.kind, intent: f.intent } : { text: f.text, kind: f.kind });
    for (const q of questions) declare($, "raise_question", { text: q });
    if (facts.length || questions.length) $.ui.toast(`banked ${facts.length} fact(s), ${questions.length} question(s)`);
  } catch {
    return;
  } finally {
    capturing = false;
  }
}

function percent(n: number | undefined): string {
  return n === undefined ? "?" : `${Math.round(n)}%`;
}

export function register(on) {
  on("session.start", async ($, e, next) => {
    thread = (await $.env.get("TLON_THREAD")) ?? "";
    author = (await $.env.get("TLON_AUTHOR")) ?? "";
    if (!thread || !author) return next(e);
    cwd = e.cwd;
    const pane = await $.env.get("TMUX_PANE");
    declare($, "register", pane ? { pane_ref: pane } : {});
    $.clock.every(WAKE_POLL_MS, () => drainWakes($));
    void refresh($);
    try {
      await $.tool.register({
        name: "consult",
        description:
          "Ask a different (or stronger) ollama model for a second opinion and get its answer back as this tool's result. " +
          "`context: transcript` (default) shows it your recent session; `context: none` is a clean one-shot. The peer can read files, not run them.",
        inputSchema: {
          type: "object",
          properties: { prompt: { type: "string" }, model: { type: "string" }, context: { type: "string", enum: ["transcript", "none"] } },
          required: ["prompt"],
        },
      });
      if (await $.env.get("ANTHROPIC_BASE_URL")) {
        await $.tool.register({
          name: "web_search",
          description: "Search the web (through ollama's search; this session's own WebSearch is unavailable). Returns each result's title, URL and an excerpt.",
          inputSchema: {
            type: "object",
            properties: { query: { type: "string" }, max_results: { type: "number", description: "1-10, default 5" } },
            required: ["query"],
          },
          isDeferred: false,
        });
      }
      await $.command.register({ name: "thread", description: "Open this tlon thread's conversation beside the session", immediate: true });
      await $.command.register({ name: "consult", description: "Ask another model, with this session as context", argumentHint: "[model] <prompt>" });
      await $.command.register({ name: "fresh", description: "Ask another model, with no session context", argumentHint: "[model] <prompt>" });
    } catch {
      // a name already taken leaves the session without that command, nothing worse
    }
    return next(e);
  });

  // A /clear, /resume or /branch is a new conversation: brief it and capture it from the start.
  on("session.end", async ($, e, next) => {
    if (thread) declare($, "presence_idle");
    briefed = "";
    captured = 0;
    return next(e);
  });

  on("prompt.submit", async ($, e, next) => {
    if (!thread) return next(e);
    const habit = detectCorrection(e.text);
    if (habit && habit !== lastCorrection) {
      lastCorrection = habit;
      declare($, "propose_habit", { text: habit, rationale: "auto-detected from a correction you made" });
    }
    await refresh($);
    const key = dossier ? JSON.stringify(dossier) : "";
    if (!dossier || key === briefed) return next(e);
    briefed = key;
    const brief = renderBrief(dossier, new Date(), await $.session.model());
    return next({ ...e, context: [...(e.context ?? []), `<tlon-brief>\n${brief}\n</tlon-brief>`] });
  });

  on("turn.start", async ($, e, next) => {
    if (thread) declare($, "presence_thinking");
    return next(e);
  });

  // `$.mcp.call` raises tool.call too: the mod's own calls are not the session's work.
  on("tool.call", async ($, e, next) => {
    if (next.origin.plugin === $.plugin.name) return next(e);
    if (thread) {
      const what = doingOf(e.tool, e);
      declare($, "presence_doing", { ...(what ? { what } : {}), summary: summaryOf(e.tool, e, cwd) });
    }
    if (e.tool === `mcp__${$.plugin.name}__consult`) {
      const args = parseToolArgs(e);
      if (!args.ok) return { result: args.error };
      try {
        return { result: await delegate($, args.model, await consultTask($, args.prompt, args.context === "transcript")) };
      } catch (err) {
        return { result: `${args.model} could not answer: ${err instanceof Error ? err.message : String(err)}` };
      }
    }
    if (e.tool === `mcp__${$.plugin.name}__web_search`) {
      const max = Math.min(10, Math.max(1, Number(e.max_results) || 5));
      return { result: await webSearch($, String(e.query ?? ""), max) };
    }
    if (e.tool === "Read" && isImagePath(e.file_path ?? "")) {
      try {
        const described = await describeImage($, e.file_path);
        if (described) return { result: described };
      } catch {
        // an undescribed image is read as the model would have read it
      }
    }
    return next(e);
  });

  // A subagent's turn ends inside the session's own; only the session's turn ending is idle.
  on("turn.complete", async ($, e, next) => {
    if (thread && !e.agentId) {
      declare($, "presence_idle");
      void capture($, MIN_DELTA_CHARS);
      void refresh($);
    }
    return next(e);
  });

  on("session.compact", async ($, e, next) => {
    if (thread) await capture($, 1);
    return next(e);
  });

  on("command.run", { command: "consult" }, async ($, e) => runConsult($, "consult", e.args));
  on("command.run", { command: "fresh" }, async ($, e) => runConsult($, "fresh", e.args));

  on("command.run", { command: "thread" }, async ($) => {
    await loadMessages($);
    await $.ui.open({ id: THREAD_PANE, title: `#${thread}`, focus: true, closeOnEscape: true });
    return {};
  });

  on("ui.render", { component: "AbovePrompt" }, async ($, e, next) => {
    if (!thread) return next(e);
    const { Box, Text } = $.ui.resolve(e);
    const usage = await $.session.usage();
    const limit = (kind: string) => usage.rateLimits.find((r) => r.kind === kind);
    const fiveHour = limit("five_hour");
    const week = limit("seven_day");
    const meters = [`ctx ${percent(usage.context.percent)}`];
    if (fiveHour) meters.push(`5h ${percent(fiveHour.percentUsed)}`);
    if (week) meters.push(`wk ${percent(week.percentUsed)}`);
    const d = dossier;
    const todos = d ? d.todos.shown.length + d.todos.more : 0;
    const blockers = d ? d.blockers.shown.length + d.blockers.more : 0;
    const parts = [`#${thread} ${d?.goal ?? ""}`.trim()];
    if (todos) parts.push(`todos ${todos}${d?.next ? ` → ${d.next.text}` : ""}`);
    if (blockers) parts.push(`blockers ${blockers}`);
    return Box({
      flexDirection: "column",
      children: [
        Box({
          flexDirection: "row",
          justifyContent: "space-between",
          children: [
            Text({ wrap: "truncate-end", children: [parts.join(" · ")] }),
            Text({ dimColor: true, children: [`${author} · ${meters.join(" · ")}`] }),
          ],
        }),
        await next(e),
      ],
    });
  });

  on("ui.render", { component: "Pane" }, async ($, e, next) => {
    if (e.requestId !== THREAD_PANE) return next(e);
    const { Box, Text, Markdown } = $.ui.resolve(e);
    if (!messages.length) return Text({ dimColor: true, children: ["no messages on this thread yet"] });
    return Box({
      flexDirection: "column",
      children: messages.map((m, i) =>
        Box({
          key: `m${i}`,
          flexDirection: "column",
          children: [Text({ bold: true, children: [m.author] }), Markdown({ text: m.body })],
        }),
      ),
    });
  });
}
