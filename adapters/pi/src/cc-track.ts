// adapters — the claude-code adapter's auto-track hook (reshape slice B). Claude Code has
// no persistent extension process like pi's, so a PostToolUse hook is a fresh bun process per
// tool call. When the tool call that just finished was a successful
// `git … commit`, this connection's thread promotes into the stage machine via `track_thread` —
// the ticket condenses out of the work. The server is idempotent, so firing on every commit is
// safe; no state file needed.
//
// Same failure discipline as the sibling hooks: the server down, no identity, an unparseable
// payload — all silent no-ops. A PostToolUse hook must never block or break a tool call.

import { isCommitCommand } from "./activity.ts";
import { readHookInput, runHook } from "./hook.ts";
import { TlonClient, identityFromEnv } from "./mcp.ts";

const HOOK_TIMEOUT_MS = 10_000;

export interface PostToolUseInput {
  tool_name?: string;
  tool_input?: unknown;
  tool_response?: unknown;
}

// The pure gate: a Bash tool call whose command is a commit invocation and whose response does
// not read as a failure. Claude Code's Bash tool_response is `{stdout, stderr, interrupted, …}`
// with no single error flag, so failure is inferred: an interrupt, an explicit flag where one
// exists, or a stderr that names a git refusal. A wrong promote is NOT harmless (there is no
// demote verb — a thread where nothing landed would be staged "build" forever), so refusal
// shapes are checked first; only then does an unmarked response count as success.
const FAILURE_STDERR = /nothing to commit|fatal:|error:|rejected|hook failed|no changes added/i;
// stdout gets ANCHORED refusal shapes only — a successful commit's subject line echoes into
// stdout, so a commit titled "fix: error: handling" must not read as a failure.
const FAILURE_STDOUT = /^(nothing to commit|no changes added|On branch .*\nnothing to commit)/m;

export function shouldTrack(input: PostToolUseInput): boolean {
  if (input.tool_name !== "Bash") return false;
  const cmd = (input.tool_input as Record<string, unknown> | null)?.["command"];
  if (typeof cmd !== "string" || !isCommitCommand(cmd)) return false;
  const response = input.tool_response as Record<string, unknown> | null;
  if (!response) return true;
  if (response["is_error"] === true || response["success"] === false) return false;
  if (response["interrupted"] === true) return false;
  const stderr = response["stderr"];
  if (typeof stderr === "string" && FAILURE_STDERR.test(stderr)) return false;
  const stdout = response["stdout"];
  if (typeof stdout === "string" && FAILURE_STDOUT.test(stdout)) return false;
  return true;
}

async function track(): Promise<void> {
  const identity = identityFromEnv();
  if (!identity) return;

  const hookInput = await readHookInput<PostToolUseInput>();
  if (!hookInput || !shouldTrack(hookInput)) return;

  const client = new TlonClient(identity);
  await client.connect();
  await client.trackThread();
}

if (import.meta.main) {
  runHook(track, HOOK_TIMEOUT_MS).finally(() => process.exit(0));
}
