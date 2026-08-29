// adapters — the pi adapter (pi doc §2b). Three lifecycle hooks make a pi session a citizen
// of its funes thread: session_start registers (claims the pane, supersedes any zombie
// predecessor); before_agent_start injects the rendered dossier as the honest brief
// (aleph §3b: briefed from funes state, never a raw replay); turn_end refreshes the footer.
//
// Holds no state, touches no SQLite — calls funes through its own MCP client (mcp.ts).
// When funes is unreachable it surfaces the failure and does nothing else: no retry queue,
// no spill file (AGENTS.md, pi doc §2a).

import { env } from "node:process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { lastToolActivity, phraseHeartbeat, sawSuccessfulCommit } from "./activity.ts";
import { renderBrief, type Dossier } from "./brief.ts";
import { FunesClient, FunesRejected, FunesUnreachable, type FunesConfig } from "./mcp.ts";
import { detectCorrection } from "./recall.ts";
import {
  buildExtractionPrompt,
  deltaSince,
  DEFAULT_CAPTURE_MODEL,
  parseExtraction,
  redactSecrets,
  serializeDelta,
} from "./capture.ts";
import { completeText } from "./llm.ts";
import type { ExtensionAPI, ExtensionContext } from "./pi.ts";

// The cheap model that runs cadence extraction out-of-band (ollama-cloud), shared with the
// claude-code reflex via capture.ts's DEFAULT_CAPTURE_MODEL. Overridable per-pane via
// funes-recall.json `captureModel` (e.g. a local-daemon model to keep deltas off the wire entirely).
const CAPTURE_MODEL = DEFAULT_CAPTURE_MODEL;

interface RecallConfig {
  correctionDetection: boolean;
  boundaryCapture: boolean;
  captureEveryTurns: number;
  captureModel: string;
}

const RECALL_DEFAULTS: RecallConfig = {
  correctionDetection: true,
  boundaryCapture: true,
  captureEveryTurns: 8,
  captureModel: CAPTURE_MODEL,
};

// The total-recall noise knob: ~/.pi/agent/funes-recall.json (flake-seeded with defaults + a
// comment). A missing/broken file → defaults, so the adapter never fails to load over config.
function readRecallConfig(): RecallConfig {
  try {
    const raw = readFileSync(join(homedir(), ".pi/agent/funes-recall.json"), "utf-8");
    const c = JSON.parse(raw) as Partial<RecallConfig>;
    const n = c.captureEveryTurns;
    return {
      correctionDetection: c.correctionDetection !== false,
      boundaryCapture: c.boundaryCapture !== false,
      captureEveryTurns: typeof n === "number" && n > 0 ? Math.floor(n) : RECALL_DEFAULTS.captureEveryTurns,
      captureModel:
        typeof c.captureModel === "string" && c.captureModel.trim()
          ? c.captureModel.trim()
          : RECALL_DEFAULTS.captureModel,
    };
  } catch {
    return { ...RECALL_DEFAULTS };
  }
}

const STATUS_KEY = "funes";
const WIDGET_KEY = "funes";

// Identity travels in the spawn (pi doc §2d): TLON_MCP_URL/THREAD/AUTHOR. No TLON_TOKEN
// — the client mints a fresh token per connect against the URL's origin, so a pane survives
// a token-model change or secret regeneration. Missing any of the three means this pane
// wasn't spawned as a funes citizen; the adapter stays quiet rather than guessing.
function readConfig(): FunesConfig | null {
  const url = env.TLON_MCP_URL;
  const thread = env.TLON_THREAD;
  const author = env.TLON_AUTHOR;
  if (!url || !thread || !author) return null;
  const threadId = Number(thread);
  if (!Number.isInteger(threadId)) return null;
  return { url, threadId, agent: author };
}

function identityLabel(): string {
  return `${env.TLON_AUTHOR ?? "?"} on ${env.TLON_THREAD ?? "?"}`;
}

