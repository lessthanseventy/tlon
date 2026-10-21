// The claude-code adapter's mod: what makes a Claude Code session a citizen of its tlon thread,
// from inside the session. Claude Code runs it in its own process, so every call goes over the
// session's own `tlon` MCP connection (launch.sh's --mcp-config, headersHelper-authed) — no bun per
// hook, no second client, and the calls leave in the order the events fire.
//
// The server is the only state: the module's variables are per-session bookkeeping (what was last
// briefed, how far capture has read, which mentions were shown), lost on a reload, never a queue of
// unsent work. A slow or down server never holds a prompt, a tool, a turn or the session's start.
//
// With no thread identity and TLON_OPERATOR_MODE set, the same mod is the operator's: a band of what
// waits on them, the release and their streak, and the coworkers' asks put to them as questions.

import { doingOf, summaryOf } from "./lib/doing.ts";
import { ago, asDossier, renderBrief, type ChatterMessage, type Dossier } from "./lib/brief.ts";
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
import { seatGlyph, seatStatus } from "./lib/status.ts";
import { attribution, bandParts, figureCells, gateOf, landedAlerts, landingsOf, mentionsOf, operatorApi, turnWord, usageReport, type Glance } from "./lib/citizen.ts";
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
// How long a prompt waits on get_dossier before going on with the last brief (a hook's own
// budget is 10s, and a $.clock wait counts against it).
const DOSSIER_WAIT_MS = 3_000;
// How long one get_dossier holds the refresh flight before it is abandoned (its late reply dropped),
// so a call that never answers can't wedge every refresh queued behind it.
const DOSSIER_GIVE_UP_MS = 30_000;
const NO_BRIEF = "(no brief)";

type Message = { author: string; body: string; at?: string };
type Figure = { columns: number; rows: number; cells: string };
type Need = { key: string; kind: string; level: string; ref?: number; title: string; text?: string; options?: { key: string; label: string }[] };

let thread = "";
let author = "";
let cwd = "";
let mainCheckout = "";
let onOllama = false;
let dossier: Dossier | null = null;
let dossierAt = 0;
let dossierError = "";
let glance: Glance | null = null;
let figure: Figure | null = null;
let briefed = "";
// percent of the context window past which a turn starts by compacting (TLON_COMPACT_AT, the profile's
// `compact_at`); 0 leaves compaction to Claude Code
let compactAt = 0;
let lastCorrection = "";
let captured = 0;
let capturing = false;
let messages: Message[] = [];
let draining = false;
// submits run one at a time on their own chain: the host holds one until the session is idle, and
// that wait must never hold the poll that takes the next wakes
let submitting: Promise<void> = Promise.resolve();
// subagents whose turn started and has not ended: the session is busy while any runs, even after
// its own turn ended
const running = new Set<string>();
let mainEnded = false;
let waitTicks = 0;
const STALE_REFRESH_TICKS = 60;
// what register still has to send: at boot the tlon MCP server may not be connected yet, and a
// seat whose register was lost runs its whole life off the roster
let registration: Record<string, unknown> | null = null;
let registerFailed = false;
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

// What a hook met and couldn't use, one line each in $XDG_STATE_HOME/tlon/citizen-<author>.log (the
// last 200): the pane's transcript shows only that a hook was skipped, never what it got.
async function note($, what: string) {
  try {
    const state = (await $.env.get("XDG_STATE_HOME")) || `${(await $.env.get("HOME")) ?? ""}/.local/state`;
    const path = `${state}/tlon/citizen-${author || "unknown"}.log`;
    const old = await $.fs.read(path).then((t) => String(t), () => "");
    const line = `${new Date(await $.clock.now()).toISOString()} ${what.replace(/\n/g, " ")}`;
    await $.fs.write(path, [...old.split("\n").filter(Boolean), line].slice(-200).join("\n") + "\n");
  } catch {
    // a log that can't be written is no reason to fail the hook it serves
  }
}

// One dossier read in flight, at most one queued behind it (office/tui/flight.ts's shape): two
// replies landing out of order would let the older overwrite the newer and advance seenMessage twice.
let dossierFlight: Promise<void> | null = null;
let dossierQueued: Promise<void> | null = null;
function refresh($): Promise<void> {
  if (!dossierFlight) return (dossierFlight = readDossier($).finally(() => { dossierFlight = null; }));
  const again = () => { dossierQueued = null; return refresh($); };
  return (dossierQueued ??= dossierFlight.then(again, again));
}

