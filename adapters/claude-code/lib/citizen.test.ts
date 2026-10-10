import { describe, expect, test } from "bun:test";
import { attribution, bandParts, figureCells, gateOf, landingsOf, mentionsOf, turnWord } from "./citizen.ts";
import type { Dossier } from "./brief.ts";

const NONE = { shown: [], more: 0 };
const dossier = (over: Partial<Dossier> = {}): Dossier => ({
  thread_id: 42, goal: "ship the band", lead: "hronir", todos: NONE, next: null, learnings: NONE, unknowns: NONE,
  done: NONE, blockers: NONE, checks: NONE, recent: [], ...over,
});

describe("bandParts — the band's left half", () => {
  test("the thread and its goal, and nothing more when nothing else is on", () => {
    expect(bandParts("42", dossier())).toEqual(["#42 ship the band"]);
  });

  test("the workline's stage and gate, the last check, todos, blockers, what is red", () => {
    const d = dossier({
      workline: { stage: "review", awaiting: "lonnrot", artifact_ok: true, why: "" },
      checks: { shown: [{ passed: false, cmd: "mise run check", exit: 1, tail: null, at: null }], more: 0 },
      todos: { shown: [{ id: 1, text: "fix the band", done_at: null, at: null }], more: 2 },
      next: { id: 1, text: "fix the band", done_at: null, at: null },
      blockers: { shown: [{ id: 1, summary: "x", evidence: null, found_by: null, state: "open", at: null }], more: 0 },
    });
    expect(bandParts("42", d, 2)).toEqual(["#42 ship the band", "review ⏳lonnrot", "✗ mise run check", "todos 3 → fix the band", "blockers 1", "🔴 2"]);
  });
});

describe("gateOf — what is held before it runs", () => {
  const main = "/home/a/projects/tlon";

  test("a push goes through the server, wherever it is typed", () => {
    expect(gateOf("git push origin HEAD", "/tmp/w", main)?.decision).toBe("deny");
    expect(gateOf("make && git push -f", "/tmp/w", main)?.reason).toContain("push_branch");
  });

  test("a branch switch in the live checkout is refused; in a worktree, or a file restore, it runs", () => {
    expect(gateOf("git switch feat", main, main)?.decision).toBe("deny");
    expect(gateOf("git checkout -", `${main}/server`, main)?.decision).toBe("deny");
    expect(gateOf("git checkout feat", "/home/a/.cache/tlon-scratch/w", main)).toBeNull();
    expect(gateOf("git checkout -- lib/x.ex", main, main)).toBeNull();
  });

  test("a production write is asked, never allowed", () => {
    expect(gateOf("server/_build/prod/rel/server/bin/server rpc 'IO.puts(1)'", "/tmp", main)?.decision).toBe("ask");
    expect(gateOf("mise run release:cut", "/tmp", main)?.decision).toBe("ask");
  });

  test("everything else runs", () => {
    expect(gateOf("git status && mise run check", main, main)).toBeNull();
  });
});

test("attribution names the running model on its provider's address", () => {
  expect(attribution("glm-5.2", true)).toBe("Co-Authored-By: glm-5.2 <noreply@ollama.com>");
  expect(attribution("claude-opus-5-5", false)).toBe("Co-Authored-By: claude-opus-5-5 <noreply@anthropic.com>");
});

test("a mention is news once, from someone else, by handle not by substring", () => {
  const recent = [
    { id: 1, author: "lonnrot", body: "@hronir look", reply_to: null, at: null },
    { id: 2, author: "hronir", body: "@hronir note to self", reply_to: null, at: null },
    { id: 3, author: "yu", body: "@hronir-two is someone else", reply_to: null, at: null },
    { id: 4, author: "yu", body: "ping @HRONIR.", reply_to: null, at: null },
  ];
  expect(mentionsOf(recent, 0, "hronir").map((m) => m.id)).toEqual([1, 4]);
  expect(mentionsOf(recent, 1, "hronir").map((m) => m.id)).toEqual([4]);
});

test("a landing is a work_landed event newer than the last one seen", () => {
  const d = dossier({
    done: {
      shown: [
        { source: "event", id: 7, kind: "work_landed", summary: null, evidence: null, at: null },
        { source: "event", id: 8, kind: "check_passed", summary: null, evidence: null, at: null },
        { source: "todo", id: 9, text: "x", at: null },
      ],
      more: 0,
    },
  });
  expect(landingsOf(d, 0)).toEqual([7]);
  expect(landingsOf(d, 7)).toEqual([]);
});

test("a turn's word is stable for the turn", () => {
  expect(turnWord("t-1")).toBe(turnWord("t-1"));
  expect(typeof turnWord("t-2")).toBe("string");
});

test("a figure packs two pixel rows to a cell: ▀ over its background, a lone lower pixel as ▄, clear as a space", () => {
  const { columns, rows, cells } = figureCells(["a.", ".b", "a."], { a: "#ff0000", b: "#00ff00" });
  expect([columns, rows]).toEqual([2, 2]);
  const n = new Uint32Array(Uint8Array.from(atob(cells), (c) => c.charCodeAt(0)).buffer);
  expect(Array.from(n.slice(0, 3))).toEqual([0x2580, 0xff0000, 0x01000000]);
  expect(Array.from(n.slice(3, 6))).toEqual([0x2584, 0x00ff00, 0x01000000]);
  expect(Array.from(n.slice(6, 9))).toEqual([0x2580, 0xff0000, 0x01000000]);
  expect(Array.from(n.slice(9, 12))).toEqual([32, 0x01000000, 0x01000000]);
});
