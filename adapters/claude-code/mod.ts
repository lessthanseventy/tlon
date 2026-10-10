// The claude-code adapter's mod: presence, from inside the session. Claude Code runs it in its own
// process, so the declares go over the session's own `tlon` MCP connection (launch.sh's
// --mcp-config, headersHelper-authed) — no bun per hook, no second client, and the declares leave
// in the order the events fire.
//
// Every declare is fire-and-forget: presence is a nicety, and a slow or down server must never
// hold a tool, a turn or the session's start.

import { doingOf, summaryOf } from "../pi/src/doing.ts";

let cwd = "";

function declare($, tool: string, args: Record<string, unknown> = {}) {
  $.mcp.call("tlon", tool, args).catch(() => {});
}

export function register(on) {
  on("session.start", async ($, e, next) => {
    const thread = await $.env.get("TLON_THREAD");
    const author = await $.env.get("TLON_AUTHOR");
    if (!thread || !author) return next(e);
    cwd = e.cwd;
    const pane = await $.env.get("TMUX_PANE");
    declare($, "register", pane ? { pane_ref: pane } : {});
    $.ui.status(`#${thread} as ${author}`);
    return next(e);
  });

  on("turn.start", async ($, e, next) => {
    if (cwd) declare($, "presence_thinking");
    return next(e);
  });

  // `$.mcp.call` raises tool.call too: the mod's own declares are not the session's work.
  on("tool.call", async ($, e, next) => {
    if (cwd && next.origin.plugin !== $.plugin.name) {
      const what = doingOf(e.tool, e);
      const summary = summaryOf(e.tool, e, cwd);
      declare($, "presence_doing", { ...(what ? { what } : {}), summary });
    }
    return next(e);
  });

  // A subagent's turn ends inside the session's own; only the session's turn ending is idle.
  on("turn.complete", async ($, e, next) => {
    if (cwd && !e.agentId) declare($, "presence_idle");
    return next(e);
  });

  on("session.end", async ($, e, next) => {
    if (cwd) declare($, "presence_idle");
    return next(e);
  });
}
