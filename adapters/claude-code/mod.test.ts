import { expect, mock, test } from "claude-code/testing";

type Declare = { tool: string; args: Record<string, unknown> };
type Fetch = (e: { url: string; init: { body: string } }) => { status: number; ok: boolean; headers: Record<string, string>; text: string };
type World = {
  env?: Record<string, string>;
  dossier?: unknown;
  transcript?: { role: string; text: string }[];
  fetch?: Fetch;
  compactSkips?: boolean;
  contextPercent?: number;
  compactions?: { trigger: string; instructions?: string }[];
  run?: (argv: string[], init?: { env?: Record<string, string> }) => { exitCode: number; stdout: string; stderr: string };
  model?: string;
  wakes?: unknown[];
  glance?: unknown;
  toasts?: string[];
  diagnostics?: string;
  http?: (e: { url: string; init?: { method?: string; body?: string } }) => { status: number; ok: boolean; headers: Record<string, string>; text: string };
  answer?: string;
  submitted?: string[];
  ownClock?: boolean;
  serverDown?: boolean;
  dossierHangs?: boolean;
  /** every get_dossier asked for, answered or not */
  dossierCalls?: number;
  dossierFails?: string;
  submitFails?: boolean;
  /** a submit the host holds until the session is idle: it never resolves */
  submitHangs?: boolean;
  /** registers refused until this many have been tried: the MCP server still connecting at boot */
  notConnectedFor?: number;
  writes?: { path: string; text: string }[];
};

const IDENTITY = { TLON_THREAD: "42", TLON_AUTHOR: "claude-code", TMUX_PANE: "%7", OLLAMA_API_KEY: "k" };
const NONE = { shown: [], more: 0 };
const DOSSIER = { thread_id: 42, goal: "ship the mod", lead: "claude-code", todos: NONE, next: null, learnings: NONE, unknowns: NONE, done: NONE, blockers: NONE, checks: NONE, recent: [] };
const GLANCE = { archetype: "builder", crew: [], red: [], persona: { voice: "plain-spoken", catchphrase: "Right then." }, line: null, landed: [] };
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
  on("prompt.submit", ($, e) => {
    if (world.submitFails) throw new Error("session closing");
    if (world.submitHangs) return new Promise(() => {});
    world.submitted?.push(e.text);
    return { text: e.text, context: e.context };
  });
  // $.ui.ask is an AskUserQuestion tool call underneath, answered by question
  on("tool.call", ($, e) =>
    e.tool === "AskUserQuestion"
      ? { result: { questions: e.questions, answers: Object.fromEntries(e.questions.map((q) => [q.question, world.answer ?? ""])) } }
      : { result: "ok" },
  );
  on("env.get", ($, e) => ({ value: env[e.name] }));
  if (!world.ownClock) {
    on("clock.every", () => ({ value: undefined }));
    on("clock.now", () => ({ value: 0 }));
  }
  on("command.register", () => ({ value: undefined }));
  on("tool.register", () => ({ value: undefined }));
  on("fs.read", () => {
    throw new Error("no such file");
  });
  on("fs.write", ($, e) => {
    world.writes?.push({ path: e.path, text: e.text });
    return { value: undefined };
  });
  on("process.run", ($, e) => ({
    value: { isStdoutTruncated: false, isStderrTruncated: false, ...(world.run ?? (() => ({ exitCode: 1, stdout: "", stderr: "no run" })))(e.argv, e.init) },
  }));
  on("ui.invalidate", () => ({ value: undefined }));
  on("session.compact", ($, e) => {
    world.compactions?.push({ trigger: e.trigger, instructions: e.instructions });
    return world.compactSkips ? { skip: "nothing to compact" } : { messages: [{ role: "user", text: "a summary", toolUses: [] }] };
  });
  on("session.measure", ($, e) => ({ changed: e.changed }));
  on("session.usage", () => ({ value: { context: { window: 200_000, percent: world.contextPercent }, rateLimits: [] } }));
  on("ui.toast", ($, e) => {
    world.toasts?.push(e.text);
    return { value: undefined };
  });
  on("session.cwd", () => ({ value: "/repo" }));
  on("session.model", () => ({ value: world.model ?? "glm-5.2" }));
  on("session.messages", () => ({ value: (world.transcript ?? []).map((m) => ({ ...m, toolUses: [] })) }));
  on("http.fetch", ($, e) => ({ value: (world.http ?? world.fetch ?? (() => ({ status: 500, ok: false, headers: {}, text: "" })))(e) }));
  on("mcp.call", ($, e) => {
    if (e.server === "lsp") return { value: { content: [{ type: "text", text: world.diagnostics ?? "no diagnostics" }], isError: false } };
    if (world.serverDown) throw new Error("connection refused");
    if (e.tool === "register" && world.notConnectedFor && world.notConnectedFor-- > 0) throw new Error('no connected MCP tool "register" on a server named "tlon"');
    if (e.tool === "get_dossier" && world.dossierCalls !== undefined) world.dossierCalls++;
    if (e.tool === "get_dossier" && world.dossierHangs) return new Promise(() => {});
    if (e.tool === "get_dossier" && world.dossierFails) return { value: { content: [{ type: "text", text: world.dossierFails }], isError: true } };
    sent.push({ tool: e.tool, args: e.args ?? {} });
    const text =
      e.tool === "get_dossier"
        ? JSON.stringify(world.dossier ?? DOSSIER)
        : e.tool === "take_wakes"
          ? (() => {
              const w = world.wakes?.shift();
              return typeof w === "string" ? w : JSON.stringify(w ?? []);
            })()
          : e.tool === "register"
            ? JSON.stringify({ session_id: 5, agent: "lonnrot", thread_id: 42 })
          : e.tool === "office_glance"
            ? JSON.stringify(world.glance ?? GLANCE)
            : "ok";
    return { value: { content: [{ type: "text", text }], isError: false } };
  });
  return sent;
}

