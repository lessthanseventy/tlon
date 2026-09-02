// adapters — the claude-code adapter's heartbeat (thread #3, 2026-08-27). Same problem as
// cc-capture.ts/cc-presence.ts solve for facts/presence: claude-machine has no persistent
// extension process the way pi does, so a PostToolUse hook is a fresh bun process per tool call.
// Where pi's extension.ts arms a setInterval for the turn's duration, this hook re-derives "is a
// heartbeat due" from a per-session state FILE every time it fires — the cadence gate
// (nextHeartbeatState/heartbeatDue) and the message-building (activityFrom/phraseHeartbeat) are
// activity.ts's pure core, shared verbatim with pi's side so the two harnesses never drift.
//
// Same failure discipline as the other hooks: the server down, no identity, an unparseable payload —
// all silent no-ops. A PostToolUse hook must never be why a session looks broken or a tool call
// stalls waiting on it.

import { env } from "node:process";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { activityFrom, heartbeatDue, nextHeartbeatState, phraseHeartbeat, type HeartbeatState } from "./activity.ts";
import { readHookInput, runHook } from "./hook.ts";
import { completeText } from "./llm.ts";
import { TlonClient, identityFromEnv } from "./mcp.ts";

// A hook must never wedge a tool call — the sidecar phrasing call gets a real budget (it's the
// deliverable, unlike capture's best-effort extraction), but the whole hook still has a ceiling.
const HOOK_TIMEOUT_MS = 30_000;

// The cadence — same interval as pi's side (extension.ts's HEARTBEAT_INTERVAL_MS), kept in sync
// by convention (both read "how often should a coworker check in") rather than a shared import,
// since the two live in different processes with different lifetimes.
const MIN_INTERVAL_MS = 45_000;

// A gap this long since the last post reads as a new turn (or the session sat idle) — see
// activity.ts's nextHeartbeatState doc.
const TURN_RESET_MS = 10 * 60_000;

interface PostToolUseInput {
  session_id?: string;
  tool_name?: string;
  tool_input?: unknown;
}

function stateFilePath(sessionId: string): string {
  const stateHome = env.XDG_STATE_HOME?.trim() || join(homedir(), ".local/state");
  return join(stateHome, "tlon-cc-heartbeat", sessionId);
}

async function readState(path: string): Promise<HeartbeatState | null> {
  try {
    const parsed = JSON.parse(await readFile(path, "utf-8")) as Partial<HeartbeatState>;
    if (typeof parsed.turnStartedAt === "number" && typeof parsed.lastPostAt === "number") {
      return { turnStartedAt: parsed.turnStartedAt, lastPostAt: parsed.lastPostAt };
    }
    return null;
  } catch {
    return null;
  }
}

async function writeState(path: string, state: HeartbeatState): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, JSON.stringify(state), "utf-8");
}

// The IO/orchestration core (deliberately not unit-tested — same split as cc-capture.ts's
// capture(): this talks to the filesystem, the network, and completeText; the decision math and
// message-building it calls into are what's pure and pinned, in activity.ts).
async function heartbeat(): Promise<void> {
  const identity = identityFromEnv();
  if (!identity) return;

  const hookInput = await readHookInput<PostToolUseInput>();
  if (!hookInput?.session_id || !hookInput.tool_name) return;

  const path = stateFilePath(hookInput.session_id);
  const now = Date.now();
  const prior = await readState(path);
  const { turnStartedAt, anchor } = nextHeartbeatState(prior, now, TURN_RESET_MS);

  if (!heartbeatDue(anchor, now, MIN_INTERVAL_MS)) {
    // Not due — persist the (possibly just-reset) turnStartedAt/anchor so the next call picks up
    // where this one left off, but no post, no sidecar call, no network beyond that.
    await writeState(path, { turnStartedAt, lastPostAt: anchor }).catch(() => {});
    return;
  }

  const activity = activityFrom(hookInput.tool_name, hookInput.tool_input);
  const elapsedSeconds = (now - turnStartedAt) / 1000;
  const line = await phraseHeartbeat(activity, elapsedSeconds, completeText);

  try {
    const client = new TlonClient(identity);
    await client.connect();
    await client.postMessage(line);
  } catch {
    // the server unreachable — this beat is dropped; the next due PostToolUse call retries
  }

  await writeState(path, { turnStartedAt, lastPostAt: now }).catch(() => {});
}

if (import.meta.main) {
  runHook(heartbeat, HOOK_TIMEOUT_MS).finally(() => process.exit(0));
}