// The thread's dossier, and what in it is news: a mention of this seat, a workline landing.
async function readDossier($) {
  let got: unknown;
  try {
    // a sleep the host refuses never gives up rather than abandoning a call that may yet answer
    const giveUp = $.clock.sleep(DOSSIER_GIVE_UP_MS).then(
      () => { throw new Error(`took over ${DOSSIER_GIVE_UP_MS / 1000}s`); },
      () => new Promise<never>(() => {}),
    );
    got = await Promise.race([call($, "get_dossier"), giveUp]);
  } catch (err) {
    dossierError = err instanceof Error ? err.message : String(err);
    return void note($, `get_dossier: ${dossierError}`);
  }
  // a reply that isn't one (a server mid-restart, a scratch release taken down) keeps the last good dossier
  const d = asDossier(got);
  if (!d) {
    dossierError = "not a dossier";
    return void note($, `get_dossier: not a dossier: ${JSON.stringify(got).slice(0, 300)}`);
  }
  dossier = d;
  dossierAt = await $.clock.now();
  dossierError = "";
  const recent: ChatterMessage[] = dossier.recent ?? [];
  const newest = Math.max(-1, ...recent.map((m) => m.id));
  if (seenMessage >= 0) for (const m of mentionsOf(recent, seenMessage, author)) $.ui.toast(`${m.author}: ${m.body.slice(0, 140)}`, { timeoutMs: 10_000 });
  seenMessage = Math.max(seenMessage, newest);
  const landed = landingsOf(dossier, seenLanding);
  if (seenLanding >= 0 && landed.length && dossier.lead === author) {
    $.ui.toast((await landedToday($)).find((a) => a.thread_id === Number(thread))?.title ?? "landed ✓");
    $.audio.play({ base64: CHIME_WAV, mime: "audio/wav" }).catch(() => {});
  }
  seenLanding = Math.max(seenLanding, ...landed, ...dossier.done.shown.map((e) => e.id));
  $.ui.invalidate("ui.render");
}

