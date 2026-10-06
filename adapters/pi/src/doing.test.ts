import { expect, test } from "bun:test";
import { doingOf } from "./doing.ts";

test("pi's built-in tools and Claude Code's map to the same kinds", () => {
  expect(doingOf("read", {})).toBe("read");
  expect(doingOf("Read", {})).toBe("read");
  expect(doingOf("edit", {})).toBe("edit");
  expect(doingOf("MultiEdit", {})).toBe("edit");
  expect(doingOf("write", {})).toBe("edit");
  expect(doingOf("grep", {})).toBe("search");
  expect(doingOf("Glob", {})).toBe("search");
  expect(doingOf("WebFetch", {})).toBe("web");
  expect(doingOf("WebSearch", {})).toBe("web");
  expect(doingOf("Agent", {})).toBe("delegate");
  expect(doingOf("bash", { command: "ls -la" })).toBe("bash");
});

test("a shell command that runs a suite or a gate is a test", () => {
  expect(doingOf("bash", { command: "mise run check" })).toBe("test");
  expect(doingOf("Bash", { command: "cd server && mix test test/foo_test.exs" })).toBe("test");
  expect(doingOf("bash", { command: "bun test src" })).toBe("test");
  expect(doingOf("bash", { command: "git checkout main" })).toBe("bash");
});

test("an MCP tool is read by its own name, and an unknown tool is plain thinking", () => {
  expect(doingOf("mcp__tlon__consult_peer", {})).toBe("delegate");
  expect(doingOf("mcp__menard__edit_clause", {})).toBe("edit");
  expect(doingOf("mcp__tlon__get_brief", {})).toBe("read");
  expect(doingOf("TodoWrite", {})).toBeUndefined();
});
