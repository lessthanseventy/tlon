// The claude-code adapter's mod: what makes a Claude Code session a citizen of its tlon thread,
// from inside the session. Claude Code runs it in its own process, so every call goes over the
// session's own `tlon` MCP connection (launch.sh's --mcp-config, headersHelper-authed) — no bun per
// hook, no second client, and the calls leave in the order the events fire.
//
// The server is the only state: the module's variables are per-session bookkeeping (what was last
// briefed, how far capture has read, which mentions were shown), lost on a reload, never a queue of
// unsent work. A slow or down server never holds a prompt, a tool, a turn or the session's start.
//
// With no thread identity and TLON_OPERATOR set, the same mod is the operator's: a band of what
// waits on them, the release and their streak, and the coworkers' asks put to them as questions.

import { doingOf, summaryOf } from "./lib/doing.ts";
import { renderBrief, type ChatterMessage, type Dossier } from "./lib/brief.ts";
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
import { DEFAULT_MODEL, delegateSettings, isImagePath, mimeOf, parseArgs, parseToolArgs, serializeTranscript, VISION_MODELS, visionPrompt } from "./lib/consult.ts";
import { attribution, bandParts, figureCells, gateOf, landingsOf, mentionsOf, operatorApi, turnWord, type Glance } from "./lib/citizen.ts";
import { CHIME_WAV } from "./lib/chime.ts";

// Below this much new transcript a turn's capture waits for the next turn instead of paying for
// an extraction call; a compaction flushes whatever is there.
const MIN_DELTA_CHARS = 2_000;
const THREAD_PANE = "tlon-thread";
// How often the session looks for wakes the server queued for it (Server.Wake). Taking them is
// not activity on the server's side, so polling never keeps an idle session warm.
const WAKE_POLL_MS = 3_000;
// The office glance and the operator's band: slow, because nothing on them is urgent.
const GLANCE_MS = 120_000;
// A line from the office's pool, at most this often.
const LINE_EVERY_MS = 3_600_000;
// On the Claude plan, past this much of the five-hour window: Explore subagents run on Haiku (and
// every request at low effort, past plan/'s mark).
const HOT_5H = 75;

type Message = { author: string; body: string; at?: string };
type Figure = { columns: number; rows: number; cells: string };
type Need = { key: string; kind: string; level: string; ref?: number; title: string; text?: string; options?: { key: string; label: string }[] };

let thread = "";
let author = "";
let cwd = "";
let mainCheckout = "";
let onOllama = false;
let dossier: Dossier | null = null;
let glance: Glance | null = null;
let figure: Figure | null = null;
let briefed = "";
let lastCorrection = "";
let captured = 0;
let capturing = false;
let messages: Message[] = [];
let draining = false;
let seenMessage = -1;
let seenLanding = -1;
let seenRed = -1;
let lastLine = 0;
let operator = false;
let needs: Need[] = [];
let asked = new Set<string>();
let asking = false;
let release = "";
let life = "";
let api = operatorApi(undefined);

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

// The thread's dossier, and what in it is news: a mention of this seat, a workline landing.
async function refresh($) {
  try {
    dossier = (await call($, "get_dossier")) as Dossier;
  } catch {
    return;
  }
  const recent: ChatterMessage[] = dossier.recent ?? [];
  const newest = Math.max(-1, ...recent.map((m) => m.id));
  if (seenMessage >= 0) for (const m of mentionsOf(recent, seenMessage, author)) $.ui.toast(`${m.author}: ${m.body.slice(0, 140)}`, { timeoutMs: 10_000 });
  seenMessage = Math.max(seenMessage, newest);
  const landed = landingsOf(dossier, seenLanding);
  if (seenLanding >= 0 && landed.length && dossier.lead === author) {
    $.ui.toast("landed ✓");
    $.audio.play({ base64: CHIME_WAV, mime: "audio/wav" }).catch(() => {});
  }
  seenLanding = Math.max(seenLanding, ...landed, ...(dossier.done.shown.map((e) => e.id) ?? []));
  $.ui.invalidate("ui.render");
}