// The landing rows of the alerts the desktop raises, so both surfaces toast the server's own wording.
async function landedToday($) {
  try {
    const res = await $.http.fetch(`${api}/alerts`);
    return res.ok ? landedAlerts(JSON.parse(res.text)) : [];
  } catch {
    return [];
  }
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

let sessionId: number | null = null;
let superseded = false;
let registering: Promise<void> | null = null;
function registerNow($): Promise<void> {
  return (registering ??= (async () => {
    const args = registration;
    if (!args) return;
    try {
      const claimed = await call($, "register", args);
      sessionId = (claimed as { session_id?: number } | null)?.session_id ?? null;
      registration = null;
    } catch (e) {
      if (!registerFailed) void note($, `register: ${e instanceof Error ? e.message : String(e)} — trying again every poll`);
      registerFailed = true;
    }
  })().finally(() => {
    registering = null;
  }));
}

// A wake (a teammate's message, an opening assignment) arrives as if typed: Claude Code holds it
// until the session is idle, so it never lands on a booting input or a half-written prompt. Taking
// deletes the server's row, so a wake whose submit fails is put back for the next poll.
function submitWakes($, texts: string[]) {
  submitting = submitting.then(async () => {
    const failed: string[] = [];
    for (const text of texts) {
      try {
        await $.prompt.submit({ text, asUser: true });
      } catch {
        failed.push(text);
      }
    }
    if (failed.length) await call($, "put_back_wakes", { prompts: failed }).catch(() => {});
  });
}

async function drainWakes($) {
  if (draining) return;
  draining = true;
  try {
    const wakes = await call($, "take_wakes", sessionId === null ? {} : { session_id: sessionId });
    // a newer session holds this seat: say so once, then take nothing and register nothing — but
    // keep asking, so a seat whose newer session has since ended is claimed again, not left empty
    if (wakes && typeof wakes === "object" && (wakes as { superseded?: boolean }).superseded) {
      if (superseded) return;
      superseded = true;
      registration = null;
      submitWakes($, [String((wakes as { text?: string }).text ?? "")]);
      return;
    }
    // only a real wake list says the seat is free: a non-JSON reply (server mid-restart) must not
    // register this stopped session over the live newer one
    if (superseded && Array.isArray(wakes)) {
      superseded = false;
      void note($, "take_wakes: no longer superseded — claiming the seat again");
      const pane = await $.env.get("TMUX_PANE");
      registration = pane ? { pane_ref: pane } : {};
      void registerNow($);
    }
    if (Array.isArray(wakes) && wakes.length) submitWakes($, wakes.map(String));
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
    api = operatorApi(await $.env.get("TLON_MCP_URL"));
    compactAt = Number(await $.env.get("TLON_COMPACT_AT")) || 0;
    if (!thread || !author) {
      operator = !!(await $.env.get("TLON_OPERATOR_MODE"));
      if (operator) {
        $.clock.every(GLANCE_MS, () => refreshOperator($));
        $.clock.every(GLANCE_MS * 5, () => refreshRelease($));
        void refreshOperator($);
        void refreshRelease($);
      }
      return next(e);
    }
    cwd = e.cwd;
    const pane = await $.env.get("TMUX_PANE");
    registration = pane ? { pane_ref: pane } : {};
    registerFailed = false;
    superseded = false;
    sessionId = null;
    void registerNow($);
    $.clock.every(WAKE_POLL_MS, async () => {
      // the host's stale-turn clock would read a long wait on a subagent as a dead turn
      if (thread && mainEnded && running.size && ++waitTicks % STALE_REFRESH_TICKS === 0)
        declare($, "presence_doing", { summary: "waiting on a background agent" });
      if (registration) await registerNow($);
      await drainWakes($);
    });
    $.clock.every(GLANCE_MS, () => refreshGlance($));
    void refresh($);
    void refreshGlance($).then(() => {
      void loadFigure($, glance?.archetype ?? null);
      void landedToday($).then((rows) => {
        const titles = rows.length ? rows.map((a) => a.title) : (glance?.landed ?? []).map((l) => `#${l.thread_id} ${l.title}`);
        if (titles.length) $.ui.toast(`landed today: ${titles.slice(0, 3).join(" · ")}${titles.length > 3 ? ` +${titles.length - 3}` : ""}`, { timeoutMs: 10_000 });
      });
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
    running.clear();
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
    // a server that never answers holds the prompt DOSSIER_WAIT_MS at most; a sleep the host
    // refuses never times out rather than racing ahead of the answer
    const late = await Promise.race([
      refresh($).then(() => false),
      $.clock.sleep(DOSSIER_WAIT_MS).then(() => true, () => new Promise<boolean>(() => {})),
    ]);
    const brief = (text: string) => next({ ...e, context: [...(e.context ?? []), `<tlon-brief>\n${text}\n</tlon-brief>`] });
    if (!dossier) {
      if (briefed === NO_BRIEF) return next(e);
      briefed = NO_BRIEF;
      const why = late ? `took over ${DOSSIER_WAIT_MS / 1000}s` : dossierError || "no reply";
      return brief(`No brief: the tlon server didn't answer get_dossier (${why}). get_messages reads the thread when it is back.`);
    }
    const key = JSON.stringify(dossier);
    if (key === briefed) return next(e);
    briefed = key;
    const now = await $.clock.now();
    const why = late ? " in time" : dossierError ? ` (${dossierError})` : "";
    const asOf = why ? `\n_the server didn't answer${why}: this brief is as of ${ago(new Date(dossierAt), new Date(now))}, the last it gave._` : "";
    return brief(renderBrief(dossier, new Date(), await $.session.model(), undefined, (await $.env.get("TLON_OPERATOR")) || undefined) + asOf);
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
    if (e.agentId) running.add(e.agentId);
    else mainEnded = false;
    if (thread && !e.agentId) declare($, "presence_thinking");
    return next(e);
  });

  on("agent.spawn", async ($, e, next) => {
    if (!onOllama && e.subagentType === "Explore" && (await fiveHourUsed($)) >= HOT_5H) return next({ ...e, model: "haiku" });
    return next(e);
  });

  // A refusal is reported, never acted on: the server derives the operator's `tool_denied` Need from
  // these (two or more since the workline last moved, nobody working it), the check's reason with it.
  on("tool.check", async ($, e, next) => {
    const r = (await next(e)) as { decision?: string; reason?: string } | undefined;
    if (thread && r?.decision === "deny") declare($, "tool_denied", { tool: e.tool, summary: summaryOf(e.tool, e.input, cwd), ...(r.reason ? { reason: r.reason } : {}) });
    return r;
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
    if (e.agentId) running.delete(e.agentId);
    else mainEnded = true;
    if (thread && !e.agentId) {
      void capture($, MIN_DELTA_CHARS);
      void refresh($);
    }
    if (thread && mainEnded && running.size === 0) declare($, "presence_idle");
    const done = await next(e);
    // past its compaction point, a seat compacts while idle between turns (never under one: the host
    // refuses that), so the next prompt carries the whole brief
    const filled =
      thread && !e.agentId && compactAt
        ? await $.session.usage().then(
            (u) => u.context.percent ?? 0,
            (err) => (void note($, `usage unread for compaction: ${err}`), 0),
          )
        : 0;
    if (compactAt && filled >= compactAt)
      void $.session
        .compact({ instructions: "Keep what is in flight: the task at hand, what was decided and why, what is still open. The brief comes back whole after this." })
        .catch((err) => note($, `compaction at ${compactAt}% refused: ${err}`));
    return done;
  });

  on("session.compact", async ($, e, next) => {
    if (thread) await capture($, 1);
    const r = await next(e);
    // the summary stands where the brief was: the next prompt carries it whole again (a precompute installs nothing)
    if (!r.skip && e.trigger !== "precompute" && !e.agentId) briefed = "";
    return r;
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

  // the plan's windows, for the office's meter: pushed when one moves a whole point, never polled
  on("session.measure", async ($, e, next) => {
    const report = e.changed.includes("rateLimits") ? usageReport(e.rateLimits) : null;
    if (report) void $.http.fetch(`${api}/usage/claude`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(report) }).catch(() => {});
    return next(e);
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
      head.push(Text({ key: "crew", children: [crew.map((c) => `${seatGlyph(seatStatus(c))} ${c.agent}${c.doing ? ` ${c.doing}` : ""}`).join("  ")] }));
    const body = messages.length
      ? messages.map((m, i) => Box({ key: `m${i}`, flexDirection: "column", children: [Text({ bold: true, children: [m.author] }), Markdown({ text: m.body })] }))
      : [Text({ key: "empty", dimColor: true, children: ["no messages on this thread yet"] })];
    return Box({ flexDirection: "column", children: [...head, Text({ key: "rule", dimColor: true, children: ["─".repeat(20)] }), ...body] });
  });
}
