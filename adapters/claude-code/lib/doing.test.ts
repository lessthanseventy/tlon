import { expect, test } from "bun:test";
import { doingOf, summaryOf } from "./doing.ts";

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

// The activity feed's line (`presence_doing`'s summary): the tool and its target, never contents.
test("a Claude Code PreToolUse names the tool and its target", () => {
  const cwd = "/home/me/repo";
  expect(summaryOf("Bash", { command: "mise run check", description: "the gate" }, cwd)).toBe("Bash · mise run check");
  expect(summaryOf("Read", { file_path: "/home/me/repo/lib/server/ticket.ex" }, cwd)).toBe("Read · lib/server/ticket.ex");
  expect(summaryOf("Edit", { file_path: "/home/me/repo/office/kit/crew.ts", old_string: "SECRET BODY", new_string: "x" }, cwd)).toBe("Edit · office/kit/crew.ts");
  expect(summaryOf("Write", { file_path: "/elsewhere/a.md", content: "the whole file" }, cwd)).toBe("Write · /elsewhere/a.md");
  expect(summaryOf("Grep", { pattern: "def thread_view", path: "server" }, cwd)).toBe("Grep · def thread_view");
  expect(summaryOf("WebFetch", { url: "https://hexdocs.pm/ecto", prompt: "what is it" }, cwd)).toBe("WebFetch · https://hexdocs.pm/ecto");
  expect(summaryOf("Agent", { description: "find the hook", prompt: "a long brief" }, cwd)).toBe("Agent · find the hook");
  expect(summaryOf("mcp__tlon__post_message", { body: "hi" }, cwd)).toBe("post_message");
});

test("a pi tool call reads the same way", () => {
  const cwd = "/w";
  expect(summaryOf("bash", { command: "bun test src" }, cwd)).toBe("Bash · bun test src");
  expect(summaryOf("read", { path: "/w/src/doing.ts" }, cwd)).toBe("Read · src/doing.ts");
  expect(summaryOf("edit", { path: "src/doing.ts", oldText: "a", newText: "b" }, cwd)).toBe("Edit · src/doing.ts");
});

test("a summary is one line, capped, and redacts anything credential-shaped", () => {
  const s = (command: string) => summaryOf("Bash", { command }, "/");
  expect(s("echo a\necho b")).toBe("Bash · echo a ⏎ echo b");
  expect(s("curl -H 'Authorization: Bearer abc.def-123' https://x")).not.toContain("abc.def-123");
  expect(s("OLLAMA_API_KEY=sk-live1234567890abcdef pi")).toBe("Bash · OLLAMA_API_KEY=… pi");
  expect(s("gh auth login --with-token ghp_abcdefghijklmnop1234")).not.toContain("ghp_abcdefghijklmnop1234");
  expect(s("x".repeat(500)).length).toBeLessThanOrEqual(120);
});
