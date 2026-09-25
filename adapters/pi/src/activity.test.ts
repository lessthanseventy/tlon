import { describe, expect, test } from "bun:test";
import type { Entry } from "./activity.ts";

describe("isCommitCommand — a real `git … commit` invocation (reshape slice B)", async () => {
  const { isCommitCommand } = await import("./activity.ts");

  test("plain and flagged commit forms match", () => {
    expect(isCommitCommand("git commit -m 'fix'")).toBe(true);
    expect(isCommitCommand("git -C /repo commit --amend")).toBe(true);
    expect(isCommitCommand("git add -A && git commit -F msg.txt")).toBe(true);
    expect(isCommitCommand("cd x; git commit -m x")).toBe(true);
  });

  test("commit as a mere word does not match", () => {
    expect(isCommitCommand("git log --oneline | grep commit")).toBe(false);
    expect(isCommitCommand("grep -rn commit lib/")).toBe(false);
    expect(isCommitCommand("git status")).toBe(false);
    expect(isCommitCommand("mix test")).toBe(false);
  });

  test("commit inside a flag's VALUE does not match (the backtracking hole)", () => {
    expect(isCommitCommand("git -c commit.gpgsign=false push")).toBe(false);
    expect(isCommitCommand("git -c commit.gpgsign=false commit -m x")).toBe(true);
  });
});

describe("sawSuccessfulCommit — a bash toolCall with a non-error toolResult (pi's NATIVE shape)", async () => {
  const { sawSuccessfulCommit } = await import("./activity.ts");

  // Fabricated to pi-ai's real Message types (toolCall blocks + whole toolResult messages) —
  // a review caught an earlier cut fabricating the Anthropic wire format instead, which made
  // the detector pass its tests while matching nothing live.
  const bashCall = (id: string, command: string): Entry => ({
    message: { role: "assistant", content: [{ type: "toolCall", id, name: "bash", arguments: { command } }] },
  });
  const result = (toolCallId: string, isError = false): Entry =>
    ({ message: { role: "toolResult", toolCallId, isError, content: [] } }) as Entry;

  test("commit + ok result → true", () => {
    expect(sawSuccessfulCommit([bashCall("t1", "git commit -m x"), result("t1")])).toBe(true);
  });

  test("commit whose result errored → false", () => {
    expect(sawSuccessfulCommit([bashCall("t1", "git commit -m x"), result("t1", true)])).toBe(false);
  });

  test("non-commit tools and other results → false", () => {
    expect(sawSuccessfulCommit([bashCall("t1", "mix test"), result("t1")])).toBe(false);
    expect(sawSuccessfulCommit([bashCall("t1", "git commit -m x"), result("t9")])).toBe(false);
    expect(sawSuccessfulCommit([])).toBe(false);
  });
});
