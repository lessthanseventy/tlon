import { describe, expect, test } from "bun:test";
import { parseDiff, rangesOverlap } from "./impact.ts";

describe("parseDiff — new-file line ranges from `git diff --unified=0`", () => {
  test("reads the +c,d half of each hunk, per file, stripping the b/ prefix", () => {
    const diff = [
      "diff --git a/lib/foo.ex b/lib/foo.ex",
      "index 111..222 100644",
      "--- a/lib/foo.ex",
      "+++ b/lib/foo.ex",
      "@@ -10,0 +11,3 @@ def existing do",
      "+  new line",
      "+  new line",
      "+  new line",
      "@@ -40,2 +43,1 @@",
      "+  changed",
      "diff --git a/lib/bar.ex b/lib/bar.ex",
      "--- a/lib/bar.ex",
      "+++ b/lib/bar.ex",
      "@@ -1,0 +2,1 @@",
      "+  x",
    ].join("\n");

    const got = parseDiff(diff);
    expect(got.get("lib/foo.ex")).toEqual([
      { startLine: 11, endLine: 13 },
      { startLine: 43, endLine: 43 },
    ]);
    expect(got.get("lib/bar.ex")).toEqual([{ startLine: 2, endLine: 2 }]);
  });

  test("a single-line hunk with no count (`+5`) is one line", () => {
    const diff = ["+++ b/a.ts", "@@ -5 +5 @@", "+changed"].join("\n");
    expect(parseDiff(diff).get("a.ts")).toEqual([{ startLine: 5, endLine: 5 }]);
  });

  test("a pure deletion (+c,0) attributes no new lines", () => {
    const diff = ["+++ b/a.ts", "@@ -5,3 +4,0 @@"].join("\n");
    expect(parseDiff(diff).has("a.ts")).toBe(false);
  });

  test("a deleted file (+++ /dev/null) is skipped", () => {
    const diff = ["--- a/gone.ts", "+++ /dev/null", "@@ -1,5 +0,0 @@"].join("\n");
    expect(parseDiff(diff).size).toBe(0);
  });

  test("empty diff yields an empty map", () => {
    expect(parseDiff("").size).toBe(0);
  });
});

describe("rangesOverlap — 0-based symbol span vs 1-based inclusive changed range", () => {
  test("a change inside a symbol's span overlaps", () => {
    // symbol lines 10..20 (0-based); change at 1-based 13 (→ 0-based 12) is inside.
    expect(rangesOverlap(10, 20, { startLine: 13, endLine: 13 })).toBe(true);
  });

  test("a change entirely before or after does not overlap", () => {
    expect(rangesOverlap(10, 20, { startLine: 1, endLine: 5 })).toBe(false); // 0-based 0..4, before 10
    expect(rangesOverlap(10, 20, { startLine: 30, endLine: 31 })).toBe(false); // 0-based 29.., after 20
  });

  test("boundary touch counts (change on the symbol's first/last line)", () => {
    expect(rangesOverlap(10, 20, { startLine: 11, endLine: 11 })).toBe(true); // 0-based 10 == symStart
    expect(rangesOverlap(10, 20, { startLine: 21, endLine: 21 })).toBe(true); // 0-based 20 == symEnd
  });
});