export default function adapters(pi: ExtensionAPI): void {
  const config = readConfig();

  // One client for this pane's lifetime — connect() is guarded so only the first hook does
  // the handshake. register binds the session to the TOKEN, so the model's own tool calls
  // (a separate connection, same token) resolve this same session.
  const client = config ? new FunesClient(config) : null;

  // The last dossier state we surfaced this pane. The dossier is re-read every turn (to catch
  // what peers banked), but re-DISPLAYING an unchanged brief every turn buries the pane in
  // duplicate blocks — the "why so many mid-convo briefs" smell. We keep feeding the model the
  // current brief each turn; we only surface it to the operator when the state actually changed.
  // Keyed on the dossier, NOT the rendered brief — the brief's staleness line ("40m ago") drifts
  // with the clock, so a rendered-string compare would re-display on time alone, not on change.
  let lastDossierKey: string | null = null;

  // Total-recall state (slices C/D): the noise knob, read once at start; the last correction we
  // proposed (dedup); and the cadence-capture bookkeeping — a watermark into the entry list (how
  // far we've captured), a turn counter, and a re-entrancy guard so a compaction flush and a turn
  // tick can't double-capture the same delta.
  let recall: RecallConfig = { ...RECALL_DEFAULTS };
  let lastProposedCorrection: string | null = null;
  let watermark = 0;
  let turnCount = 0;
  let capturing = false;

  // The heartbeat (funes thread #3, 2026-08-27): "here's what's happening" check-ins on a
  // cadence during a long single turn, instead of silence until turn_end. turnStartedAt seeds
  // the elapsed-time the sidecar's prompt (and the mechanical fallback) names; heartbeatTimer
  // is armed in turn_start and disarmed in turn_end, so it can never tick after (or across) a
  // turn boundary — a stray post from a finished turn would misread as still-running.
  const HEARTBEAT_INTERVAL_MS = 45_000;
  let heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  // Auto-track latch (reshape slice B): once this session has promoted its thread, stop scanning.
  let threadTracked = false;
  let turnStartedAt = 0;

  const runHeartbeat = async (ctx: ExtensionContext): Promise<void> => {
    if (!client) return;
    try {
      const activity = lastToolActivity(ctx.sessionManager.buildContextEntries());
      const elapsedSeconds = (Date.now() - turnStartedAt) / 1000;
      const line = await phraseHeartbeat(activity, elapsedSeconds, completeText);
      await client.connect();
      await client.postMessage(line);
    } catch {
      // best-effort — a heartbeat failure must never interrupt the turn
    }
  };

  // Capture the delta since the watermark (bounded — a few turns, never the full window): extract
  // durable facts out-of-band via a cheap model, bank them DERIVED, raise any open questions.
  // Re-entrancy is the `capturing` guard (a compaction flush and a turn tick can't double-run);
  // the watermark advances ONLY after a successful extraction, so a failed call retries the same
  // delta next flush instead of punching a permanent hole in the record. The outbound delta is
  // secret-REDACTED before it leaves the box — funes' own scan guards the inbound bank one hop
  // too late to stop egress. Best-effort throughout: a failure never disturbs the session.
  const runCapture = async (ctx: ExtensionContext): Promise<void> => {
    if (!client || !recall.boundaryCapture || capturing) return;
    let entries;
    try {
      entries = ctx.sessionManager.buildContextEntries();
    } catch {
      return;
    }
    const { slice, nextWatermark } = deltaSince(entries, watermark);
    const delta = redactSecrets(serializeDelta(slice));
    if (!delta.trim()) {
      watermark = nextWatermark;
      return;
    }

    capturing = true;
    try {
      const { facts, questions } = parseExtraction(
        await completeText(recall.captureModel, buildExtractionPrompt(delta)),
      );
      watermark = nextWatermark;
      for (const f of facts) {
        try {
          await client.bankFact(f.text, f.kind, f.intent);
        } catch {
          /* a rejected fact (e.g. a secret) is dropped, never retried */
        }
      }
      for (const q of questions) {
        try {
          await client.raiseQuestion(q);
        } catch {
          /* best-effort */
        }
      }
      if (facts.length || questions.length) {
        ctx.ui.setStatus(STATUS_KEY, `funes: captured ${facts.length} fact(s), ${questions.length} question(s)`);
      }
    } catch {
      // extraction is a nicety; a failure never interrupts the session
    } finally {
      capturing = false;
    }
  };

  pi.on("session_start", async (_event, ctx) => {
    recall = readRecallConfig();
    if (!client) {
      ctx.ui.setStatus(STATUS_KEY, "funes: not wired (need TLON_MCP_URL / TLON_THREAD / TLON_AUTHOR)");
      return;
    }
    try {
      await client.connect();
      await client.register(env.TMUX_PANE);
      ctx.ui.setStatus(STATUS_KEY, `funes: registered — ${identityLabel()}`);
    } catch (err) {
      surface(ctx, err);
    }
  });

  pi.on("before_agent_start", async (event, ctx) => {
    if (!client) return;
    try {
      await client.connect();

      // If this turn's prompt reads as a correction, propose it as a pending habit — the operator
      // approves (or drops) it in the Tlön panel. Best-effort: a failure here must never fail the
      // turn, and we surface it quietly rather than as an error toast (a proposal is not a problem).
      if (recall.correctionDetection) {
        const habit = detectCorrection(event.prompt ?? "");
        if (habit && habit !== lastProposedCorrection) {
          lastProposedCorrection = habit;
          try {
            await client.proposeHabit(habit, "auto-detected from a correction you made");
            ctx.ui.setStatus(STATUS_KEY, "funes: proposed a habit from your correction (review in Tlön)");
          } catch {
            // proposing is a nicety; never interrupt the turn over it
          }
        }
      }

      const dossier = (await client.getDossier()) as Dossier;
      updateWidget(ctx, dossier);
      const content = renderBrief(dossier, new Date(), env.PI_MODEL);
      const key = JSON.stringify(dossier);
      const changed = key !== lastDossierKey;
      lastDossierKey = key;
      return { message: { customType: "funes-brief", content, display: changed } };
    } catch (err) {
      surface(ctx, err);
      return;
    }
  });

  // Thinking presence (the cockpit's typing indicator): declare at turn start, clear at turn
  // end. Best-effort both ways — presence is a nicety and must never disturb the session; a
  // crash that skips the idle is cleared by funes' own max-age sweep.
  pi.on("turn_start", async (_event, ctx) => {
    turnStartedAt = Date.now();
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    if (client) heartbeatTimer = setInterval(() => void runHeartbeat(ctx), HEARTBEAT_INTERVAL_MS);

    if (!client) return;
    try {
      await client.connect();
      await client.presenceThinking();
    } catch {
      // best-effort
    }
  });

  pi.on("turn_end", async (_event, ctx) => {
    if (heartbeatTimer) {
      clearInterval(heartbeatTimer);
      heartbeatTimer = null;
    }
    if (!client) return;
    try {
      await client.connect();
      await client.presenceIdle();
    } catch {
      // best-effort
    }
    try {
      await client.connect();
      updateWidget(ctx, (await client.getDossier()) as Dossier);
    } catch {
      // The footer is a nicety; a failed refresh must never interrupt or fail a turn.
    }
    // Auto-track (reshape slice B): a turn that landed a git commit promotes this thread into
    // the stage machine — mechanically, so the ticket condenses out of the work. Once is enough
    // per session (the server is idempotent anyway); best-effort like everything else here.
    if (!threadTracked) {
      try {
        if (sawSuccessfulCommit(ctx.sessionManager.buildContextEntries())) {
          await client.connect();
          await client.trackThread();
          threadTracked = true;
        }
      } catch (e) {
        // A REFUSAL (e.g. the root machine thread — its standing coworkers commit constantly)
        // latches too: retrying a doomed promote every turn_end forever helps no one. Only a
        // transport failure (funes down) leaves the latch open for a later retry.
        if (e instanceof FunesRejected) threadTracked = true;
      }
    }
    // Cadence capture (slice C): every Nth turn, flush the delta. Bounded input, so it never
    // overflows the cheap extractor however full the frontier context is.
    turnCount += 1;
    if (recall.boundaryCapture && turnCount % recall.captureEveryTurns === 0) {
      await runCapture(ctx);
    }
  });

  // The delta flush at the boundaries the cadence might miss: right before the context is compacted
  // (so the about-to-be-lost tail is captured), and best-effort at session end.
  pi.on("session_before_compact", async (_event, ctx) => {
    await runCapture(ctx);
  });
  pi.on("session_shutdown", async (_event, ctx) => {
    await runCapture(ctx);
  });
}

