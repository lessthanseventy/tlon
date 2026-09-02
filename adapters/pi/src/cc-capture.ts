// adapters — the claude-code adapter's capture reflex (one-ledger Cut 1, Task 4). claude-machine
// has no persistent extension process the way pi does; a Claude Code Stop hook is a fresh bun
// process per turn, fed the turn's transcript on stdin and nothing else. This module reuses
// capture.ts's PURE core (delta-slicing, redaction, prompt, tolerant parse) and mcp.ts's
// FunesClient exactly as pi's extension.ts does — the only new code here is (1) parseTranscript,
// which turns Claude Code's JSONL transcript into the same Entry[] shape capture.ts already
// consumes, and (2) a per-session watermark FILE, since there's no long-lived closure to hold one
// across turns the way pi's extension does.
//
// Same failure discipline as extension.ts: funes down, no identity, a bad completion, an
// unparseable transcript — all silent no-ops. A Stop hook's stdout/stderr never surface to the
// operator by default, but silence is the contract regardless: this must never be the reason a
// session looks broken.

import { env } from "node:process";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import {
  buildExtractionPrompt,
  deltaSince,
  DEFAULT_CAPTURE_MODEL,
  parseExtraction,
  redactSecrets,
  serializeDelta,
  type Entry,
} from "./capture.ts";
import { completeText } from "./llm.ts";
import { FunesClient } from "./mcp.ts";

// A hung completion or a wedged funes connection must never keep the hook process alive past the
// turn — bound the whole capture with a hard ceiling and let the process exit regardless.
const HOOK_TIMEOUT_MS = 45_000;

// A cadence floor, since a Claude Code Stop hook fires EVERY turn (pi batches ~every 8) — roughly a
// couple of substantive turns' worth of transcript. Below it, we accumulate rather than pay for a
// per-turn extraction. The watermark is deliberately NOT advanced under the floor (unlike the
// empty-delta path): the next Stop re-includes this delta plus the new turn's content, growing it
// until it clears the floor; capture.ts's MAX_DELTA_CHARS backstops the growth.
const MIN_DELTA_CHARS = 2_000;

interface StopHookInput {
  session_id?: string;
  transcript_path?: string;
}

// Claude Code's transcript is JSONL; each line is a session-record object, most of which carry a
// `message: { role, content }` in the exact shape capture.ts's Entry already expects (content is
// a string or an array of {type:"text",text} blocks — extractText inside capture.ts handles both).
// Lines with no message (tool-result records, meta records) or that fail to parse are skipped —
// tolerant by design, since a hook must never throw on transcript shapes it doesn't recognize.
export function parseTranscript(jsonlText: string): Entry[] {
  const entries: Entry[] = [];
  for (const line of jsonlText.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    let parsed: unknown;
    try {
      parsed = JSON.parse(trimmed);
    } catch {
      continue;
    }
    if (!parsed || typeof parsed !== "object") continue;
    const message = (parsed as { message?: unknown }).message;
    if (!message || typeof message !== "object") continue;
    const role = (message as { role?: unknown }).role;
    const content = (message as { content?: unknown }).content;
    entries.push({ message: { role: typeof role === "string" ? role : undefined, content } });
  }
  return entries;
}

function stateFilePath(sessionId: string): string {
  const stateHome = env.XDG_STATE_HOME?.trim() || join(homedir(), ".local/state");
  return join(stateHome, "tlon-cc-capture", sessionId);
}

async function readWatermark(path: string): Promise<number> {
  try {
    const raw = (await readFile(path, "utf-8")).trim();
    const n = Number.parseInt(raw, 10);
    return Number.isInteger(n) && n >= 0 ? n : 0;
  } catch {
    return 0;
  }
}

async function writeWatermark(path: string, watermark: number): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, String(watermark), "utf-8");
}

// The IO/orchestration core (deliberately not unit-tested — same split as extension.ts vs
// capture.ts: this talks to the filesystem, the network, and completeText; nothing here is pure).
async function capture(): Promise<void> {
  const url = env.TLON_MCP_URL;
  const threadEnv = env.TLON_THREAD;
  const agent = env.TLON_AUTHOR;
  if (!url || !threadEnv || !agent) return;
  const threadId = Number(threadEnv);
  if (!Number.isInteger(threadId)) return;

  const stdinText = await Bun.stdin.text();
  let hookInput: StopHookInput;
  try {
    hookInput = JSON.parse(stdinText) as StopHookInput;
  } catch {
    return;
  }
  const sessionId = hookInput.session_id;
  const transcriptPath = hookInput.transcript_path;
  if (!sessionId || !transcriptPath) return;

  let jsonlText: string;
  try {
    jsonlText = await readFile(transcriptPath, "utf-8");
  } catch {
    return;
  }
  const entries = parseTranscript(jsonlText);

  const path = stateFilePath(sessionId);
  const watermark = await readWatermark(path);
  const { slice, nextWatermark } = deltaSince(entries, watermark);
  const delta = redactSecrets(serializeDelta(slice));
  if (!delta.trim()) {
    // Nothing new to capture — advance the watermark so an idle stretch of tool-only turns
    // doesn't get re-scanned next time (mirrors extension.ts's runCapture).
    await writeWatermark(path, nextWatermark).catch(() => {});
    return;
  }

  // Below the cadence floor: accumulate. Do NOT advance the watermark — the next Stop re-includes
  // this delta plus new content, so nothing is dropped mid-session; we just haven't paid for an
  // extraction yet (capture.ts's MAX_DELTA_CHARS backstops unbounded growth).
  if (delta.length < MIN_DELTA_CHARS) return;

  // Extraction is the make-or-break for the watermark (mirrors extension.ts: the watermark
  // advances once extraction succeeds, regardless of individual bank outcomes below — a failed
  // extraction is what retries the same delta next turn, not a rejected fact).
  let facts;
  try {
    const raw = await completeText(DEFAULT_CAPTURE_MODEL, buildExtractionPrompt(delta));
    ({ facts } = parseExtraction(raw));
  } catch {
    return;
  }

  try {
    const client = new FunesClient({ url, threadId, agent });
    await client.connect();
    for (const f of facts) {
      try {
        await client.bankFact(f.text, f.kind, f.intent);
      } catch {
        // a rejected fact (e.g. a secret) is dropped, never retried
      }
    }
  } catch {
    // funes unreachable/rejected the connection — this pass banked nothing, but the extraction
    // itself succeeded, so the watermark still advances below (same discipline as extension.ts).
  }

  await writeWatermark(path, nextWatermark).catch(() => {});
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main(): Promise<void> {
  try {
    // If the ceiling wins the race mid-bank, capture()'s writeWatermark never runs, so the same
    // delta re-extracts and re-banks next turn — a rare duplicate-fact tradeoff we accept over the
    // alternative (letting a hung completion wedge the session). funes dedups on promotion anyway.
    await Promise.race([capture(), delay(HOOK_TIMEOUT_MS)]);
  } catch {
    // silent no-op — a Stop hook must never surface a failure or break the session
  }
}

if (import.meta.main) {
  main().finally(() => process.exit(0));
}
