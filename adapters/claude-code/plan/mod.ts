// Loaded only for a seat on the Claude plan (launch.sh). A turn.step hook re-yields the model's
// stream, and a stream that passes through a hook is held to Claude's tool-call id shape, which
// other models' ids fail (kimi's `functions.Bash:0`): on a gateway seat no mod may wrap it.

// Past this much of the five-hour window, every request at low effort.
const SCORCHED_5H = 90;

export function register(on) {
  on("turn.step", async function* ($, e, next) {
    const usage = await $.session.usage();
    const used = usage.rateLimits.find((r) => r.kind === "five_hour")?.percentUsed ?? 0;
    if (!e.agentId && used >= SCORCHED_5H) return yield* next({ ...e, effort: "low" });
    return yield* next(e);
  });
}
