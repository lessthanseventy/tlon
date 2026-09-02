// adapters — the claude-code adapter's thinking-presence declare. claude-machine has no
// persistent extension process, so each hook fire is a fresh bun process (same shape as
// cc-capture.ts): UserPromptSubmit declares thinking, Stop/SessionEnd declare idle — the
// verb rides argv. Reuses mcp.ts's TlonClient; identity is the TLON_* env, the tools are
// argless self-thread declares.
//
// Same failure discipline as the other hooks: the server down, no identity, a slow connect —
// all silent no-ops, hard-bounded so a wedged connect can never hold the session's hook.

import { argv } from "node:process";
import { runHook } from "./hook.ts";
import { TlonClient, identityFromEnv } from "./mcp.ts";

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

  const client = new TlonClient(identity);
  await client.connect();
  if (verbOf(argv) === "idle") {
    await client.presenceIdle();
  } else {
    await client.presenceThinking();
  }
}

if (import.meta.main) {
  runHook(declare, HOOK_TIMEOUT_MS).finally(() => process.exit(0));
}
