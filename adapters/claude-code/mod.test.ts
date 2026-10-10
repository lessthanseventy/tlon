import { expect, test } from "claude-code/testing";

type Declare = { tool: string; args: Record<string, unknown> };
type Fetch = (e: { url: string; init: { body: string } }) => { status: number; ok: boolean; headers: Record<string, string>; text: string };
type World = {
  env?: Record<string, string>;
  dossier?: unknown;
  transcript?: { role: string; text: string }[];
  fetch?: Fetch;
  run?: (argv: string[], init?: { env?: Record<string, string> }) => { exitCode: number; stdout: string; stderr: string };
  model?: string;
  serverDown?: boolean;
};

const IDENTITY = { TLON_THREAD: "42", TLON_AUTHOR: "claude-code", TMUX_PANE: "%7", OLLAMA_API_KEY: "k" };
const NONE = { shown: [], more: 0 };
const DOSSIER = { thread_id: 42, goal: "ship the mod", lead: "claude-code", todos: NONE, next: null, learnings: NONE, unknowns: NONE, done: NONE, blockers: NONE, checks: NONE, recent: [] };
const TURN_END = { answer: "", durationMs: 1, isAborted: false, turnId: "t1", reason: "answer" };
const START = { cwd: "/repo", surface: null, isInteractive: false };

// What Claude Code and the tlon server answer beneath the plugins; returns every tlon call made.
function engine(on, world: World = {}): Declare[] {
  const env = world.env ?? IDENTITY;
  const sent: Declare[] = [];
  on("session.start", ($, e) => ({ cwd: e.cwd }));
  on("session.end", ($, e) => ({ sessionId: e.sessionId }));
  on("turn.start", ($, e) => ({ turnId: e.turnId }));
  on("turn.complete", ($, e) => ({ text: e.answer }));
  on("prompt.submit", ($, e) => ({ text: e.text, context: e.context }));
  on("tool.call", () => ({ result: "ok" }));
  on("env.get", ($, e) => ({ value: env[e.name] }));
  on("clock.every", () => ({ value: undefined }));
  on("command.register", () => ({ value: undefined }));
  on("tool.register", () => ({ value: undefined }));
  on("fs.read", () => {
    throw new Error("no such file");
  });
  on("process.run", ($, e) => ({
    value: { isStdoutTruncated: false, isStderrTruncated: false, ...(world.run ?? (() => ({ exitCode: 1, stdout: "", stderr: "no run" })))(e.argv, e.init) },
  }));
  on("ui.invalidate", () => ({ value: undefined }));
  on("ui.toast", () => ({ value: undefined }));
  on("session.model", () => ({ value: world.model ?? "glm-5.2" }));
  on("session.messages", () => ({ value: (world.transcript ?? []).map((m) => ({ ...m, toolUses: [] })) }));
  on("http.fetch", ($, e) => ({ value: (world.fetch ?? (() => ({ status: 500, ok: false, headers: {}, text: "" })))(e) }));
  on("mcp.call", ($, e) => {
    if (world.serverDown) throw new Error("connection refused");
    sent.push({ tool: e.tool, args: e.args ?? {} });
    const text = e.tool === "get_dossier" ? JSON.stringify(world.dossier ?? DOSSIER) : "ok";
    return { value: { content: [{ type: "text", text }], isError: false } };
  });
  return sent;
}

const declares = (sent: Declare[]) => sent.filter((d) => d.tool !== "get_dossier");

// Fire-and-forget calls land a few ticks after the hook returns.
async function settle() {
  for (let i = 0; i < 2_000; i++) await Promise.resolve();
}