const READS = ["get_dossier", "take_wakes", "office_glance"];
const declares = (sent: Declare[]) => sent.filter((d) => !READS.includes(d.tool));

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

test("a get_dossier reply that isn't a dossier is logged where the seat's state lives", async ($, on) => {
  const world: World = { writes: [], env: { ...IDENTITY, XDG_STATE_HOME: "/state" } };
  engine(on, world);
  await $.session.start(START);
  world.dossier = "session not registered on this server";
  await $.prompt.submit({ text: "go on", wait: false });
  await settle();

  const last = world.writes!.at(-1);
  expect(last?.path).toBe("/state/tlon/citizen-claude-code.log");
  expect(last?.text).toContain('get_dossier: not a dossier: "session not registered on this server"');
});

test("a get_dossier that never answers holds the prompt only so long: the last brief goes, as of when it came", async ($, on) => {
  const world: World = { ownClock: true };
  engine(on, world);
  const clock = mock.clock(on);
  await $.session.start(START);
  await $.prompt.submit({ text: "start", wait: false });
  await $.session.end({ reason: "clear", sessionId: "s1" });

  world.dossierHangs = true;
  let done = false;
  const slow = $.prompt.submit({ text: "fresh", wait: false }).then((r) => ((done = true), r));
  await settle();
  expect(done).toBe(false);
  await clock.advance(3_000);
  const r = await slow;

  expect(r.context?.[0]).toContain("# Brief: ship the mod");
  expect(r.context?.[0]).toContain("the server didn't answer in time: this brief is as of");
});

test("one get_dossier in flight: prompts during a hung one queue one more behind it, which runs once it gives up", async ($, on) => {
  const world: World = { ownClock: true, dossierHangs: true, dossierCalls: 0 };
  engine(on, world);
  const clock = mock.clock(on);
  await $.session.start(START);
  await settle();
  expect(world.dossierCalls).toBe(1);

  for (const text of ["one", "two"]) {
    const r = $.prompt.submit({ text, wait: false });
    await settle();
    await clock.advance(3_000);
    await r;
  }
  expect(world.dossierCalls).toBe(1);

  await clock.advance(30_000);
  await settle();
  expect(world.dossierCalls).toBe(2);
});

test("a get_dossier that fails fast still dates the brief it falls back on, with why", async ($, on) => {
  const world: World = {};
  engine(on, world);
  await $.session.start(START);
  await $.prompt.submit({ text: "start", wait: false });
  await $.session.end({ reason: "clear", sessionId: "s1" });

  world.dossierFails = "session not registered";
  const r = await $.prompt.submit({ text: "fresh", wait: false });

  expect(r.context?.[0]).toContain("# Brief: ship the mod");
  expect(r.context?.[0]).toContain("the server didn't answer (session not registered): this brief is as of");
});