// The office from this seat: who else is on, what is red here, this seat's voice, a line now and then.
async function refreshGlance($) {
  try {
    const got = (await call($, "office_glance")) as Glance;
    if (!got || !Array.isArray(got.red) || !Array.isArray(got.crew)) return;
    glance = got;
  } catch {
    return;
  }
  try {
    if (seenRed >= 0 && glance.red.length > seenRed) $.ui.toast(`🔴 ${glance.red[glance.red.length - 1]!.text}`, { timeoutMs: 10_000 });
    seenRed = glance.red.length;
    const now = await $.clock.now();
    if (glance.line && now - lastLine > LINE_EVERY_MS) {
      if (lastLine) $.ui.toast(glance.line, { timeoutMs: 8_000 });
      lastLine = now;
    }
  } finally {
    $.ui.invalidate("ui.render");
  }
}

// The coworker's own figure, from the office's art (`office/cli.ts figure`), for the pane.
async function loadFigure($, archetype: string | null) {
  const office = `${$.plugin.root}/../office/cli.ts`;
  try {
    const r = await $.process.run(["bun", office, "figure", author, ...(archetype ? [archetype] : [])]);
    if (r.exitCode !== 0) return;
    const { rows, paint } = JSON.parse(r.stdout);
    figure = figureCells(rows, paint);
  } catch {
    return;
  }
}

