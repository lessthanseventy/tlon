// The dense statusline — replaces pi's default thin footer with a 2-line bar that
// packs the things you glance at most: full model name (never truncated), context
// usage with a visual bar, session I/O, git branch, sandbox, and server connection.
//
// A generic statusline: NOT a server concern, so it lives in its own adapters package (not
// modules/adapters/pi, which the Tlön coworker profile drops to sever the server) — the
// footer loads for every pi, server-citizen or self-contained.
//
// Uses the footerData API for reactive git-branch updates and extension statuses, plus
// ctx.sessionManager / ctx.model / ctx.getContextUsage() for everything else.

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext, FooterData } from "./pi.ts";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// ── formatters (pure — exported so the seams are unit-pinned) ───────────────────

export function fmtTokens(n: number): string {
  if (n === 0) return "0";
  if (n < 1_000) return String(n);
  if (n < 1_000_000) return `${(n / 1_000).toFixed(1)}k`;
  return `${(n / 1_000_000).toFixed(1)}M`;
}

export function fmtCost(c: number): string {
  if (c === 0) return "";
  if (c < 0.01) return `$${c.toFixed(4)}`;
  return `$${c.toFixed(2)}`;
}

// The usage fields the footer glances at, cache included. Structural (not the full pi-ai
// `Usage`) so the seam is unit-pinnable without constructing whole AssistantMessages.
export interface UsageLike {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  cost: { total: number };
}

export interface UsageTotals {
  input: number;
  output: number;
  cost: number;
  cacheRead: number;
  cacheWrite: number;
}

// Fold the per-turn usages into session totals. Extends the old inline input/output/cost
// sum with the cache read/write tokens that were already sitting unused on every Usage.
export function accumulateUsage(usages: Iterable<UsageLike>): UsageTotals {
  const totals: UsageTotals = { input: 0, output: 0, cost: 0, cacheRead: 0, cacheWrite: 0 };
  for (const u of usages) {
    totals.input += u.input;
    totals.output += u.output;
    totals.cost += u.cost.total;
    totals.cacheRead += u.cacheRead;
    totals.cacheWrite += u.cacheWrite;
  }
  return totals;
}

// Share of prompt tokens served from cache: cacheRead / (input + cacheRead + cacheWrite),
// rounded to a whole percent. Zero prompt tokens → 0 (no divide-by-zero). High is good —
// it's the reuse signal the cache-reuse cribs care about.
export function cacheHitPct(input: number, cacheRead: number, cacheWrite: number): number {
  const prompt = input + cacheRead + cacheWrite;
  if (prompt === 0) return 0;
  return Math.round((cacheRead / prompt) * 100);
}

// Self-describing statuses pass through: adapters/pi's "tlon" key (its text already reads
// "tlon: registered …") and pi-sandbox's "sandbox". Every other key prefixes itself for context.
// "tlon" must equal adapters/pi's STATUS_KEY — footer.test.ts pins the two together.
export const SELF_DESCRIBING_STATUS_KEYS: ReadonlySet<string> = new Set(["tlon", "sandbox"]);

export function statusLabel(key: string, text: string): string {
  return SELF_DESCRIBING_STATUS_KEYS.has(key) ? text : `${key}: ${text}`;
}

export function fmtCwd(cwd: string): string {
  const home = process.env.HOME;
  if (home && cwd.startsWith(home)) return `~${cwd.slice(home.length)}`;
  return cwd;
}

// A context bar: ▓▓▓░░░░░░░  fills proportionally. Clamps pct to [0, 100] so context overflow
// (pct > 100) can't produce a negative repeat count (a crash in String.repeat).
export function contextBar(pct: number, width: number): string {
  const clamped = Math.max(0, Math.min(100, pct));
  const filled = Math.round((clamped / 100) * width);
  return "▓".repeat(filled) + "░".repeat(width - filled);
}

// ── the footer component ─────────────────────────────────────────────────────

