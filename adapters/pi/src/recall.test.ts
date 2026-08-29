import { describe, expect, test } from "bun:test";
import { detectCorrection } from "./recall.ts";

describe("detectCorrection — a correction reads as a durable preference to propose", () => {
  test("catches the common correction shapes", () => {
    expect(detectCorrection("don't use tabs, use spaces")).toBe("don't use tabs, use spaces");
    expect(detectCorrection("always run mise run check before committing")).toBe("always run mise run check before committing");
    expect(detectCorrection("use ripgrep instead of grep")).toBe("use ripgrep instead of grep");
    expect(detectCorrection("no, parse the header as bytes not chars")).toBe("no, parse the header as bytes not chars");
    expect(detectCorrection("prefer the Claude bucket")).toBe("prefer the Claude bucket");
    expect(detectCorrection("from now on, branch before committing")).toBe("from now on, branch before committing");
  });

  test("trims surrounding whitespace", () => {
    expect(detectCorrection("  never force-push to main  ")).toBe("never force-push to main");
  });

  test("ignores ordinary requests and interjections (no signal)", () => {
    expect(detectCorrection("can you help me with this function?")).toBeNull();
    expect(detectCorrection("what does this do?")).toBeNull();
    expect(detectCorrection("thanks, that works")).toBeNull();
  });

  test("ignores too-short and too-long messages even with a signal word", () => {
    expect(detectCorrection("no")).toBeNull(); // below the floor
    const long = "actually " + "x".repeat(300);
    expect(detectCorrection(long)).toBeNull(); // above the ceiling — that's a task, not a habit
  });
});
