// adapters/reload — the dogfood loop's "reload me" primitive.
//
// pi loads its extensions ONCE, at process start. So when the agent edits its own tooling
// (any adapters extension) the running pi keeps executing the OLD code — and an agent can't
// restart the process it lives in and keep its train of thought. This tool closes that loop:
// it respawns pi in place and RESUMES the current session, so the agent edits code, calls
// `reload`, and wakes up in the same thread running the new code.
//
// Mechanism: the tlon launcher (aleph Cockpit.tlon_launcher) exports ADAPTERS_RELOAD_CMD — the
// command that re-launches pi with `--continue` (resume the most-recent session = this one).
// reload fires a DETACHED helper (own session via setsid-equivalent) that, after a short delay,
// runs `tmux respawn-pane -k` on pi's own pane: the delay lets this turn's result flush to the
// session file, `-k` kills the old pi, and the launcher's `--continue` brings the thread back.
// The helper is detached so it survives the very process (pi) that spawned it being killed.
//
// Gated on the adapters extensions typechecking (a syntax error would otherwise respawn pi into
// broken code); pass force to skip.

import { spawn } from "node:child_process";
import type { ExtensionAPI, ToolResult } from "./pi.ts";
import { Type } from "./pi.ts";

export interface ReloadEnv {
  pane?: string; // $TMUX_PANE — pi's own tmux pane
  cmd?: string; // $ADAPTERS_RELOAD_CMD — how to re-launch pi, resuming
}

export interface ReloadPlan {
  ok: boolean;
  error?: string; // when ok=false: why reload can't run here
  bashArgv?: string[]; // when ok=true: argv for spawn("bash", …, { detached })
  message?: string; // when ok=true: the text the tool returns before the pane dies
}

// Pure core — decide what reload should do given the environment, no side effects. Exported so
// the guard messages and the exact respawn argv are unit-tested without spawning anything.
export function planReload(env: ReloadEnv, delaySeconds = 0.4): ReloadPlan {
  if (!env.pane) {
    return {
      ok: false,
      error:
        "reload only works inside the tlön tmux pane — $TMUX_PANE is unset. It restarts the pi harness in place, which needs the embedded terminal.",
    };
  }
  if (!env.cmd) {
    return {
      ok: false,
      error:
        "reload has no respawn command — $ADAPTERS_RELOAD_CMD is unset. The tlön launcher (aleph Cockpit.tlon_launcher) exports it; reboot the cockpit after updating aleph so the session carries it.",
    };
  }
  // Positional args ($0=pane, $1=cmd) dodge all quoting. `exec` so no bash lingers. The whole
  // thing runs detached (see execute) so the pane-kill can't take it down mid-respawn.
  const script = `sleep ${delaySeconds}; exec tmux respawn-pane -k -t "$0" "$1"`;
  return {
    ok: true,
    bashArgv: ["-c", script, env.pane, env.cmd],
    message:
      `Reloading the pi harness — it will be killed and respawned via \`${env.cmd}\` in ~${delaySeconds}s, resuming this session. ` +
      "This turn ends now; continue once it's back (new tool code will be live).",
  };
}

// Run the reload safety gate: every adapters pi extension must typecheck, or a fresh pi could fail
// to load one. Returns the combined output on failure. mise walks up to the repo's mise.toml, so
// any cwd inside the repo works.
function runGate(cwd: string): Promise<{ ok: boolean; output: string }> {
  return new Promise((resolve) => {
    let out = "";
    const p = spawn("mise", ["run", "adapters:typecheck"], { cwd, stdio: ["ignore", "pipe", "pipe"] });
    p.stdout.on("data", (d: Buffer) => (out += d.toString()));
    p.stderr.on("data", (d: Buffer) => (out += d.toString()));
    p.on("error", (e) => resolve({ ok: false, output: `could not run the gate: ${e instanceof Error ? e.message : String(e)}` }));
    p.on("exit", (code) => resolve({ ok: code === 0, output: out.trim().slice(-4000) }));
  });
}

export default function reload(pi: ExtensionAPI): void {
  pi.registerTool({
    name: "reload",
    label: "reload",
    description:
      "Restart the pi harness itself and resume this session — use after you EDIT adapters extension/tool code, because the running pi loaded the old code at startup and won't pick up changes otherwise. Typechecks the adapters extensions first (pass force:true to skip). Only works inside the tlön embedded terminal.",
    parameters: Type.Object({
      force: Type.Optional(
        Type.Boolean({ description: "skip the typecheck gate and respawn anyway — only if you're sure every adapters extension still loads" }),
      ),
    }),
    execute: async (_id, params, _signal, _onUpdate, ctx): Promise<ToolResult> => {
      const plan = planReload({ pane: process.env.TMUX_PANE, cmd: process.env.ADAPTERS_RELOAD_CMD });
      if (!plan.ok) return { content: [{ type: "text", text: `reload: ${plan.error}` }], isError: true };

      if (params.force !== true) {
        const gate = await runGate(ctx.cwd);
        if (!gate.ok) {
          return {
            content: [
              {
                type: "text",
                text: `reload aborted — the adapters extensions don't typecheck, so a fresh pi could fail to load one. Fix them, or call reload with force:true.\n\n${gate.output}`,
              },
            ],
            isError: true,
          };
        }
      }

      const child = spawn("bash", plan.bashArgv!, { detached: true, stdio: "ignore" });
      child.unref();
      return { content: [{ type: "text", text: plan.message! }] };
    },
  });
}