export default function footer(pi: ExtensionAPI): void {
  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsubBranch = footerData.onBranchChange(() => tui.requestRender());

      // Deferred render kick: the initial setFooter factory can race pi's startup layout
      // (the differential renderer establishes cursor/scroll state while the footer's first
      // paint lands) leaving the footer blank until a later full redraw. Two extra render
      // requests shortly after mount give it a chance to self-heal onto an already-settled
      // layout instead of staying frozen on a missed first paint.
      setTimeout(() => tui.requestRender(), 50);
      setTimeout(() => tui.requestRender(), 200);

      // Extension statuses are reactive through the footer render — no extra sub needed,
      // getExtensionStatuses() already reflects live setStatus() calls on every render.

      return {
        dispose: unsubBranch,
        invalidate() {},
        render(width: number): string[] {
          // NO caching here — pi's main-screen renderer is DIFFERENTIAL: a row is only
          // repainted when its string changes from the previous frame. A cached line that
          // ever missed one paint (a mount-frame positioning slip, observed live) would be
          // frozen wrong forever, since an unchanged cached string never re-enters the diff
          // range to self-heal. Recomputing every call matches the built-in FooterComponent
          // (also uncached) and costs nothing — a string-fold over the branch's usages.

          // Each line built independently and defensively: a throw computing one (an
          // unregistered theme color key, an upstream API shape drift, ...) must not take
          // the other line down with it or vanish with no trace — a visible "failed" stub
          // + a stderr trace beats a footer line that's just silently gone.
          const line1 = safeLine("line1", () => buildLine1(width));
          const line2 = safeLine("line2", () => buildLine2(width));

          return [line1, line2];

          function safeLine(tag: string, build: () => string): string {
            try {
              return build();
            } catch (err) {
              console.error(`adapters/footer: ${tag} render failed:`, err);
              return theme.fg("dim", `footer: ${tag} failed (see stderr)`);
            }
          }

          // ── Line 1: model · provider │ context │ I/O ────────────────────
          function buildLine1(width: number): string {
            const model = ctx.model;
            const modelId = model?.id ?? "no-model";
            const provider = model?.provider ?? "";
            const thinking = pi.getThinkingLevel();

            // Context usage
            const usage = ctx.getContextUsage();
            const ctxWindow = usage?.contextWindow ?? model?.contextWindow;
            const ctxPct = usage?.percent ?? 0;
            const ctxBarW = Math.min(10, Math.max(6, width - 40));
            const ctxLabel = ctxWindow
              ? `${contextBar(ctxPct, ctxBarW)} ${Math.round(ctxPct)}%/${fmtTokens(ctxWindow)}`
              : "ctx ?";

            // Session I/O + cache — one fold over the branch's assistant usages.
            const usages: UsageLike[] = [];
            for (const e of ctx.sessionManager.getBranch()) {
              if (e.type === "message" && e.message.role === "assistant") {
                usages.push((e.message as AssistantMessage).usage);
              }
            }
            const totals = accumulateUsage(usages);
            const ioParts = [`↑${fmtTokens(totals.input)}`, `↓${fmtTokens(totals.output)}`];
            // Cache reuse: only worth showing once cache is actually in play, else it reads
            // as a permanent 0% on providers/sessions that don't cache.
            if (totals.cacheRead > 0 || totals.cacheWrite > 0) {
              ioParts.push(`↺${cacheHitPct(totals.input, totals.cacheRead, totals.cacheWrite)}%`);
            }
            const costStr = fmtCost(totals.cost);
            if (costStr) ioParts.push(costStr);
            const ioLabel = ioParts.join(" ");

            const thinkLabel = thinking !== "off" ? ` · ${thinking}` : "";

            const left =
              theme.fg("accent", `${modelId}`) +
              theme.fg("dim", `${provider ? ` · ${provider}` : ""}${thinkLabel}`);
            const right = theme.fg("muted", `${ctxLabel} │ ${ioLabel}`);

            const pad = Math.max(1, width - visibleWidth(left) - visibleWidth(right));
            return truncateToWidth(left + " ".repeat(pad) + right, width);
          }

          // ── Line 2: cwd (branch) │ statuses ──────────────────────────────
          function buildLine2(width: number): string {
            const branch = footerData.getGitBranch();
            const cwd = fmtCwd(ctx.cwd);

            // Shrink cwd to fit: keep at least branch + "…"
            const branchStr = branch ? ` (${branch})` : "";
            const locBase = `${cwd}${branchStr}`;

            const statuses = footerData.getExtensionStatuses();
            const statusParts: string[] = [];
            statuses.forEach((text, key) => statusParts.push(statusLabel(key, text)));
            const statusStr = statusParts.length > 0 ? statusParts.join(" │ ") : "";

            const left = theme.fg("dim", locBase);
            const right = statusStr ? theme.fg("dim", statusStr) : "";

            if (right) {
              const pad = Math.max(1, width - visibleWidth(left) - visibleWidth(right));
              return truncateToWidth(left + " ".repeat(pad) + right, width);
            }
            return truncateToWidth(left, width);
          }
        },
      };
    });
  });
}