test("a citizen registers, then declares thinking, each tool, and idle, in order", async ($, on) => {
  const sent = engine(on);

  await $.session.start(START);
  await $.turn.start({ text: "run the gate", turnId: "t1" });
  await $.tool.call({ tool: "Bash", command: "mise run check" });
  await $.tool.call({ tool: "Read", file_path: "/repo/lib/x.ex" });
  await $.turn.complete({ ...TURN_END, agentId: "sub-1" });
  await $.turn.complete(TURN_END);
  await settle();

  expect(declares(sent)).toEqual([
    { tool: "register", args: { pane_ref: "%7" } },
    { tool: "presence_thinking", args: {} },
    { tool: "presence_doing", args: { what: "test", summary: "Bash · mise run check" } },
    { tool: "presence_doing", args: { what: "read", summary: "Read · lib/x.ex" } },
    { tool: "presence_idle", args: {} },
  ]);
});

test("a plain claude, with no tlon identity, calls nothing and briefs nothing", async ($, on) => {
  const sent = engine(on, { env: {} });

  await $.session.start(START);
  await $.tool.call({ tool: "Bash", command: "ls" });
  const r = await $.prompt.submit({ text: "hi", wait: false });

  expect(sent).toEqual([]);
  expect(r.context).toBeUndefined();
});

test("a down server never holds the tool", async ($, on) => {
  engine(on, { serverDown: true });

  await $.session.start(START);
  const r = await $.tool.call({ tool: "Bash", command: "ls" });

  expect(r.result).toBe("ok");
});

test("the brief rides a prompt when the dossier changed, and again after a /clear", async ($, on) => {
  const world: World = {};
  engine(on, world);
  await $.session.start(START);

  const first = await $.prompt.submit({ text: "start", wait: false });
  const same = await $.prompt.submit({ text: "go on", wait: false });
  world.dossier = { ...DOSSIER, goal: "ship the mod, then the band" };
  const changed = await $.prompt.submit({ text: "and now", wait: false });
  await $.session.end({ reason: "clear", sessionId: "s1" });
  const cleared = await $.prompt.submit({ text: "fresh", wait: false });

  expect(first.context?.[0]).toContain("# Brief: ship the mod");
  expect(first.context?.[0]).toContain("You are glm-5.2 (Claude Code).");
  expect(same.context).toBeUndefined();
  expect(changed.context?.[0]).toContain("# Brief: ship the mod, then the band");
  expect(cleared.context?.[0]).toContain("# Brief: ship the mod, then the band");
});

test("a correction is proposed as a habit, once", async ($, on) => {
  const sent = engine(on);
  await $.session.start(START);

  await $.prompt.submit({ text: "always run mise run check before committing", wait: false });
  await $.prompt.submit({ text: "always run mise run check before committing", wait: false });
  await settle();

  expect(declares(sent).filter((d) => d.tool === "propose_habit")).toEqual([
    { tool: "propose_habit", args: { text: "always run mise run check before committing", rationale: "auto-detected from a correction you made" } },
  ]);
});

test("a turn's capture banks what was learned, never the brief it was given", async ($, on) => {
  const long = "we decided the band shows the thread goal ".repeat(60);
  const extraction = JSON.stringify({ facts: [{ text: "the band shows the goal", kind: "decision" }], questions: [] });
  let prompt = "";
  const sent = engine(on, {
    transcript: [{ role: "user", text: `${long}<tlon-brief>\nBRIEF-SECRET\n</tlon-brief>` }],
    fetch: (e) => {
      prompt = JSON.parse(e.init.body).messages[0].content;
      return { status: 200, ok: true, headers: {}, text: JSON.stringify({ choices: [{ message: { content: extraction } }] }) };
    },
  });
  await $.session.start(START);

  await $.turn.complete(TURN_END);
  await settle();

  expect(prompt).toContain("we decided the band");
  expect(prompt).not.toContain("BRIEF-SECRET");
  expect(declares(sent).filter((d) => d.tool === "bank_fact")).toEqual([
    { tool: "bank_fact", args: { text: "the band shows the goal", kind: "decision" } },
  ]);
});

