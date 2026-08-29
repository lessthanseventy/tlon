import { describe, expect, test } from "bun:test";
import { planReload } from "./extension.ts";

// The pure seam: given the environment, reload decides to refuse (with a specific reason) or to
// emit an exact detached-respawn argv. Tested without spawning anything or touching tmux.

describe("planReload — guards", () => {
  test("no TMUX_PANE → refuses (not in the embedded terminal)", () => {
    const p = planReload({ pane: undefined, cmd: "mise exec -- pi --continue" });
    expect(p.ok).toBe(false);
    expect(p.error).toMatch(/TMUX_PANE/);
    expect(p.bashArgv).toBeUndefined();
  });

  test("no ADAPTERS_RELOAD_CMD → refuses (launcher hasn't wired it)", () => {
    const p = planReload({ pane: "%3", cmd: undefined });
    expect(p.ok).toBe(false);
    expect(p.error).toMatch(/ADAPTERS_RELOAD_CMD/);
  });
});

describe("planReload — respawn argv", () => {
  const plan = planReload({ pane: "%7", cmd: "mise exec -- pi --continue" }, 0.4);

  test("ok with a bash -c detached-respawn argv", () => {
    expect(plan.ok).toBe(true);
    expect(plan.bashArgv?.[0]).toBe("-c");
    // pane + cmd are passed as positional args ($0/$1), never interpolated into the script.
    expect(plan.bashArgv?.[2]).toBe("%7");
    expect(plan.bashArgv?.[3]).toBe("mise exec -- pi --continue");
  });

  test("script kills the pane and respawns via the positional args (no interpolation)", () => {
    const script = plan.bashArgv?.[1] ?? "";
    expect(script).toContain("respawn-pane -k");
    expect(script).toContain('"$0"'); // pane
    expect(script).toContain('"$1"'); // cmd
    expect(script).toContain("sleep 0.4");
    // the literal pane/cmd must NOT be baked into the script — that's the quoting-safety point
    expect(script).not.toContain("%7");
    expect(script).not.toContain("mise exec");
  });

  test("message names the resume command so the agent knows what's happening", () => {
    expect(plan.message).toContain("mise exec -- pi --continue");
    expect(plan.message).toMatch(/resum/i);
  });
});