test("with no brief yet and a server that can't answer, the prompt says so in one line, and the failure is logged", async ($, on) => {
  const world: World = { dossierFails: "session not registered", writes: [], env: { ...IDENTITY, XDG_STATE_HOME: "/state" } };
  engine(on, world);
  await $.session.start(START);

  const r = await $.prompt.submit({ text: "go", wait: false });
  await settle();

  expect(r.context).toEqual(["<tlon-brief>\nNo brief: the tlon server didn't answer get_dossier (session not registered). get_messages reads the thread when it is back.\n</tlon-brief>"]);
  expect(world.writes!.some((w) => w.text.includes("get_dossier: session not registered"))).toBe(true);
});

const SO_FAR = [{ role: "user", text: "start", toolUses: [] }];

test("a compaction that replaced the conversation brings the whole brief back on the next prompt; a skipped or precomputed one doesn't", async ($, on) => {
  const world: World = {};
  engine(on, world);
  await $.session.start(START);

  await $.prompt.submit({ text: "start", wait: false });
  await $.session.compact({ trigger: "precompute", messages: SO_FAR });
  const afterPrecompute = await $.prompt.submit({ text: "go on", wait: false });
  world.compactSkips = true;
  await $.session.compact({ trigger: "auto", messages: SO_FAR });
  const afterSkip = await $.prompt.submit({ text: "and on", wait: false });
  world.compactSkips = false;
  await $.session.compact({ trigger: "auto", messages: SO_FAR });
  const afterCompact = await $.prompt.submit({ text: "where was I", wait: false });

  expect(afterPrecompute.context).toBeUndefined();
  expect(afterSkip.context).toBeUndefined();
  expect(afterCompact.context?.[0]).toContain("# Brief: ship the mod");
});

test("a seat set to compact at half full asks to compact between main-thread turns once past it, never under 50% or after a subagent's", async ($, on) => {
  const world: World = { env: { ...IDENTITY, TLON_COMPACT_AT: "50" }, compactions: [], contextPercent: 30 };
  engine(on, world);
  await $.session.start(START);

  // the kit has no core to fill a plugin compaction's transcript, so this holds the request: when and
  // what it asks to keep; that an applied compaction re-briefs is "a compaction that replaced the conversation…"
  await $.prompt.submit({ text: "start", wait: false });
  await $.turn.complete(TURN_END);
  await settle();
  expect(world.compactions).toEqual([]);

  world.contextPercent = 70;
  await $.turn.complete({ ...TURN_END, agentId: "sub-1" });
  await settle();
  expect(world.compactions).toEqual([]);

  await $.turn.complete(TURN_END);
  await settle();
  expect(world.compactions).toHaveLength(1);
  expect(world.compactions![0]!.instructions).toContain("Keep what is in flight");
});