test("a short turn waits for more before paying for an extraction", async ($, on) => {
  let calls = 0;
  engine(on, {
    transcript: [{ role: "user", text: "hi" }],
    fetch: () => {
      calls++;
      return { status: 200, ok: true, headers: {}, text: "{}" };
    },
  });
  await $.session.start(START);

  await $.turn.complete(TURN_END);
  await settle();

  expect(calls).toBe(0);
});

const ON_OLLAMA = { ...IDENTITY, ANTHROPIC_BASE_URL: "https://ollama.com" };

test("/fresh asks the named model on the ollama gateway and prints its answer for the session", async ($, on) => {
  let ran: { argv: string[]; env?: Record<string, string> } | null = null;
  const world: World = {
    run: (argv, init) => {
      ran = { argv, env: init?.env };
      return { exitCode: 0, stdout: "use a GenServer\n", stderr: "" };
    },
  };
  engine(on, world);
  await $.session.start(START);

  const r = await $.command.run({ command: "fresh", args: "glm-5.2 how should this hold state?" });
  await settle();

  expect(ran!.argv.slice(0, 5)).toEqual(["claude", "-p", "how should this hold state?", "--model", "glm-5.2"]);
  expect(ran!.argv).toContain("Read,Grep,Glob");
  expect(ran!.env).toMatchObject({ ANTHROPIC_BASE_URL: "https://ollama.com", ANTHROPIC_AUTH_TOKEN: "k", TLON_THREAD: "" });
  expect(r.text).toBe("[/fresh glm-5.2] how should this hold state?\n\nuse a GenServer");
});

test("the consult tool answers in place, with the transcript as context", async ($, on) => {
  let task = "";
  engine(on, {
    transcript: [{ role: "user", text: "we are adding the band" }],
    run: (argv) => {
      task = argv[2]!;
      return { exitCode: 0, stdout: "looks right", stderr: "" };
    },
  });
  await $.session.start(START);

  const r = await $.tool.call({ tool: "mcp__tlon-citizen__consult", prompt: "is this right?" });

  expect(r.result).toBe("looks right");
  expect(task).toContain("### user\nwe are adding the band");
  expect(task).toEndWith("is this right?");
});

test("an image read on a text-only ollama model is described by a vision model", async ($, on) => {
  let asked = "";
  engine(on, {
    env: ON_OLLAMA,
    model: "glm-5.2",
    run: () => ({ exitCode: 0, stdout: "aW1n", stderr: "" }),
    fetch: (e) => {
      asked = JSON.parse(e.init.body).model;
      return { status: 200, ok: true, headers: {}, text: JSON.stringify({ choices: [{ message: { content: "a red build badge" } }] }) };
    },
  });
  await $.session.start(START);

  const r = await $.tool.call({ tool: "Read", file_path: "/tmp/shot.png" });

  expect(asked).toBe("minimax-m3");
  expect(r.result).toContain("a red build badge");
});

test("a model that sees images, or one on the Claude plan, reads the image itself", async ($, on) => {
  engine(on, { model: "glm-5.2" });
  await $.session.start(START);

  const r = await $.tool.call({ tool: "Read", file_path: "/tmp/shot.png" });

  expect(r.result).toBe("ok");
});

test("on the ollama gateway, web_search goes through ollama's search", async ($, on) => {
  let url = "";
  engine(on, {
    env: ON_OLLAMA,
    fetch: (e) => {
      url = e.url;
      return { status: 200, ok: true, headers: {}, text: JSON.stringify({ results: [{ title: "Mods", url: "https://code.claude.com/x", content: "a mod is a plugin" }] }) };
    },
  });
  await $.session.start(START);

  const r = await $.tool.call({ tool: "mcp__tlon-citizen__web_search", query: "claude code mods" });

  expect(url).toBe("https://ollama.com/api/web_search");
  expect(r.result).toContain("## Mods\nhttps://code.claude.com/x\na mod is a plugin");
});
