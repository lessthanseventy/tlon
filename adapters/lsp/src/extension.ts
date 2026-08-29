// adapters/lsp — the pi shim for the adapters-lspd sidecar. Registers the same five LSP tools
// (hover/definition/references/symbols/diagnostics) with identical names/schemas, and
// forwards each call over a Unix socket to the long-lived daemon that owns the warm
// LspClient pool. Models see zero change; a pi restart leaves the servers warm.
//
// line/col are 1-based (editor convention); the daemon converts to 0-based for the protocol.

import * as path from "node:path";
import { execFile } from "node:child_process";
import type { ExtensionAPI, ToolResult } from "./pi.ts";
import { Type } from "./pi.ts";
import { LspdClient, LspdConnectionError } from "./socket.ts";
import { adapterForFile } from "../../lspd/src/adapters.ts";
import { parseDiff } from "../../lspd/src/impact.ts";

// `git diff --unified=0 <ref>` in pi's cwd — the working tree (staged + unstaged) against ref.
// --unified=0 so hunk headers pin the exact changed line spans with no context lines to widen them.
function gitDiff(ref: string, cwd: string): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile("git", ["diff", "--unified=0", ref, "--"], { cwd, maxBuffer: 32 * 1024 * 1024 }, (err, stdout) => {
      if (err) reject(err instanceof Error ? err : new Error(String(err)));
      else resolve(stdout);
    });
  });
}

export default function lsp(pi: ExtensionAPI): void {
  const client = new LspdClient();

  const run = async (params: Record<string, unknown>, method: Parameters<LspdClient["request"]>[0]): Promise<ToolResult> => {
    const file = String(params.path ?? "");
    if (!file) return { content: [{ type: "text", text: "missing `path`" }], isError: true };
    try {
      const text = await client.request(method, params);
      return { content: [{ type: "text", text }] };
    } catch (err) {
      // A dead socket means the daemon isn't up — self-heal (spawn + retry once). A normal
      // LSP error (ok:false) or a hung-daemon timeout is surfaced as-is, no respawn.
      if (err instanceof LspdConnectionError) {
        try {
          const text = await client.selfHeal(method, params);
          return { content: [{ type: "text", text }] };
        } catch (err2) {
          const msg = err2 instanceof Error ? err2.message : String(err2);
          return { content: [{ type: "text", text: `lspd unavailable — ${msg} (mise run lspd:restart)` }], isError: true };
        }
      }
      const msg = err instanceof Error ? err.message : String(err);
      return { content: [{ type: "text", text: `lsp: ${msg}` }], isError: true };
    }
  };

  const PathParam = Type.Object({ path: Type.String({ description: "absolute file path" }) });
  const PosParam = Type.Object({
    path: Type.String({ description: "absolute file path" }),
    line: Type.Number({ description: "1-based line number" }),
    col: Type.Number({ description: "1-based column number" }),
  });

  pi.registerTool({
    name: "hover",
    description: "LSP hover: the type/signature/doc at a (path, line, col). 1-based line/col. Routes to the file's language server (Expert for Elixir, typescript-language-server for TS, …).",
    parameters: PosParam,
    execute: (_id, p) => run(p, "hover"),
  });
  pi.registerTool({
    name: "definition",
    description: "LSP go-to-definition: where the symbol at (path, line, col) is defined. Returns file:line:col locations. 1-based line/col.",
    parameters: PosParam,
    execute: (_id, p) => run(p, "definition"),
  });
  pi.registerTool({
    name: "references",
    description: "LSP references: everywhere the symbol at (path, line, col) is referenced. Returns file:line:col locations. 1-based line/col.",
    parameters: PosParam,
    execute: (_id, p) => run(p, "references"),
  });
  pi.registerTool({
    name: "symbols",
    description: "LSP document symbols: the outline of a file (functions, types, modules, …) with their positions.",
    parameters: PathParam,
    execute: (_id, p) => run(p, "symbols"),
  });
  pi.registerTool({
    name: "diagnostics",
    description: "LSP diagnostics: the server's published errors/warnings for a file (incremental, file-scoped — cheaper and finer than a full mix compile / tsc). May be empty until the server has indexed the doc.",
    parameters: PathParam,
    execute: (_id, p) => run(p, "diagnostics"),
  });

  // impact — change blast-radius. Not a per-(path,line,col) op: it diffs the working tree,
  // maps each hunk to the symbols it touches, and reports their external callers. The git diff
  // + file filtering happen here (the shim has pi's cwd); the per-file symbol/reference walk
  // happens in the daemon (the warm pool), which is why `ranges` rides the codec.
  const requestHealed = async (method: Parameters<LspdClient["request"]>[0], params: Record<string, unknown>): Promise<string> => {
    try {
      return await client.request(method, params);
    } catch (err) {
      if (err instanceof LspdConnectionError) return await client.selfHeal(method, params);
      throw err;
    }
  };

  pi.registerTool({
    name: "impact",
    description:
      "Change blast-radius (first-order): for each symbol your uncommitted changes touch, the external callers that reference it. Diffs the working tree against `ref` (default HEAD). Coverage is best for Elixir and TypeScript; other languages' references may be sparse or absent.",
    parameters: Type.Object({ ref: Type.Optional(Type.String({ description: "git ref to diff against (default HEAD)" })) }),
    execute: async (_id, p, _signal, _onUpdate, ctx): Promise<ToolResult> => {
      const ref = String((p as { ref?: unknown }).ref ?? "HEAD");
      // `ref` sits where git parses OPTIONS (before the `--`): a model-supplied "-O/path" or
      // "--ext-diff" would be honored as a flag. A real ref never starts with a dash.
      if (ref.startsWith("-")) {
        return { content: [{ type: "text", text: `impact: invalid ref ${JSON.stringify(ref)}` }], isError: true };
      }
      let diff: string;
      try {
        diff = await gitDiff(ref, ctx.cwd);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text", text: `impact: git diff failed — ${msg}` }], isError: true };
      }

      const byFile = parseDiff(diff);
      if (byFile.size === 0) return { content: [{ type: "text", text: `impact: no changes vs ${ref}` }] };

      const sections: string[] = [];
      let skipped = 0;
      for (const [rel, ranges] of byFile) {
        const abs = path.resolve(ctx.cwd, rel);
        if (!adapterForFile(abs)) {
          skipped++;
          continue;
        }
        try {
          const text = await requestHealed("impact", { path: abs, ranges });
          sections.push(`# ${rel}\n${text}`);
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          sections.push(`# ${rel}\n  (impact failed: ${msg})`);
        }
      }

      if (sections.length === 0) {
        return { content: [{ type: "text", text: `impact: changes vs ${ref} touch no LSP-supported files (${skipped} skipped)` }] };
      }
      const note = skipped > 0 ? `\n\n(${skipped} non-code file${skipped === 1 ? "" : "s"} skipped)` : "";
      return { content: [{ type: "text", text: sections.join("\n\n") + note }] };
    },
  });
}
