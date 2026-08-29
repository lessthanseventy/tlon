import { describe, expect, test } from "bun:test";
import { formatTarget, findMixRoot } from "./extension.ts";
import type { ToolResultEvent } from "./pi.ts";

// formatTarget is the pure decision — test it without spawning mix. The findMixRoot walk
// is exercised against the real repo layout (this file lives under modules/adapters/fmt, no
// mix.exs above it; funes/aleph do have one).

describe("formatTarget — which edits to format", () => {
  const edit = (p: string): ToolResultEvent => ({
    toolName: "edit",
    toolCallId: "c",
    input: { path: p },
    content: [],
  });

  test("an .ex edit inside a mix project → {root, rel}", () => {
    const t = formatTarget(edit("/home/andrew/projects/ficciones/modules/server/lib/funes/mcp/gateway.ex"));
    expect(t).not.toBeNull();
    expect(t!.root).toBe("/home/andrew/projects/ficciones/modules/server");
    expect(t!.rel).toBe("lib/funes/mcp/gateway.ex");
  });

  test("an .exs edit inside a mix project → formatted too", () => {
    const t = formatTarget(edit("/home/andrew/projects/ficciones/modules/console/config/runtime.exs"));
    expect(t).not.toBeNull();
    expect(t!.root).toBe("/home/andrew/projects/ficciones/modules/console");
  });

  test("a .ts edit is left alone (no formatter in the ts gate)", () => {
    expect(formatTarget(edit("/home/andrew/projects/ficciones/modules/adapters/consult/src/extension.ts"))).toBeNull();
  });

  test("a non-edit/write tool is left alone", () => {
    expect(formatTarget({ ...edit("/x.ex"), toolName: "bash" })).toBeNull();
    expect(formatTarget({ ...edit("/x.ex"), toolName: "read" })).toBeNull();
  });

  test("an .ex file with no mix.exs above it is left alone (not a mix project)", () => {
    expect(formatTarget(edit("/tmp/orphan.ex"))).toBeNull();
  });

  test("an edit with no path is left alone", () => {
    expect(formatTarget({ toolName: "edit", toolCallId: "c", input: {}, content: [] })).toBeNull();
  });
});

describe("findMixRoot — walk up to mix.exs", () => {
  test("finds the funes project root from a deep file", () => {
    expect(findMixRoot("/home/andrew/projects/ficciones/modules/server/lib/funes/mcp/gateway.ex")).toBe(
      "/home/andrew/projects/ficciones/modules/server",
    );
  });

  test("returns null when no mix.exs is above (this file's own location)", () => {
    expect(findMixRoot("/home/andrew/projects/ficciones/modules/adapters/fmt/src/extension.ts")).toBeNull();
  });
});