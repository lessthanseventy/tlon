// adapters/lsp — the LSP tools as a stdio MCP server, for any harness: hover, definition,
// references, symbols, diagnostics and impact, each forwarded over a Unix socket to the long-lived
// adapters-lspd daemon that owns the warm language servers. A session restart leaves them warm.
//
// line/col are 1-based (editor convention); the daemon converts to 0-based for the protocol.
// MCP over stdio is newline-delimited JSON-RPC; this speaks the three methods a client needs.

import * as path from "node:path";
import { execFile } from "node:child_process";
import { LspdClient, LspdConnectionError } from "./socket.ts";
import { adapterForFile } from "../../lspd/src/adapters.ts";
import { parseDiff } from "../../lspd/src/impact.ts";

type Method = Parameters<LspdClient["request"]>[0];
type Content = { content: { type: "text"; text: string }[]; isError?: boolean };

const PATH = { path: { type: "string", description: "absolute file path" } };
const POS = {
  ...PATH,
  line: { type: "number", description: "1-based line number" },
  col: { type: "number", description: "1-based column number" },
};
const schema = (properties: Record<string, unknown>, required: string[]) => ({ type: "object", properties, required });

export const TOOLS = [
  {
    name: "hover",
    description: "LSP hover: the type/signature/doc at a (path, line, col). 1-based line/col. Routes to the file's language server (Expert for Elixir, typescript-language-server for TS, …).",
    inputSchema: schema(POS, ["path", "line", "col"]),
  },
  {
    name: "definition",
    description: "LSP go-to-definition: where the symbol at (path, line, col) is defined. Returns file:line:col locations. 1-based line/col.",
    inputSchema: schema(POS, ["path", "line", "col"]),
  },
  {
    name: "references",
    description: "LSP references: everywhere the symbol at (path, line, col) is referenced. Returns file:line:col locations. 1-based line/col.",
    inputSchema: schema(POS, ["path", "line", "col"]),
  },
  {
    name: "symbols",
    description: "LSP document symbols: the outline of a file (functions, types, modules, …) with their positions.",
    inputSchema: schema(PATH, ["path"]),
  },
  {
    name: "diagnostics",
    description: "LSP diagnostics: the server's published errors/warnings for a file (incremental, file-scoped — cheaper and finer than a full mix compile / tsc). May be empty until the server has indexed the doc.",
    inputSchema: schema(PATH, ["path"]),
  },
  {
    name: "impact",
    description:
      "Change blast-radius (first-order): for each symbol your uncommitted changes touch, the external callers that reference it. Diffs the working tree against `ref` (default HEAD). Coverage is best for Elixir and TypeScript; other languages' references may be sparse or absent.",
    inputSchema: schema({ ref: { type: "string", description: "git ref to diff against (default HEAD)" } }, []),
  },
];

const text = (t: string, isError = false): Content => ({ content: [{ type: "text", text: t }], ...(isError ? { isError } : {}) });

// `git diff --unified=0 <ref>` — the working tree against ref, hunk headers pinning the exact
// changed spans with no context lines to widen them.
function gitDiff(ref: string, cwd: string): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile("git", ["diff", "--unified=0", ref, "--"], { cwd, maxBuffer: 32 * 1024 * 1024 }, (err, stdout) => {
      if (err) reject(err instanceof Error ? err : new Error(String(err)));
      else resolve(stdout);
    });
  });
}

// A dead socket means the daemon isn't up: spawn it and retry once. An LSP error or a hung
// daemon's timeout is surfaced as-is.
async function healed(client: LspdClient, method: Method, params: Record<string, unknown>): Promise<string> {
  try {
    return await client.request(method, params);
  } catch (err) {
    if (err instanceof LspdConnectionError) return await client.selfHeal(method, params);
    throw err;
  }
}

async function impact(client: LspdClient, ref: string, cwd: string): Promise<Content> {
  // `ref` sits where git parses options: a "-O/path" or "--ext-diff" would be honored as a flag.
  if (ref.startsWith("-")) return text(`impact: invalid ref ${JSON.stringify(ref)}`, true);
  let diff: string;
  try {
    diff = await gitDiff(ref, cwd);
  } catch (err) {
    return text(`impact: git diff failed — ${err instanceof Error ? err.message : String(err)}`, true);
  }
  const byFile = parseDiff(diff);
  if (byFile.size === 0) return text(`impact: no changes vs ${ref}`);
  const sections: string[] = [];
  let skipped = 0;
  for (const [rel, ranges] of byFile) {
    const abs = path.resolve(cwd, rel);
    if (!adapterForFile(abs)) {
      skipped++;
      continue;
    }
    try {
      sections.push(`# ${rel}\n${await healed(client, "impact", { path: abs, ranges })}`);
    } catch (err) {
      sections.push(`# ${rel}\n  (impact failed: ${err instanceof Error ? err.message : String(err)})`);
    }
  }
  if (sections.length === 0) return text(`impact: changes vs ${ref} touch no LSP-supported files (${skipped} skipped)`);
  const note = skipped > 0 ? `\n\n(${skipped} non-code file${skipped === 1 ? "" : "s"} skipped)` : "";
  return text(sections.join("\n\n") + note);
}

export async function callTool(client: LspdClient, name: string, args: Record<string, unknown>, cwd: string): Promise<Content> {
  if (name === "impact") return impact(client, String(args.ref ?? "HEAD"), cwd);
  if (!TOOLS.some((t) => t.name === name)) return text(`lsp: no tool ${name}`, true);
  if (!args.path) return text("missing `path`", true);
  try {
    return text(await healed(client, name as Method, args));
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (err instanceof LspdConnectionError) return text(`lspd unavailable — ${msg} (restart the lspd daemon: kill it and the next call respawns it)`, true);
    return text(`lsp: ${msg}`, true);
  }
}

type Request = { jsonrpc: "2.0"; id?: number | string; method: string; params?: Record<string, unknown> };

// One JSON-RPC message in, its reply out; a notification gets none.
export async function handle(client: LspdClient, msg: Request, cwd: string): Promise<object | null> {
  const reply = (result: unknown) => ({ jsonrpc: "2.0", id: msg.id, result });
  switch (msg.method) {
    case "initialize":
      return reply({
        protocolVersion: (msg.params?.protocolVersion as string) ?? "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "lsp", version: "0.1.0" },
      });
    case "tools/list":
      return reply({ tools: TOOLS });
    case "tools/call": {
      const p = msg.params ?? {};
      return reply(await callTool(client, String(p.name), (p.arguments as Record<string, unknown>) ?? {}, cwd));
    }
    case "ping":
      return reply({});
    default:
      if (msg.id === undefined) return null;
      return { jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: `no method ${msg.method}` } };
  }
}

if (import.meta.main) {
  const client = new LspdClient();
  let buffer = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk: string) => {
    buffer += chunk;
    let nl: number;
    while ((nl = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, nl).trim();
      buffer = buffer.slice(nl + 1);
      if (!line) continue;
      void handle(client, JSON.parse(line) as Request, process.cwd()).then((out) => {
        if (out) process.stdout.write(`${JSON.stringify(out)}\n`);
      });
    }
  });
}