test("a seat with no compaction point leaves compaction to Claude Code", async ($, on) => {
  const world: World = { compactions: [], contextPercent: 90 };
  engine(on, world);
  await $.session.start(START);
  await $.prompt.submit({ text: "start", wait: false });
  await $.turn.complete(TURN_END);
  await settle();
  expect(world.compactions).toEqual([]);
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
    fetch: (e) => {
      if (e.url.includes("ollama.com")) calls++;
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

test("a consult's delegate is held to the seat's own deny rules", async ($, on) => {
  let argv: string[] = [];
  engine(on, {
    env: { ...IDENTITY, TLON_PERMISSIONS_DENY: "Read(~/.ssh/*),Read(**/*.env)" },
    run: (a) => {
      argv = a;
      return { exitCode: 0, stdout: "ok", stderr: "" };
    },
  });
  await $.session.start(START);

  await $.command.run({ command: "fresh", args: "what is in the keys?" });

  const settings = argv[argv.indexOf("--settings") + 1]!;
  expect(JSON.parse(settings)).toEqual({ permissions: { deny: ["Read(~/.ssh/*)", "Read(**/*.env)"] } });
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

test("a wake the server queued is taken on the next poll and submitted as a turn — nothing typed", async ($, on) => {
  const world: World = { ownClock: true, wakes: [["New message on thread 42 from lonnrot: look at the band"]], submitted: [] };
  engine(on, world);
  const clock = mock.clock(on);
  await $.session.start(START);

  await clock.advance(3_000);
  await settle();

  expect(world.submitted).toEqual(["New message on thread 42 from lonnrot: look at the band"]);
});

test("a register refused while the MCP server is still connecting is tried again until it lands", async ($, on) => {
  const world: World = { ownClock: true, notConnectedFor: 3 };
  const sent = engine(on, world);
  const clock = mock.clock(on);
  await $.session.start(START);
  await settle();
  expect(sent.filter((d) => d.tool === "register")).toEqual([]);

  for (let i = 0; i < 3; i++) {
    await clock.advance(3_000);
    await settle();
  }
  expect(sent.filter((d) => d.tool === "register")).toEqual([{ tool: "register", args: { pane_ref: "%7" } }]);

  await clock.advance(3_000);
  await settle();
  expect(sent.filter((d) => d.tool === "register").length).toBe(1);
});

test("a session the server says was superseded is told to stop once, and takes no wakes while the newer one holds the seat", async ($, on) => {
  const text = "This session was superseded: a newer session now holds lonnrot's seat on thread #42. Stop.";
  const gone = { superseded: true, by: 9, text };
  const world: World = { ownClock: true, wakes: [gone, gone, gone], submitted: [] };
  const sent = engine(on, world);
  const clock = mock.clock(on);
  await $.session.start(START);

  for (let i = 0; i < 3; i++) {
    await clock.advance(3_000);
    await settle();
  }

  expect(sent.filter((d) => d.tool === "register").length).toBe(1);
  expect(world.submitted).toEqual([text]);
});

test("a superseded session whose newer one is gone claims the seat again instead of staying stopped", async ($, on) => {
  const text = "This session was superseded: a newer session now holds lonnrot's seat on thread #42. Stop.";
  const world: World = { ownClock: true, wakes: [{ superseded: true, by: 9, text }, [], ["a wake the seat missed"]], submitted: [], writes: [], env: { ...IDENTITY, XDG_STATE_HOME: "/state" } };
  const sent = engine(on, world);
  const clock = mock.clock(on);
  await $.session.start(START);

  for (let i = 0; i < 3; i++) {
    await clock.advance(3_000);
    await settle();
  }

  expect(sent.filter((d) => d.tool === "register").length).toBe(2);
  expect(world.submitted).toEqual([text, "a wake the seat missed"]);
  expect(world.writes!.some((w) => w.text.includes("take_wakes: no longer superseded — claiming the seat again"))).toBe(true);
});

test("a superseded session does not claim the seat back on a reply that is not a wake list", async ($, on) => {
  const text = "This session was superseded: a newer session now holds lonnrot's seat on thread #42. Stop.";
  const world: World = { ownClock: true, wakes: [{ superseded: true, by: 9, text }, "upstream hiccup, not json"], submitted: [] };
  const sent = engine(on, world);
  const clock = mock.clock(on);
  await $.session.start(START);

  for (let i = 0; i < 2; i++) {
    await clock.advance(3_000);
    await settle();
  }

  expect(sent.filter((d) => d.tool === "register").length).toBe(1);
  expect(world.submitted).toEqual([text]);
});

test("a later session.start whose register fails takes wakes without the earlier session's id", async ($, on) => {
  const world: World = { ownClock: true };
  const sent = engine(on, world);
  const clock = mock.clock(on);
  await $.session.start(START);
  await settle();
  await clock.advance(3_000);
  await settle();
  expect(sent.filter((d) => d.tool === "take_wakes").at(-1)?.args).toEqual({ session_id: 5 });

  world.notConnectedFor = 99;
  await $.session.start(START);
  await settle();
  await clock.advance(3_000);
  await settle();
  expect(sent.filter((d) => d.tool === "take_wakes").at(-1)?.args).toEqual({});
});

test("a wake whose submit fails is put back on the server, not lost", async ($, on) => {
  const world: World = { ownClock: true, wakes: [["wake one", "wake two"]], submitFails: true };
  const sent = engine(on, world);
  const clock = mock.clock(on);
  await $.session.start(START);

  await clock.advance(3_000);
  await settle();

  expect(sent.filter((d) => d.tool === "put_back_wakes")).toEqual([{ tool: "put_back_wakes", args: { prompts: ["wake one", "wake two"] } }]);
});

test("a submit the host holds until idle doesn't stop the next poll from taking", async ($, on) => {
  const world: World = { ownClock: true, wakes: [["wake one"], ["wake two"]], submitHangs: true };
  const sent = engine(on, world);
  const clock = mock.clock(on);
  await $.session.start(START);

  await clock.advance(3_000);
  await settle();
  await clock.advance(3_000);
  await settle();

  expect(sent.filter((d) => d.tool === "take_wakes").length).toBeGreaterThanOrEqual(2);
});

test("a main turn ending while a subagent still runs is not idle; the last subagent ending is", async ($, on) => {
  const sent = engine(on);

  await $.session.start(START);
  await $.turn.start({ text: "go", turnId: "t1" });
  await $.turn.start({ text: "bg", turnId: "s1", agentId: "sub-1" });
  await $.turn.complete(TURN_END);
  await settle();
  expect(declares(sent).filter((d) => d.tool === "presence_idle")).toEqual([]);

  await $.turn.complete({ ...TURN_END, agentId: "sub-1" });
  await settle();
  expect(declares(sent).filter((d) => d.tool === "presence_idle")).toHaveLength(1);
});

test("a push is held for the server's push_branch; a status runs", async ($, on) => {
  engine(on);
  on("tool.check", () => ({ decision: "allow" }));
  await $.session.start(START);

  const push = await $.tool.check({ tool: "Bash", input: { command: "git push origin HEAD" } });
  const status = await $.tool.check({ tool: "Bash", input: { command: "git status" } });

  expect(push.decision).toBe("deny");
  expect(push.reason).toContain("push_branch");
  expect(status.decision).toBe("allow");
});

test("a refusal beneath the mod is reported with the call and the check's reason, never acted on", async ($, on) => {
  const sent = engine(on);
  on("tool.check", () => ({ decision: "deny", reason: "Auto-Mode Bypass" }));
  await $.session.start(START);

  const r = await $.tool.check({ tool: "Bash", input: { command: "mise run release:smoke" } });
  await settle();

  expect(r.decision).toBe("deny");
  expect(sent.filter((d) => d.tool === "tool_denied")).toEqual([
    { tool: "tool_denied", args: { tool: "Bash", summary: "Bash · mise run release:smoke", reason: "Auto-Mode Bypass" } },
  ]);
});

test("a commit is signed by the model that is running, on its provider's address", async ($, on) => {
  engine(on, { env: ON_OLLAMA, model: "kimi-k2.7-code" });
  on("attribution.text", ($, e) => ({ text: e.text }));
  await $.session.start(START);

  const r = await $.attribution.text({ kind: "commit", text: "Co-Authored-By: Claude <noreply@anthropic.com>\nClaude-Session: x" });

  expect(r.text).toBe("Co-Authored-By: kimi-k2.7-code <noreply@ollama.com>\nClaude-Session: x");
});

test("an edit's result carries what the language server says about the file", async ($, on) => {
  engine(on, { diagnostics: "lib/x.ex:3:1 error: undefined variable foo" });
  await $.session.start(START);

  const r = await $.tool.call({ tool: "Edit", file_path: "/repo/lib/x.ex", old_string: "a", new_string: "b" });

  expect(r.context?.[0]).toContain("undefined variable foo");
});

test("a clean edit carries nothing extra", async ($, on) => {
  engine(on);
  await $.session.start(START);

  const r = await $.tool.call({ tool: "Edit", file_path: "/repo/lib/x.ex", old_string: "a", new_string: "b" });

  expect(r.context).toBeUndefined();
});

test("a new message that @mentions this seat is a toast; the ones before it never are", async ($, on) => {
  const world: World = { toasts: [], dossier: { ...DOSSIER, recent: [{ id: 1, author: "yu", body: "@claude-code old", reply_to: null, at: null }] } };
  engine(on, world);
  await $.session.start(START);
  await $.prompt.submit({ text: "go", wait: false });

  world.dossier = { ...DOSSIER, recent: [{ id: 2, author: "lonnrot", body: "@claude-code look at this", reply_to: null, at: null }] };
  await $.prompt.submit({ text: "and", wait: false });

  expect(world.toasts).toEqual(["lonnrot: @claude-code look at this"]);
});

test("@ completes from the crew the office says is on", async ($, on) => {
  engine(on, { glance: { ...GLANCE, crew: [{ agent: "lonnrot", thread_id: 7, warm: true, thinking: false, doing: null }] } });
  on("prompt.autocomplete", () => ({ suggestions: [] }));
  await $.session.start(START);
  await settle();

  const r = await $.prompt.autocomplete({ text: "@lo", cursor: 3, token: "@lo", start: 0 });

  expect(r.suggestions).toEqual([{ text: "@lonnrot", description: "#7" }]);
});

test("the operator's session puts a coworker's ask to them and answers it by its key", async ($, on) => {
  let answered = "";
  const ask = { key: "ask:9", kind: "ask", level: "blocking", ref: 9, title: "keep the last one?", options: [{ key: "1", label: "keep" }, { key: "2", label: "drop" }] };
  engine(on, {
    env: { TLON_OPERATOR_MODE: "1" },
    answer: "drop",
    http: (e) => {
      if (e.url.endsWith("/office/needs")) return { status: 200, ok: true, headers: {}, text: JSON.stringify([ask]) };
      if (e.url.endsWith("/office/asks/9")) answered = e.init?.body ?? "";
      return { status: 200, ok: true, headers: {}, text: "{}" };
    },
  });
  await $.session.start(START);
  await settle();

  expect(answered).toBe(JSON.stringify({ key: "2" }));
});

test("the operator's band reads the server the session points at, a scratch release's port too", async ($, on) => {
  const urls: string[] = [];
  engine(on, {
    env: { TLON_OPERATOR_MODE: "1", TLON_MCP_URL: "http://127.0.0.1:4141/mcp" },
    http: (e) => {
      urls.push(e.url);
      return { status: 200, ok: true, headers: {}, text: "[]" };
    },
  });
  await $.session.start(START);
  await settle();

  expect(urls).toContain("http://127.0.0.1:4141/api/office/needs");
  expect(urls.every((u) => u.startsWith("http://127.0.0.1:4141/api/"))).toBe(true);
});

test("a rate-limit window that moves is posted to the office's usage meter; a context move alone is not", async ($, on) => {
  const posts: { url: string; body?: string }[] = [];
  engine(on, { fetch: (e) => (e.init?.method === "POST" && posts.push({ url: e.url, body: e.init.body }), { status: 200, ok: true, headers: {}, text: "{}" }) });
  await $.session.start(START);

  const context = { window: 200_000 };
  await $.session.measure({ context, rateLimits: [{ kind: "five_hour", percentUsed: 34, resetsAt: "2026-10-13T19:00:00Z" }], changed: ["context"] });
  await settle();
  expect(posts).toEqual([]);

  await $.session.measure({ context, rateLimits: [{ kind: "five_hour", percentUsed: 35, resetsAt: "2026-10-13T19:00:00Z" }, { kind: "seven_day", percentUsed: 44 }], changed: ["rateLimits"] });
  await settle();
  expect(posts.map((p) => p.url)).toEqual(["http://127.0.0.1:4040/api/usage/claude"]);
  expect(JSON.parse(posts[0]!.body!)).toEqual({ five_hour: { percent: 35, resets_at: "2026-10-13T19:00:00Z" }, seven_day: { percent: 44, resets_at: null } });
});

const LANDING = { id: 9, source: "event", kind: "work_landed", summary: "landed", at: null };

test("a landing the seat led is toasted in the alert row's own words", async ($, on) => {
  const world: World = {
    toasts: [],
    dossier: { ...DOSSIER, done: { shown: [{ ...LANDING, id: 3 }], more: 0 } } as never,
    http: (e) => ({ status: 200, ok: true, headers: {}, text: e.url.endsWith("/api/alerts") ? JSON.stringify([{ kind: "landed", key: "landed:9", level: "info", title: "#42 landed — ship the mod", thread_id: 42, at: "2026-10-19T10:00:00Z" }, { kind: "landed", key: "landed:8", level: "info", title: "#7 landed — other", thread_id: 7, at: "2026-10-19T11:00:00Z" }]) : "{}" }),
  };
  engine(on, world);
  await $.session.start(START);
  await $.prompt.submit({ text: "go", wait: false });

  world.dossier = { ...DOSSIER, done: { shown: [LANDING, { ...LANDING, id: 3 }], more: 0 } } as never;
  await $.prompt.submit({ text: "and", wait: false });
  await settle();

  expect(world.toasts).toContain("#42 landed — ship the mod");
  expect(world.toasts).not.toContain("landed ✓");
});

test("with no alert row to read, a landing still toasts", async ($, on) => {
  const world: World = { toasts: [], dossier: { ...DOSSIER, done: { shown: [{ ...LANDING, id: 3 }], more: 0 } } as never };
  engine(on, world);
  await $.session.start(START);
  await $.prompt.submit({ text: "go", wait: false });

  world.dossier = { ...DOSSIER, done: { shown: [LANDING, { ...LANDING, id: 3 }], more: 0 } } as never;
  await $.prompt.submit({ text: "and", wait: false });
  await settle();

  expect(world.toasts).toContain("landed ✓");
});