// The footer: the live at-a-glance the human driving pi directly sees — the same dossier
// the cockpit shows (pi doc §2b). For slice 2 that is the goal and the open blockers; the
// TODOS line joins when slice 3 lands.
function updateWidget(ctx: ExtensionContext, d: Dossier): void {
  const lines = [`funes · ${d.north_star ?? "(untitled)"} — ${d.lead ?? "unstaffed"}`];
  const blockers = d.blockers.shown.length + d.blockers.more;
  if (blockers > 0) {
    lines.push(`blockers (${blockers}):`);
    for (const b of d.blockers.shown) lines.push(`  • ${b.summary}`);
    if (d.blockers.more > 0) lines.push(`  • … +${d.blockers.more} more`);
  } else {
    lines.push("no open blockers");
  }
  ctx.ui.setWidget(WIDGET_KEY, lines);
}

// Surface and stop (pi doc §2a): distinguish "funes is down" from "funes said no", show
// both, and do nothing else — no queue, no spill, no silent swallow.
function surface(ctx: ExtensionContext, err: unknown): void {
  const message = err instanceof Error ? err.message : String(err);
  const label = err instanceof FunesUnreachable ? "funes unreachable" : "funes error";
  ctx.ui.setStatus(STATUS_KEY, `${label}: ${message}`);
  ctx.ui.notify(`${label}: ${message}`, "error");
}
