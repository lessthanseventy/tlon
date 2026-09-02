import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  accumulateUsage,
  cacheHitPct,
  contextBar,
  fmtCost,
  fmtTokens,
  SELF_DESCRIBING_STATUS_KEYS,
  statusLabel,
} from "./footer.ts";

describe("fmtTokens — human token counts", () => {
  test("0 / under 1k / k / M thresholds", () => {
    expect(fmtTokens(0)).toBe("0");
    expect(fmtTokens(512)).toBe("512");
    expect(fmtTokens(1_500)).toBe("1.5k");
    expect(fmtTokens(2_400_000)).toBe("2.4M");
  });
});

describe("fmtCost — money, or nothing when free", () => {
  test("0 is blank; sub-cent shows 4 places; else 2", () => {
    expect(fmtCost(0)).toBe("");
    expect(fmtCost(0.0004)).toBe("$0.0004");
    expect(fmtCost(0.42)).toBe("$0.42");
    expect(fmtCost(12.5)).toBe("$12.50");
  });
});

describe("accumulateUsage — sums the fields the footer glances at, cache included", () => {
  test("empty is all zeros", () => {
    expect(accumulateUsage([])).toEqual({ input: 0, output: 0, cost: 0, cacheRead: 0, cacheWrite: 0 });
  });

  test("sums input/output/cost/cacheRead/cacheWrite across turns", () => {
    const totals = accumulateUsage([
      { input: 100, output: 20, cacheRead: 400, cacheWrite: 50, cost: { total: 0.5 } },
      { input: 30, output: 10, cacheRead: 900, cacheWrite: 0, cost: { total: 0.25 } },
    ]);
    expect(totals).toEqual({ input: 130, output: 30, cost: 0.75, cacheRead: 1300, cacheWrite: 50 });
  });
});

describe("cacheHitPct — share of prompt tokens served from cache", () => {
  test("zero prompt tokens is 0 (no divide-by-zero)", () => {
    expect(cacheHitPct(0, 0, 0)).toBe(0);
  });

  test("rounds cacheRead / (input + cacheRead + cacheWrite)", () => {
    expect(cacheHitPct(100, 900, 0)).toBe(90); // 900 / 1000
    expect(cacheHitPct(100, 400, 500)).toBe(40); // 400 / 1000
  });

  test("all-fresh input is 0%", () => {
    expect(cacheHitPct(1000, 0, 0)).toBe(0);
  });
});

describe("statusLabel — self-describing statuses pass through, others get their key", () => {
  test("tlon and sandbox are shown as their text; anything else is prefixed", () => {
    expect(statusLabel("tlon", "tlon: registered — pi on 7")).toBe("tlon: registered — pi on 7");
    expect(statusLabel("sandbox", "🔒 Sandbox: 12 domains")).toBe("🔒 Sandbox: 12 domains");
    expect(statusLabel("lsp", "3 diagnostics")).toBe("lsp: 3 diagnostics");
  });

  // The footer keys on the status the pi adapter sets. The two packages share no code on
  // purpose (the footer loads without adapters/pi), so the coupling is pinned by text: if
  // adapters/pi renames its STATUS_KEY, this fails instead of the footer silently prefixing
  // "tlon: tlon: registered…".
  test("the pass-through key is the one adapters/pi sets its status under", () => {
    const ext = readFileSync(join(import.meta.dir, "../../pi/src/extension.ts"), "utf-8");
    const key = /^const STATUS_KEY = "([^"]+)";/m.exec(ext)?.[1];
    expect(key).toBeDefined();
    expect(SELF_DESCRIBING_STATUS_KEYS.has(key!)).toBe(true);
  });
});

describe("contextBar — proportional fill, clamped", () => {
  test("fills proportionally to width", () => {
    expect(contextBar(0, 10)).toBe("░".repeat(10));
    expect(contextBar(50, 10)).toBe("▓".repeat(5) + "░".repeat(5));
    expect(contextBar(100, 10)).toBe("▓".repeat(10));
  });

  test("context overflow (pct > 100) clamps instead of crashing String.repeat with a negative", () => {
    // The bug this pins: an unclamped `width - filled` goes negative past 100% and throws.
    expect(() => contextBar(150, 10)).not.toThrow();
    expect(contextBar(150, 10)).toBe("▓".repeat(10));
    expect(contextBar(-20, 10)).toBe("░".repeat(10));
  });
});
