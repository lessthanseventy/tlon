import { expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
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
