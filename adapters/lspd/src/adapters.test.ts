import { describe, expect, test } from "bun:test";
import { adapterForFile, findRootWith, ADAPTERS } from "./adapters.ts";
import { frameMessage } from "./client.ts";

describe("frameMessage — LSP frames are byte-exact (Content-Length counts bytes, not chars)", () => {
  // A Content-Length that counts characters instead of bytes desyncs the server's framing and
  // lands its reader mid-character — Expert then crashes reading the next header with
  // {:no_translation, :unicode, :latin1}. The header must equal the body's UTF-8 byte length.
  test("multibyte payload: declared length equals the body's byte length", () => {
    const msg = { jsonrpc: "2.0", method: "textDocument/didOpen", params: { text: "Tlön — Uqbar 😀 中文" } };
    const buf = frameMessage(msg);
    const sep = buf.indexOf("\r\n\r\n");
    const declared = Number(/Content-Length: (\d+)/.exec(buf.subarray(0, sep).toString("ascii"))![1]);
    const actualBodyBytes = buf.length - (sep + 4);
    expect(declared).toBe(actualBodyBytes);
    // And bytes must exceed JS's UTF-16 code-unit count here — proving the count is of bytes.
    expect(declared).toBeGreaterThan(JSON.stringify(msg).length);
  });

  test("ASCII payload: byte length equals string length", () => {
    const msg = { jsonrpc: "2.0", id: 1, method: "textDocument/hover" };
    const buf = frameMessage(msg);
    const declared = Number(/Content-Length: (\d+)/.exec(buf.toString("ascii"))![1]);
    expect(declared).toBe(JSON.stringify(msg).length);
  });
});

// The adapter registry is the pluggable seam — test that routing + root-finding are
// correct, so adding a language (a new adapter object) can't silently break the others.
// The LSP stdio client itself is integration (a real server), not unit-tested here.

describe("adapterForFile — route a file to its language server", () => {
  const cases: Array<[string, string | null]> = [
    ["/x/lib/foo.ex", "elixir"],
    ["/x/config/runtime.exs", "elixir"],
    ["/x/lib/foo_web/index.html.heex", "elixir"],
    ["/x/src/extension.ts", "typescript"],
    ["/x/src/component.tsx", "typescript"],
    ["/x/flake.nix", "nix"],
    ["/x/scripts/tlon-cli.sh", "bash"],
    ["/x/package.json", "json"],
    ["/x/README.md", null], // markdown — no adapter (yet)
    ["/x/no-extension", null],
  ];
  for (const [file, name] of cases) {
    test(`${file} → ${name}`, () => {
      expect(adapterForFile(file)?.name ?? null).toBe(name);
    });
  }

  test("case-insensitive extension matching", () => {
    expect(adapterForFile("/x/Foo.EX")?.name).toBe("elixir");
    expect(adapterForFile("/x/Foo.TS")?.name).toBe("typescript");
  });
});

describe("findRootWith — walk up to a project marker", () => {
  test("mix.exs: finds the funes root from a deep lib file", () => {
    expect(findRootWith("/home/andrew/projects/ficciones/modules/server/lib/funes/mcp/gateway.ex", "mix.exs")).toBe(
      "/home/andrew/projects/ficciones/modules/server",
    );
  });
  test("tsconfig.json: finds the adapters/consult root", () => {
    expect(findRootWith("/home/andrew/projects/ficciones/modules/adapters/consult/src/extension.ts", "tsconfig.json")).toBe(
      "/home/andrew/projects/ficciones/modules/adapters/consult",
    );
  });
  test("flake.nix: finds the repo root from flake.nix itself", () => {
    expect(findRootWith("/home/andrew/projects/ficciones/flake.nix", "flake.nix")).toBe(
      "/home/andrew/projects/ficciones",
    );
  });
  test("null when no marker is above the file", () => {
    expect(findRootWith("/tmp/orphan.ex", "mix.exs")).toBeNull();
  });
});

describe("ADAPTERS — every adapter declares a server + extensions + a root finder", () => {
  for (const a of ADAPTERS) {
    test(`${a.name}: has command, args, extensions, rootFor, serverPackage`, () => {
      expect(a.command.length).toBeGreaterThan(0);
      expect(Array.isArray(a.args)).toBe(true);
      expect(a.extensions.length).toBeGreaterThan(0);
      expect(typeof a.rootFor).toBe("function");
      expect(a.serverPackage.length).toBeGreaterThan(0);
    });
  }
});