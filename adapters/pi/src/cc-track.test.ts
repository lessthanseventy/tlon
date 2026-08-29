import { describe, expect, test } from "bun:test";
import { shouldTrack } from "./cc-track.ts";

describe("shouldTrack — the PostToolUse gate for auto-tracking (reshape slice B)", () => {
  test("a successful Bash git commit tracks", () => {
    expect(shouldTrack({ tool_name: "Bash", tool_input: { command: "git commit -m 'x'" } })).toBe(true);
    expect(
      shouldTrack({
        tool_name: "Bash",
        tool_input: { command: "git add -A && git commit -F msg" },
        tool_response: { stdout: "[main abc123] x" },
      }),
    ).toBe(true);
  });

  test("non-Bash tools and non-commit commands do not", () => {
    expect(shouldTrack({ tool_name: "Edit", tool_input: { command: "git commit" } })).toBe(false);
    expect(shouldTrack({ tool_name: "Bash", tool_input: { command: "git status" } })).toBe(false);
    expect(shouldTrack({ tool_name: "Bash" })).toBe(false);
    expect(shouldTrack({})).toBe(false);
  });

  test("cc's real Bash response shapes: interrupt and git refusals do not track", () => {
    const base = { tool_name: "Bash", tool_input: { command: "git commit -m x" } };
    expect(shouldTrack({ ...base, tool_response: { stdout: "", stderr: "", interrupted: true } })).toBe(false);
    expect(
      shouldTrack({ ...base, tool_response: { stdout: "nothing to commit, working tree clean", stderr: "" } }),
    ).toBe(false);
    expect(shouldTrack({ ...base, tool_response: { stdout: "", stderr: "fatal: not a git repository" } })).toBe(false);
    expect(shouldTrack({ ...base, tool_response: { stdout: "", stderr: "pre-commit hook failed" } })).toBe(false);
    expect(shouldTrack({ ...base, tool_response: { stdout: "[main abc1234] fix", stderr: "" } })).toBe(true);
    // A commit SUBJECT containing "error:" echoes into stdout — must still track.
    expect(
      shouldTrack({ ...base, tool_response: { stdout: "[main abc1234] fix: error: handling in parser", stderr: "" } }),
    ).toBe(true);
  });

  test("a response that reads as failure does not track", () => {
    expect(
      shouldTrack({
        tool_name: "Bash",
        tool_input: { command: "git commit -m x" },
        tool_response: { is_error: true },
      }),
    ).toBe(false);
    expect(
      shouldTrack({
        tool_name: "Bash",
        tool_input: { command: "git commit -m x" },
        tool_response: { success: false },
      }),
    ).toBe(false);
  });
});
