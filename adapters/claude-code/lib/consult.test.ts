import { describe, expect, test } from "bun:test";
import { DEFAULT_MODEL, isImagePath, mimeOf, parseArgs, parseToolArgs, serializeTranscript, visionPrompt } from "./consult.ts";

describe("parseArgs — [model] <prompt>", () => {
  test("an explicit known model id is peeled off the front", () => {
    expect(parseArgs("deepseek-v4-pro am I on track?")).toEqual({ model: "deepseek-v4-pro", prompt: "am I on track?" });
  });

  test("a first token that isn't a known model is part of the prompt", () => {
    expect(parseArgs("am I on track?")).toEqual({ model: DEFAULT_MODEL, prompt: "am I on track?" });
  });

  test("empty → the default model and an empty prompt (the command says usage)", () => {
    expect(parseArgs("  ")).toEqual({ model: DEFAULT_MODEL, prompt: "" });
  });
});

describe("parseToolArgs — the consult tool's named params", () => {
  test("prompt only → the default model with the transcript", () => {
    expect(parseToolArgs({ prompt: " am I on track? " })).toEqual({ ok: true, model: DEFAULT_MODEL, context: "transcript", prompt: "am I on track?" });
  });

  test("context: none is the /fresh behavior", () => {
    expect(parseToolArgs({ prompt: "q", context: "none", model: "glm-5.2" })).toEqual({ ok: true, model: "glm-5.2", context: "none", prompt: "q" });
  });

  test("an unknown model is an error, not a silent downgrade", () => {
    const r = parseToolArgs({ prompt: "q", model: "gpt-9" });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toContain("gpt-9");
  });

  test("a missing prompt is an error", () => {
    expect(parseToolArgs({}).ok).toBe(false);
  });
});

describe("serializeTranscript — what the delegate reviews", () => {
  test("user and assistant turns become a framed transcript", () => {
    const out = serializeTranscript([
      { role: "user", text: "let's fix the bug" },
      { role: "assistant", text: "looking at cockpit.ex" },
    ]);
    expect(out).toContain("You are being consulted mid-session");
    expect(out).toContain("### user\nlet's fix the bug");
    expect(out).toContain("### assistant\nlooking at cockpit.ex");
  });

  test("earlier consult answers and the tlon brief are left out", () => {
    const out = serializeTranscript([
      { role: "user", text: "[/consult minimax-m3] old\n\nold answer" },
      { role: "user", text: "go on<tlon-brief>\nTHE BRIEF\n</tlon-brief>" },
    ]);
    expect(out).not.toContain("old answer");
    expect(out).not.toContain("THE BRIEF");
    expect(out).toContain("### user\ngo on");
  });

  test("nothing to review → empty, no preamble", () => {
    expect(serializeTranscript([])).toBe("");
  });

  test("only the most recent 40 turns are considered", () => {
    const turns = Array.from({ length: 50 }, (_, i) => ({ role: "user", text: `turn-${i}` }));
    const out = serializeTranscript(turns);
    expect(out).not.toContain("turn-9\n");
    expect(out).toContain("turn-49");
  });
});

describe("images", () => {
  test("image paths are recognised by extension", () => {
    expect(isImagePath("/tmp/shot.PNG")).toBe(true);
    expect(isImagePath("/tmp/notes.md")).toBe(false);
  });

  test("the mime follows the extension, png by default", () => {
    expect(mimeOf("a.jpeg")).toBe("image/jpeg");
    expect(mimeOf("a.weird")).toBe("image/png");
  });

  test("the vision prompt carries the operator's words, without the image's path", () => {
    const out = visionPrompt([{ role: "user", text: "why is this red? /tmp/shot.png" }]);
    expect(out).toContain("why is this red?");
    expect(out).not.toContain("/tmp/shot.png");
  });

  test("a bare paste gets the generic description", () => {
    expect(visionPrompt([{ role: "user", text: "/tmp/shot.png" }])).toContain("Describe this screenshot precisely");
  });
});
