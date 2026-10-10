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

// Below this much new transcript a turn's capture waits for the next turn instead of paying for
// an extraction call; a compaction flushes whatever is there.
const MIN_DELTA_CHARS = 2_000;
const THREAD_PANE = "tlon-thread";
const REFRESH_MS = 30_000;

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

async function loadMessages($) {
  try {
    const got = await call($, "get_messages", { limit: 40 });
    if (Array.isArray(got)) messages = got as Message[];
  } catch {
    return;
  }
  $.ui.invalidate("ui.render");
}

// The ollama bucket, never the session's own model: extraction is a cheap side job.
async function complete($, prompt: string): Promise<string> {
  const key = await $.env.get("OLLAMA_API_KEY");
  if (!key) return "";
  const res = await $.http.fetch("https://ollama.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: DEFAULT_CAPTURE_MODEL, max_tokens: 1024, messages: [{ role: "user", content: prompt }] }),
  });
  if (!res.ok) throw new Error(`capture HTTP ${res.status}`);
  const msg = JSON.parse(res.text).choices?.[0]?.message;
  return msg?.content?.trim() || msg?.reasoning?.trim() || "";
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
    const { facts, questions } = parseExtraction(await complete($, buildExtractionPrompt(delta)));
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
    $.clock.every(REFRESH_MS, () => refresh($));
    void refresh($);
    try {
      await $.command.register({ name: "thread", description: "Open this tlon thread's conversation beside the session", immediate: true });
    } catch {
      // a name already taken leaves the session without /thread, nothing worse
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
    if (thread && next.origin.plugin !== $.plugin.name) {
      const what = doingOf(e.tool, e);
      declare($, "presence_doing", { ...(what ? { what } : {}), summary: summaryOf(e.tool, e, cwd) });
    }
    return next(e);
  });

  // A subagent's turn ends inside the session's own; only the session's turn ending is idle.
  on("turn.complete", async ($, e, next) => {
    if (thread && !e.agentId) {
      declare($, "presence_idle");
      void capture($, MIN_DELTA_CHARS);
      $.ui.invalidate("ui.render");
    }
    return next(e);
  });

  on("session.compact", async ($, e, next) => {
    if (thread) await capture($, 1);
    return next(e);
  });

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
