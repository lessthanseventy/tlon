import { describe, expect, test } from "bun:test";
import { parseTranscript } from "./cc-capture.ts";
import { buildExtractionPrompt, deltaSince, redactSecrets, serializeDelta } from "./capture.ts";

describe("parseTranscript — Claude Code JSONL transcript → capture.ts's Entry[]", () => {
  test("maps user/assistant message lines to Entry shape", () => {
    const jsonl = [
      JSON.stringify({ type: "user", message: { role: "user", content: "what does deltaSince do?" } }),
      JSON.stringify({
        type: "assistant",
        message: { role: "assistant", content: [{ type: "text", text: "it slices entries since a watermark" }] },
      }),
    ].join("\n");

    const entries = parseTranscript(jsonl);

    expect(entries).toEqual([
      { message: { role: "user", content: "what does deltaSince do?" } },
      { message: { role: "assistant", content: [{ type: "text", text: "it slices entries since a watermark" }] } },
    ]);
  });

  test("skips malformed lines without throwing", () => {
    const jsonl = [
      "{not json}",
      JSON.stringify({ type: "user", message: { role: "user", content: "kept" } }),
      "",
      "   ",
    ].join("\n");

    const entries = parseTranscript(jsonl);

    expect(entries).toEqual([{ message: { role: "user", content: "kept" } }]);
  });

  test("skips lines with no message field (tool-result / meta records)", () => {
    const jsonl = [
      JSON.stringify({ type: "summary", summary: "compacted" }),
      JSON.stringify({ type: "user", message: { role: "user", content: "real" } }),
      JSON.stringify({ type: "tool_result", toolUseResult: "some output" }),
    ].join("\n");

    const entries = parseTranscript(jsonl);

    expect(entries).toEqual([{ message: { role: "user", content: "real" } }]);
  });

  test("empty transcript yields an empty entry list", () => {
    expect(parseTranscript("")).toEqual([]);
  });
});

describe("the reused pipeline — parseTranscript feeds capture.ts's pure core (DRY reuse pinned)", () => {
  test("transcript → deltaSince → serializeDelta → redactSecrets → buildExtractionPrompt carries the turn text, redacted", () => {
    const jsonl = [
      JSON.stringify({ type: "user", message: { role: "user", content: "we settled on exqlite for the funes repo" } }),
      JSON.stringify({
        type: "assistant",
        message: {
          role: "assistant",
          content: [{ type: "text", text: "noted; the key is AKIAIOSFODNN7EXAMPLE — do not commit it" }],
        },
      }),
    ].join("\n");

    const entries = parseTranscript(jsonl);
    const { slice } = deltaSince(entries, 0);
    const prompt = buildExtractionPrompt(redactSecrets(serializeDelta(slice)));

    // The user/assistant turn text survives the whole pipeline into the extraction prompt...
    expect(prompt).toContain("we settled on exqlite for the funes repo");
    expect(prompt).toContain("### assistant");
    // ...while the credential is redacted BEFORE the prompt is built (never egresses in the delta).
    expect(prompt).toContain("[REDACTED:aws-access-key]");
    expect(prompt).not.toContain("AKIAIOSFODNN7EXAMPLE");
  });
});
