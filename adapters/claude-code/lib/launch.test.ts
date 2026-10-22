import { expect, test } from "bun:test";
import { mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const launcher = new URL("../launch.sh", import.meta.url).pathname;

// A sandboxed seat runs dontAsk: any tool not on permissions.allow is refused without a prompt.
// The dry run prints the settings the window would start with, without spawning anything.
test("a sandboxed seat may use menard's tools without a prompt", async () => {
  const dir = mkdtempSync(join(tmpdir(), "launch-test-"));
  const sandboxFile = join(dir, "sandbox.json");
  writeFileSync(sandboxFile, "{}");
  const proc = Bun.spawn(["bash", launcher], {
    env: {
      ...process.env,
      TLON_LAUNCH_DRYRUN: "1",
      TLON_SANDBOX_FILE: sandboxFile,
      TLON_MCP_URL: "http://127.0.0.1:1/mcp",
      TLON_THREAD: "1",
      TLON_AUTHOR: "pierre",
    },
    stdout: "pipe",
    stderr: "pipe",
  });
  const out = await new Response(proc.stdout).text();
  expect(await proc.exited).toBe(0);
  const line = out.split("\n").find((l) => l.startsWith("settings:"));
  expect(line).toBeDefined();
  const settings = JSON.parse(line!.slice("settings:".length));
  expect(settings.permissions.allow).toContain("mcp__plugin_menard_menard");
});

// The dry run of a seat that needs no sandbox: its settings and the exec line it would run.
async function dryRun(author: string) {
  const proc = Bun.spawn(["bash", launcher], {
    env: {
      ...process.env,
      TLON_LAUNCH_DRYRUN: "1",
      TLON_SANDBOX_FILE: "",
      TLON_MCP_URL: "http://127.0.0.1:1/mcp",
      TLON_THREAD: "42",
      TLON_AUTHOR: author,
    },
    stdout: "pipe",
    stderr: "pipe",
  });
  const out = await new Response(proc.stdout).text();
  expect(await proc.exited).toBe(0);
  const settings = JSON.parse(out.split("\n").find((l) => l.startsWith("settings:"))!.slice("settings:".length));
  const exec = out.split("\n").find((l) => l.startsWith("exec:"))!;
  return { settings, exec };
}

// The operator's own ~/.claude/settings.json turns remote control on at startup; --settings outranks
// it, so every seat but uqbar's study opens without a /rc session.
test("a seat starts with remote control off", async () => {
  const { settings } = await dryRun("pierre");
  expect(settings.remoteControlAtStartup).toBe(false);
});

test("uqbar keeps the operator's remote control", async () => {
  const { settings } = await dryRun("uqbar");
  expect(settings).not.toHaveProperty("remoteControlAtStartup");
});

// Seat transcripts land in the operator's /resume picker; a name tells them apart from his own chats.
test("a seat is named for its author and thread", async () => {
  const { exec } = await dryRun("pierre");
  expect(exec).toContain("--name pierre #42");
});

// A seat's own workline is a linked worktree: commit writes its gitdir and the common .git, which
// sit outside the worktree, so its cwd alone (".") is not enough to write.
test("a sandboxed seat may write the worktree it starts in and its gitdirs", async () => {
  const dir = realpathSync(mkdtempSync(join(tmpdir(), "launch-test-")));
  const sandboxFile = join(dir, "sandbox.json");
  writeFileSync(sandboxFile, JSON.stringify({ filesystem: { allowWrite: ["/tmp"] } }));
  const repo = join(dir, "repo");
  const worktree = join(dir, "wt");
  const git = (...args: string[]) => {
    const r = Bun.spawnSync(["git", ...args], { stderr: "pipe" });
    expect(r.exitCode).toBe(0);
  };
  git("init", "-q", repo);
  git("-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "root");
  git("-C", repo, "worktree", "add", "-q", "--detach", worktree);
  const proc = Bun.spawn(["bash", launcher], {
    cwd: worktree,
    env: {
      ...process.env,
      TLON_LAUNCH_DRYRUN: "1",
      TLON_SANDBOX_FILE: sandboxFile,
      TLON_MCP_URL: "http://127.0.0.1:1/mcp",
      TLON_THREAD: "1",
      TLON_AUTHOR: "pierre",
    },
    stdout: "pipe",
    stderr: "pipe",
  });
  const out = await new Response(proc.stdout).text();
  expect(await proc.exited).toBe(0);
  const line = out.split("\n").find((l) => l.startsWith("settings:"));
  const settings = JSON.parse(line!.slice("settings:".length));
  expect(settings.sandbox.filesystem.allowWrite).toEqual([
    "/tmp",
    worktree,
    join(repo, ".git", "worktrees", "wt"),
    join(repo, ".git"),
  ]);
});
