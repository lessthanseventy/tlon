import { describe, expect, test } from "bun:test";
import {
  buildExtractionPrompt,
  deltaSince,
  parseExtraction,
  redactSecrets,
  serializeDelta,
  type Entry,
} from "./capture.ts";

const user = (text: string): Entry => ({ message: { role: "user", content: text } });
const asst = (text: string): Entry => ({ message: { role: "assistant", content: [{ type: "text", text }] } });

describe("deltaSince — capture only what's new since the watermark", () => {
  test("returns entries after the watermark and the new watermark", () => {
    const entries = [user("a"), asst("b"), user("c")];
    const { slice, nextWatermark } = deltaSince(entries, 1);
    expect(slice.map((e) => e.message?.content)).toEqual([[{ type: "text", text: "b" }], "c"]);
    expect(nextWatermark).toBe(3);
  });

  test("an up-to-date watermark yields an empty delta (nothing to capture)", () => {
    const entries = [user("a"), asst("b")];
    expect(deltaSince(entries, 2).slice).toEqual([]);
  });

  test("clamps a stale/oversized watermark rather than throwing", () => {
    expect(deltaSince([user("a")], 99).slice).toEqual([]);
  });
});

describe("serializeDelta — a role/text transcript, tool spam + brief injections dropped", () => {
  test("keeps user/assistant text, drops consult/brief re-injections", () => {
    const out = serializeDelta([
      user("real question"),
      asst("real answer"),
      user("[/consult glm-5.2] echoed"),
      user("<funes-brief>the dossier</funes-brief>"),
      { message: { role: "tool", content: "tool noise" } },
    ]);
    expect(out).toContain("### user\nreal question");
    expect(out).toContain("### assistant\nreal answer");
    expect(out).not.toContain("echoed");
    expect(out).not.toContain("dossier");
    expect(out).not.toContain("tool noise");
  });
});

describe("buildExtractionPrompt — pins the JSON contract + the kind restriction", () => {
  test("names the shape and forbids inventing constraints", () => {
    const p = buildExtractionPrompt("### user\nhi");
    expect(p).toContain('{"facts":[{"text":"...","kind":"learned","intent":"..."}],"questions":["..."]}');
    expect(p).toContain('"learned" or "decision"');
    expect(p).toContain("WHY this fact is worth keeping");
    expect(p).toContain("### user\nhi");
  });
});

describe("redactSecrets — outbound deltas never carry a credential off the box", () => {
  test("replaces the funes-mirrored credential shapes with labelled placeholders", () => {
    const delta =
      "set AKIAIOSFODNN7EXAMPLE then ghp_0123456789012345678901234567890123456789 " +
      "and sk-ant-abcdefghijklmnopqrstu";
    const got = redactSecrets(delta);
    expect(got).toContain("[REDACTED:aws-access-key]");
    expect(got).toContain("[REDACTED:github-token]");
    expect(got).toContain("[REDACTED:api-key-sk]");
    expect(got).not.toContain("AKIAIOSFODNN7EXAMPLE");
    expect(got).not.toContain("ghp_");
    expect(got).not.toContain("sk-ant-");
  });

  test("redacts every occurrence, not just the first", () => {
    const got = redactSecrets("AKIAIOSFODNN7EXAMPLE and again AKIAIOSFODNN7EXAMPLE");
    expect(got.match(/\[REDACTED:aws-access-key\]/g)?.length).toBe(2);
  });

  test("leaves legitimate technical text alone — SHAs and hashes are facts, not secrets", () => {
    const text = "commit 02562b0 fixed sha256-kG++eH pattern in flake.nix";
    expect(redactSecrets(text)).toBe(text);
  });
});

describe("parseExtraction — tolerant JSON, clamped kinds, empty on garbage", () => {
  test("parses clean minified JSON", () => {
    const got = parseExtraction('{"facts":[{"text":"exqlite sets busy_timeout via a NIF","kind":"learned"}],"questions":["does raxol embed?"]}');
    expect(got.facts).toEqual([{ text: "exqlite sets busy_timeout via a NIF", kind: "learned" }]);
    expect(got.questions).toEqual(["does raxol embed?"]);
  });

  test("finds the JSON even inside prose / code fences", () => {
    const raw = "Sure, here's the memory:\n```json\n{\"facts\":[{\"text\":\"chose Elixir\",\"kind\":\"decision\"}],\"questions\":[]}\n```\nHope that helps!";
    expect(parseExtraction(raw).facts).toEqual([{ text: "chose Elixir", kind: "decision" }]);
  });

  test("clamps any non-decision kind to learned — an extractor never mints a constraint", () => {
    const got = parseExtraction('{"facts":[{"text":"presses Enter","kind":"constraint"}],"questions":[]}');
    expect(got.facts).toEqual([{ text: "presses Enter", kind: "learned" }]);
  });

  test("drops empty-text facts and blank questions", () => {
    const got = parseExtraction('{"facts":[{"text":"  ","kind":"learned"},{"text":"keep","kind":"learned"}],"questions":["","q"]}');
    expect(got.facts).toEqual([{ text: "keep", kind: "learned" }]);
    expect(got.questions).toEqual(["q"]);
  });

  test("garbage or no JSON yields an empty extraction, never a throw", () => {
    expect(parseExtraction("the model refused")).toEqual({ facts: [], questions: [] });
    expect(parseExtraction("")).toEqual({ facts: [], questions: [] });
    expect(parseExtraction("{not json}")).toEqual({ facts: [], questions: [] });
  });

  test("pulls intent per fact", () => {
    const out = parseExtraction('{"facts":[{"text":"x","kind":"learned","intent":"why"}],"questions":[]}');
    expect(out.facts[0]?.intent).toBe("why");
  });

  test("a missing intent parses fine, leaving it undefined (tolerant parse)", () => {
    const out = parseExtraction('{"facts":[{"text":"x","kind":"learned"}],"questions":[]}');
    expect(out.facts[0]?.intent).toBeUndefined();
  });
});
