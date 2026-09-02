// adapters — the claude-code adapter's thinking-presence declare. claude-machine has no
// persistent extension process, so each hook fire is a fresh bun process (same shape as
// cc-capture.ts): UserPromptSubmit declares thinking, Stop/SessionEnd declare idle — the
// verb rides argv. Reuses mcp.ts's FunesClient; identity is the TLON_* env, the tools are
// argless self-thread declares.
//
// Same failure discipline as the other hooks: funes down, no identity, a slow connect —
// all silent no-ops, hard-bounded so a wedged connect can never hold the session's hook.

import { argv } from "node:process";
import { FunesClient, identityFromEnv } from "./mcp.ts";

// Presence is a per-turn nicety; a declare that can't land fast isn't worth waiting on.
const HOOK_TIMEOUT_MS = 5_000;

// The declare verb from the hook's argv — anything but an explicit "idle" means thinking,
// so a bare invocation (the UserPromptSubmit wiring) does the common thing.
export function verbOf(args: string[]): "thinking" | "idle" {
  return args[2] === "idle" ? "idle" : "thinking";
}

async function declare(): Promise<void> {
  const identity = identityFromEnv();
  if (!identity) return;

  const client = new FunesClient(identity);
  await client.connect();
  if (verbOf(argv) === "idle") {
    await client.presenceIdle();
  } else {
    await client.presenceThinking();
  }
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main(): Promise<void> {
  try {
    await Promise.race([declare(), delay(HOOK_TIMEOUT_MS)]);
  } catch {
    // silent no-op — a presence hook must never surface a failure or break the session
  }
}

if (import.meta.main) {
  main().finally(() => process.exit(0));
}
