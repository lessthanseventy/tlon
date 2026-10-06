import { test, expect } from "bun:test";
import { verbOf } from "./cc-presence";

// The hook's whole argv contract: an explicit "idle" clears, anything else (including the bare
// UserPromptSubmit invocation) declares thinking.
test("verbOf: bare invocation declares thinking; explicit idle clears", () => {
  expect(verbOf(["bun", "cc-presence.ts"])).toBe("thinking");
  expect(verbOf(["bun", "cc-presence.ts", "thinking"])).toBe("thinking");
  expect(verbOf(["bun", "cc-presence.ts", "idle"])).toBe("idle");
  expect(verbOf(["bun", "cc-presence.ts", "garbage"])).toBe("thinking");
});

// SessionStart registers the session, as pi's extension does at its session_start — without it a
// Claude Code worker had no session row, so the roster, warmth and thinking never saw it.
test("verbOf: start registers", () => {
  expect(verbOf(["bun", "cc-presence.ts", "start"])).toBe("start");
});

test("verbOf: doing reports the PreToolUse hook's tool", () => {
  expect(verbOf(["bun", "cc-presence.ts", "doing"])).toBe("doing");
});