// A wake (a teammate's message, an opening assignment) arrives as if typed: Claude Code holds it
// until the session is idle, so it never lands on a booting input or a half-written prompt. Taking
// deletes the server's row, so a wake whose submit fails is put back for the next poll.
async function drainWakes($) {
  if (draining) return;
  draining = true;
  try {
    const wakes = await call($, "take_wakes");
    const failed: string[] = [];
    if (Array.isArray(wakes))
      for (const text of wakes.map(String)) {
        try {
          await $.prompt.submit({ text, asUser: true });
        } catch {
          failed.push(text);
        }
      }
    if (failed.length) await call($, "put_back_wakes", { prompts: failed });
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
// read-only tools — a bash of its own would run outside the asking session's sandbox — and the
// seat's own deny rules, so it reads nothing the seat may not.
async function delegate($, model: string, task: string): Promise<string> {
  const key = await ollamaKey($);
  if (!key) throw new Error("no OLLAMA_API_KEY for the delegate");
  const tools = "Read,Grep,Glob";
  const settings = delegateSettings(await $.env.get("TLON_PERMISSIONS_DENY"));
  const r = await $.process.run(
    ["claude", "-p", task, "--model", model, "--tools", tools, "--allowedTools", tools, "--permission-mode", "dontAsk", "--no-session-persistence", "--settings", settings],
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
  if (!onOllama || VISION_MODELS.includes(await $.session.model())) return null;
  const b64 = await $.process.run(["base64", "-w0", path]);
  if (b64.exitCode !== 0) return null;
  const prompt = visionPrompt(await $.session.messages());
  const description = await complete($, DEFAULT_MODEL, [
    { type: "text", text: prompt },
    { type: "image_url", image_url: { url: `data:${mimeOf(path)};base64,${b64.stdout.trim()}` } },
  ]);
  return `Read image file ${path} — this model can't see images, so ${DEFAULT_MODEL} described it:\n\n${description}`;
}

// What the language server says about a file just written, for the model to read with the result.
async function diagnosticsOf($, path: string): Promise<string | null> {
  try {
    const r = await $.mcp.call("lsp", "diagnostics", { path });
    const text = r.content.find((b) => b.type === "text")?.text?.trim() ?? "";
    if (r.isError || !text || /^no diagnostics/i.test(text)) return null;
    return `Language server diagnostics for ${path} after this edit:\n${text}`;
  } catch {
    return null;
  }
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

// The operator's band: what waits on them, the release pointer, their streak.
async function refreshOperator($) {
  try {
    const res = await $.http.fetch(`${api}/office/needs`);
    if (res.ok) needs = JSON.parse(res.text) as Need[];
    const office = await $.http.fetch(`${api}/office`);
    if (office.ok) {
      const lives = Object.values(JSON.parse(office.text).life ?? {}) as { level?: number; xp?: number; streaks?: { days?: number }[] }[];
      const l = lives[0];
      life = l ? `lvl ${l.level ?? "?"}${l.streaks?.[0]?.days ? ` · 🔥${l.streaks[0].days}` : ""}` : "";
    }
  } catch {
    return;
  }
  $.ui.invalidate("ui.render");
  void askNext($);
}

async function refreshRelease($) {
  try {
    const r = await $.process.run(["mise", "run", "-q", "release:status"], { cwd: `${$.plugin.root}/..`, timeoutMs: 60_000 });
    const lines = r.stdout.split("\n");
    const live = lines.find((l) => l.startsWith("release"))?.split(/\s+/)[1] ?? "";
    const behind = lines.find((l) => l.startsWith("on main, not released"))?.match(/\((\d+)\)/)?.[1];
    release = live ? `live ${live}${behind ? ` · ${behind} unreleased` : ""}` : "";
  } catch {
    return;
  }
  $.ui.invalidate("ui.render");
}

// A coworker's ask (one decision with its answers) put to the operator in their own session.
async function askNext($) {
  if (asking) return;
  const ask = needs.find((n) => n.kind === "ask" && n.ref && n.options?.length && !asked.has(n.key));
  if (!ask) return;
  asking = true;
  asked.add(ask.key);
  try {
    const label = await $.ui.ask(`${ask.title}${ask.text ? `\n${ask.text}` : ""}`, ask.options!.map((o) => o.label));
    const option = ask.options!.find((o) => o.label === label);
    if (option)
      await $.http.fetch(`${api}/office/asks/${ask.ref}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ key: option.key }) });
  } catch {
    asked.delete(ask.key);
  } finally {
    asking = false;
  }
}

function percent(n: number | undefined): string {
  return n === undefined ? "?" : `${Math.round(n)}%`;
}

async function fiveHourUsed($): Promise<number> {
  const usage = await $.session.usage();
  return usage.rateLimits.find((r) => r.kind === "five_hour")?.percentUsed ?? 0;
}

export function register(on) {
  on("session.start", async ($, e, next) => {
    thread = (await $.env.get("TLON_THREAD")) ?? "";
    author = (await $.env.get("TLON_AUTHOR")) ?? "";
    onOllama = !!(await $.env.get("ANTHROPIC_BASE_URL"));
    mainCheckout = $.plugin.root.replace(/\/adapters\/?$/, "");
    if (!thread || !author) {
      operator = !!(await $.env.get("TLON_OPERATOR"));
      if (operator) {
        api = operatorApi(await $.env.get("TLON_MCP_URL"));
        $.clock.every(GLANCE_MS, () => refreshOperator($));
        $.clock.every(GLANCE_MS * 5, () => refreshRelease($));
        void refreshOperator($);
        void refreshRelease($);
      }
      return next(e);
    }
    cwd = e.cwd;
    const pane = await $.env.get("TMUX_PANE");
    declare($, "register", pane ? { pane_ref: pane } : {});
    $.clock.every(WAKE_POLL_MS, () => drainWakes($));
    $.clock.every(GLANCE_MS, () => refreshGlance($));
    void refresh($);
    void refreshGlance($).then(() => {
      void loadFigure($, glance?.archetype ?? null);
      const landed = glance?.landed ?? [];
      if (landed.length) $.ui.toast(`landed today: ${landed.slice(0, 3).map((l) => `#${l.thread_id} ${l.title}`).join(" · ")}${landed.length > 3 ? ` +${landed.length - 3}` : ""}`, { timeoutMs: 10_000 });
    });
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
      if (onOllama) {
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

  // #42 and @seat: the threads and the crew this session knows of.
  on("prompt.autocomplete", async ($, e, next) => {
    if (!thread || !/^[#@]/.test(e.token)) return next(e);
    const typed = e.token.slice(1).toLowerCase();
    const suggestions =
      e.token[0] === "@"
        ? (glance?.crew ?? []).filter((c) => c.agent.toLowerCase().startsWith(typed)).map((c) => ({ text: `@${c.agent}`, description: `#${c.thread_id}` }))
        : [
            ...(dossier?.cited ?? []).map((c) => ({ text: `#${c.id}`, description: c.title })),
            ...(glance?.crew ?? []).map((c) => ({ text: `#${c.thread_id}`, description: c.agent })),
          ].filter((s) => s.text.slice(1).startsWith(typed));
    return { suggestions };
  });

  on("turn.start", async ($, e, next) => {
    if (thread) declare($, "presence_thinking");
    return next(e);
  });

  on("agent.spawn", async ($, e, next) => {
    if (!onOllama && e.subagentType === "Explore" && (await fiveHourUsed($)) >= HOT_5H) return next({ ...e, model: "haiku" });
    return next(e);
  });

  // Held before they run: a push (the server pushes), a branch switch in the live checkout, a
  // production write (the operator's to press).
  on("tool.check", { tool: "Bash" }, async ($, e, next) => {
    const command = (e.input as { command?: unknown })?.command;
    const gate = typeof command === "string" ? gateOf(command, cwd || (await $.session.cwd()), mainCheckout, (await $.env.get("HOME")) ?? "") : null;
    return gate ?? next(e);
  });

  // For Elixir the AST tools keep a change to its own clause; a recorded check is the evidence a
  // gate reads, so it is always at hand.
  on("tool.describe", async ($, e, next) => {
    if (!thread) return next(e);
    const r = await next(e);
    if (e.tool === "Edit" || e.tool === "Write")
      return { ...r, description: `${r.description}\n\nFor Elixir (.ex/.exs), prefer mcp__tlon__edit_clause and mcp__tlon__rename_identifier: they change exactly the clause or name, formatted.` };
    if (e.tool === "mcp__tlon__record_check") return { ...r, isDeferred: false };
    return r;
  });

  on("attribution.text", { kind: "commit" }, async ($, e, next) => {
    if (!thread) return next(e);
    const sign = attribution(await $.session.model(), onOllama);
    const lines = e.text.split("\n").filter((l) => !/^Co-Authored-By:/i.test(l));
    return { text: [sign, ...lines].join("\n") };
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
    if (thread && (e.tool === "Edit" || e.tool === "Write") && typeof e.file_path === "string") {
      const r = await next(e);
      if (!r || "deny" in r) return r;
      const diagnostics = await diagnosticsOf($, e.file_path);
      return diagnostics ? { ...r, context: [...(r.context ?? []), diagnostics] } : r;
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

  // The coworker's own voice while it works, and a word for the turn it finished.
  on("ui.render", { component: "Spinner" }, async ($, e, next) => {
    const phrase = glance?.persona?.catchphrase;
    if (!thread || !phrase) return next(e);
    return next({ ...e, props: { ...e.props, suffix: ` · ${phrase}` } });
  });

  on("ui.render", { component: "TurnDuration" }, async ($, e, next) => {
    if (!thread) return next(e);
    return next({ ...e, props: { ...e.props, word: turnWord(e.requestId ?? "") } });
  });

  on("ui.render", { component: "AbovePrompt" }, async ($, e, next) => {
    if (!thread && !operator) return next(e);
    const { Box, Text } = $.ui.resolve(e);
    const usage = await $.session.usage();
    const limit = (kind: string) => usage.rateLimits.find((r) => r.kind === kind);
    const fiveHour = limit("five_hour");
    const week = limit("seven_day");
    const meters = [`ctx ${percent(usage.context.percent)}`];
    if (fiveHour) meters.push(`5h ${percent(fiveHour.percentUsed)}`);
    if (week) meters.push(`wk ${percent(week.percentUsed)}`);
    let left: string[];
    if (operator) {
      const blocking = needs.filter((n) => n.level === "blocking").length;
      left = [`needs ${needs.length}${blocking ? ` (${blocking} blocking)` : ""}`];
      if (release) left.push(release);
      if (life) left.push(life);
    } else {
      left = bandParts(thread, dossier, glance?.red.length ?? 0);
    }
    return Box({
      flexDirection: "column",
      children: [
        Box({
          flexDirection: "row",
          justifyContent: "space-between",
          children: [
            Text({ wrap: "truncate-end", children: [left.join(" · ")] }),
            Text({ dimColor: true, children: [`${operator ? "operator" : author} · ${meters.join(" · ")}`] }),
          ],
        }),
        await next(e),
      ],
    });
  });

  on("ui.render", { component: "Pane" }, async ($, e, next) => {
    if (e.requestId !== THREAD_PANE) return next(e);
    const { Box, Text, Markdown, Button, Raster } = $.ui.resolve(e);
    const d = dossier;
    const head: unknown[] = [];
    const who = [Text({ bold: true, children: [author] })];
    if (glance?.persona?.voice) who.push(Text({ dimColor: true, children: [glance.persona.voice] }));
    head.push(
      Box({
        key: "who",
        flexDirection: "row",
        columnGap: 2,
        children: [
          ...(figure && e.surface === "terminal" ? [Raster({ key: "figure", columns: figure.columns, rows: figure.rows, cells: figure.cells })] : []),
          Box({ flexDirection: "column", children: who }),
        ],
      }),
    );
    if (d?.workline) {
      head.push(Text({ key: "stage", children: [`stage ${d.workline.stage}${d.workline.awaiting ? ` — awaiting ${d.workline.awaiting}` : ""}${d.workline.why ? ` (${d.workline.why})` : ""}`] }));
      head.push(
        Box({
          key: "gates",
          flexDirection: "row",
          columnGap: 3,
          children: [
            Button({ key: "advance", label: "advance", hotkey: "a", plain: true, onPress: () => $.prompt.fill({ text: "Call advance_stage for this workline." }) }),
            Button({ key: "finish", label: "finish", hotkey: "f", plain: true, onPress: () => $.prompt.fill({ text: "This thread's work is done and verified: call finish with a summary." }) }),
          ],
        }),
      );
    }
    const commits = d?.commits?.shown ?? [];
    if (commits.length) head.push(Text({ key: "commits", dimColor: true, children: [`${commits.length + (d?.commits?.more ?? 0)} commits · ${commits[0]!.subject}`] }));
    if (d?.cited?.length) head.push(Text({ key: "cited", dimColor: true, children: [`cites ${d.cited.map((c) => `#${c.id}${c.stage ? ` (${c.stage})` : ""}`).join(", ")}`] }));
    const crew = glance?.crew ?? [];
    if (crew.length)
      head.push(Text({ key: "crew", children: [crew.map((c) => `${c.thinking ? "●" : c.warm ? "○" : "·"} ${c.agent}${c.doing ? ` ${c.doing}` : ""}`).join("  ")] }));
    const body = messages.length
      ? messages.map((m, i) => Box({ key: `m${i}`, flexDirection: "column", children: [Text({ bold: true, children: [m.author] }), Markdown({ text: m.body })] }))
      : [Text({ key: "empty", dimColor: true, children: ["no messages on this thread yet"] })];
    return Box({ flexDirection: "column", children: [...head, Text({ key: "rule", dimColor: true, children: ["─".repeat(20)] }), ...body] });
  });
}
