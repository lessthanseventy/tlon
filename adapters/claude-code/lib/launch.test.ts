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
