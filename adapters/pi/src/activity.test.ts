import { describe, expect, test } from "bun:test";
import {
  buildHeartbeatPrompt,
  fallbackLine,
  formatDuration,
  heartbeatDue,
  lastToolActivity,
  nextHeartbeatState,
  phraseHeartbeat,
  type Entry,
} from "./activity.ts";

const asstText = (text: string): Entry => ({ message: { role: "assistant", content: [{ type: "text", text }] } });
const toolUse = (name: string, input?: unknown): Entry => ({
  message: { role: "assistant", content: [{ type: "tool_use", name, input }] },
});

describe("lastToolActivity — the mechanical signal, no LLM involved", () => {
  test("no entries yet → undefined", () => {
    expect(lastToolActivity([])).toBeUndefined();
  });

  test("entries with no tool_use block → undefined", () => {
    expect(lastToolActivity([asstText("just thinking out loud")])).toBeUndefined();
  });

  test("finds the most recent tool_use, scanning from the end", () => {
    const entries = [toolUse("Read", { file_path: "/a.ex" }), toolUse("Bash", { command: "mix test" })];
    expect(lastToolActivity(entries)).toEqual({ name: "Bash", detail: "mix test" });
  });

  test("pulls the first recognized detail field (command over file_path)", () => {
    expect(lastToolActivity([toolUse("Bash", { command: "mix test", file_path: "/a.ex" })])).toEqual({
      name: "Bash",
      detail: "mix test",
    });
  });

  test("no recognized detail field → name only, no crash on odd input shapes", () => {
    expect(lastToolActivity([toolUse("Glob", { weird_key: 1 })])).toEqual({ name: "Glob", detail: undefined });
    expect(lastToolActivity([toolUse("NoInput")])).toEqual({ name: "NoInput", detail: undefined });
  });

  test("a long detail truncates rather than blowing up the message", () => {
    const long = "x".repeat(200);
    const got = lastToolActivity([toolUse("Bash", { command: long })]);
    expect(got?.detail?.length).toBeLessThan(90);
    expect(got?.detail?.endsWith("…")).toBe(true);
  });
});

describe("formatDuration — sub-minute-precise, mirrors the console-side Console.Text.duration/1", () => {
  test("under a minute is bare seconds", () => {
    expect(formatDuration(0)).toBe("0s");
    expect(formatDuration(45)).toBe("45s");
  });

  test("a minute or more is Mm Ss", () => {
    expect(formatDuration(60)).toBe("1m0s");
    expect(formatDuration(192)).toBe("3m12s");
  });

  test("an hour or more drops seconds", () => {
    expect(formatDuration(3_900)).toBe("1h5m");
  });

  test("negative clamps to 0s", () => {
    expect(formatDuration(-5)).toBe("0s");
  });
});

describe("fallbackLine — the never-silent mechanical line when the sidecar can't phrase one", () => {
  test("no activity yet", () => {
    expect(fallbackLine(undefined, 30)).toBe("still on it (30s)");
  });

  test("activity with a detail", () => {
    expect(fallbackLine({ name: "Bash", detail: "mix test" }, 192)).toBe("still on it (3m12s) — Bash: mix test");
  });

  test("activity with no detail", () => {
    expect(fallbackLine({ name: "Read" }, 5)).toBe("still on it (5s) — Read");
  });
});

describe("buildHeartbeatPrompt — pins the sidecar contract (short, plain, no questions)", () => {
  test("names the elapsed time and current activity, constrains the output shape", () => {
    const p = buildHeartbeatPrompt({ name: "Bash", detail: "mix test" }, 192);
    expect(p).toContain("3m12s");
    expect(p).toContain("Bash");
    expect(p).toContain("mix test");
    expect(p).toContain("ONE short");
    expect(p).toContain("no questions");
    expect(p).toContain("no markdown");
  });

  test("no activity yet reads as getting started, not a crash on undefined", () => {
    expect(buildHeartbeatPrompt(undefined, 5)).toContain("getting started");
  });
});

describe("phraseHeartbeat — the sidecar call, mechanical fallback on any hiccup", () => {
  test("uses the sidecar's phrasing, trimmed to its first line", async () => {
    const complete = async () => "  still chasing down that flaky test, hang tight  \nextra";
    const line = await phraseHeartbeat({ name: "Bash", detail: "mix test" }, 30, complete);
    expect(line).toBe("still chasing down that flaky test, hang tight");
  });

  test("an empty completion falls back to the mechanical line", async () => {
    const complete = async () => "   ";
    const line = await phraseHeartbeat({ name: "Bash", detail: "mix test" }, 30, complete);
    expect(line).toBe(fallbackLine({ name: "Bash", detail: "mix test" }, 30));
  });

  test("a throwing completion (sidecar unreachable) falls back — never silent", async () => {
    const complete = async () => {
      throw new Error("OLLAMA_API_KEY not set");
    };
    const line = await phraseHeartbeat(undefined, 5, complete);
    expect(line).toBe(fallbackLine(undefined, 5));
  });
});

// Claude Code's PostToolUse fires a fresh process every tool call (no long-lived closure like
// pi's extension) — this is the cadence gate a state file persists across those calls: "how long
// since the turn started" and "how long since the last heartbeat post" collapse to one `anchor`.
describe("nextHeartbeatState / heartbeatDue — the cross-process cadence gate (Claude Code side)", () => {
  test("no prior state → a fresh turn, anchored to now", () => {
    expect(nextHeartbeatState(null, 1_000, 600_000)).toEqual({ turnStartedAt: 1_000, anchor: 1_000 });
  });

  test("prior state within the reset window → carries turnStartedAt, anchors on the last post", () => {
    const prior = { turnStartedAt: 500, lastPostAt: 900 };
    expect(nextHeartbeatState(prior, 1_000, 600_000)).toEqual({ turnStartedAt: 500, anchor: 900 });
  });

  test("prior state past the reset window (long idle gap) → treated as a fresh turn", () => {
    const prior = { turnStartedAt: 500, lastPostAt: 900 };
    expect(nextHeartbeatState(prior, 900 + 600_001, 600_000)).toEqual({
      turnStartedAt: 900 + 600_001,
      anchor: 900 + 600_001,
    });
  });

  test("heartbeatDue: not yet at the interval → false; at or past it → true", () => {
    expect(heartbeatDue(1_000, 1_000 + 44_999, 45_000)).toBe(false);
    expect(heartbeatDue(1_000, 1_000 + 45_000, 45_000)).toBe(true);
  });
});

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
