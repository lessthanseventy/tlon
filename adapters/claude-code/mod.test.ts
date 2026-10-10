import { expect, test } from "claude-code/testing";

type Declare = { tool: string; args: Record<string, unknown> };

// What Claude Code itself answers beneath the plugins.
function engine(on) {
  on("session.start", ($, e) => ({ cwd: e.cwd }));
  on("turn.start", ($, e) => ({ turnId: e.turnId }));
  on("ui.status", () => ({ value: undefined }));
  on("turn.complete", ($, e) => ({ text: e.answer }));
}

function citizen(on, env: Record<string, string>): Declare[] {
  const sent: Declare[] = [];
  engine(on);
  on("env.get", ($, e) => ({ value: env[e.name] }));
  on("mcp.call", ($, e) => {
    sent.push({ tool: e.tool, args: e.args ?? {} });
    return { value: { content: [], isError: false } };
  });
  on("tool.call", () => ({ result: "ok" }));
  return sent;
}

const TURN_END = { answer: "", durationMs: 1, isAborted: false, turnId: "t1", reason: "answer" };
const IDENTITY = { TLON_THREAD: "42", TLON_AUTHOR: "claude-code", TMUX_PANE: "%7" };

test("a citizen registers, then declares thinking, each tool, and idle, in order", async ($, on) => {
  const sent = citizen(on, IDENTITY);

  await $.session.start({ cwd: "/repo", surface: null, isInteractive: false });
  await $.turn.start({ text: "run the gate", turnId: "t1" });
  await $.tool.call({ tool: "Bash", command: "mise run check" });
  await $.tool.call({ tool: "Read", file_path: "/repo/lib/x.ex" });
  await $.turn.complete({ ...TURN_END, agentId: "sub-1" });
  await $.turn.complete(TURN_END);

  expect(sent).toEqual([
    { tool: "register", args: { pane_ref: "%7" } },
    { tool: "presence_thinking", args: {} },
    { tool: "presence_doing", args: { what: "test", summary: "Bash · mise run check" } },
    { tool: "presence_doing", args: { what: "read", summary: "Read · lib/x.ex" } },
    { tool: "presence_idle", args: {} },
  ]);
});

test("a plain claude, with no tlon identity, declares nothing", async ($, on) => {
  const sent = citizen(on, {});

  await $.session.start({ cwd: "/repo", surface: null, isInteractive: false });
  await $.tool.call({ tool: "Bash", command: "ls" });

  expect(sent).toEqual([]);
});

test("a down server never holds the tool", async ($, on) => {
  engine(on);
  on("env.get", ($, e) => ({ value: IDENTITY[e.name] }));
  on("mcp.call", () => {
    throw new Error("connection refused");
  });
  on("tool.call", () => ({ result: "ran" }));

  await $.session.start({ cwd: "/repo", surface: null, isInteractive: false });
  const r = await $.tool.call({ tool: "Bash", command: "ls" });

  expect(r.result).toBe("ran");
});
