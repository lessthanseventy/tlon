// A minimal LSP client over stdio — Content-Length-framed JSON-RPC. One LspClient per
// (adapter, project root): spawned once, initialized, then reused for every request under
// that root; the extension holds the cache.
//
// Deliberately small, not a general LSP framework: initialize, textDocument/didOpen, and
// the four requests we expose. publishDiagnostics notifications are collected per-file so
// `diagnostics` can return them without a round-trip. Every request has a timeout — an LSP
// server must never hang the agent; any failure throws.

import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import * as fs from "node:fs";
import { rangesOverlap, type LineRange } from "./impact.ts";

export interface LspPosition {
  line: number; // 0-based
  character: number; // 0-based
}

export interface LspLocation {
  uri: string;
  range: { start: LspPosition; end: LspPosition };
}

export class LspError extends Error {}

interface Pending {
  resolve: (result: unknown) => void;
  reject: (err: unknown) => void;
  timer: ReturnType<typeof setTimeout>;
}

export class LspClient {
  #proc: ChildProcessWithoutNullStreams;
  #buf = "";
  #nextId = 1;
  #pending = new Map<number, Pending>();
  // textDocument uris we've sent didOpen for, with the on-disk identity of what we sent. The
  // daemon outlives pi sessions, and per LSP an opened doc means "the CLIENT owns the text" —
  // the server ignores disk from then on. With didChange unadvertised, a long-lived daemon
  // would answer hover/references/impact against the text as of first open, forever. So each
  // openDoc stats the file and, when disk moved on, closes + reopens with the fresh text.
  #open = new Map<string, { mtimeMs: number; size: number }>();
  #diagnostics = new Map<string, Array<{ severity: number; message: string; range: { start: LspPosition; end: LspPosition } }>>();
  #disposed = false;
  #root: string;

  constructor(command: string, args: string[], root: string) {
    this.#root = root;
    try {
      this.#proc = spawn(command, args, { cwd: root, stdio: ["pipe", "pipe", "pipe"] });
    } catch (err) {
      throw new LspError(`failed to spawn ${command}: ${err instanceof Error ? err.message : String(err)}`);
    }
    this.#proc.stdout.setEncoding("utf-8");
    this.#proc.stdout.on("data", (chunk: string) => this.#onData(chunk));
    this.#proc.on("exit", (code) => {
      if (!this.#disposed) {
        // Server died unexpectedly — fail any pending requests so the tool errors, not hangs.
        for (const p of this.#pending.values()) {
          clearTimeout(p.timer);
          p.reject(new LspError(`${command} exited (code ${code})`));
        }
        this.#pending.clear();
      }
    });
  }

  // The initialize handshake + the initialized notification. Must be the first call.
  async initialize(): Promise<void> {
    const result = await this.#request("initialize", {
      processId: process.pid,
      rootUri: uri(this.#root),
      capabilities: {
        textDocument: {
          hover: { contentFormat: ["markdown", "plaintext"] },
          synchronization: { didOpen: true, didChange: false, didSave: false },
          publishDiagnostics: { relatedInformation: false },
        },
      },
    });
    // Some servers send diagnostics before initialized; the notification is still required.
    void result;
    this.#notify("initialized", {});
  }

  // Open a file in the server, re-opening when disk changed since we last sent it (see #open).
  // Idempotent for an unchanged file: one didOpen per uri. The server indexes it and emits
  // publishDiagnostics, which we collect.
  openDoc(absPath: string): void {
    const textDoc = uri(absPath);
    const stat = fs.statSync(absPath);
    const seen = this.#open.get(textDoc);
    if (seen && seen.mtimeMs === stat.mtimeMs && seen.size === stat.size) return;
    if (seen) this.#notify("textDocument/didClose", { textDocument: { uri: textDoc } });
    const text = fs.readFileSync(absPath, "utf-8");
    this.#notify("textDocument/didOpen", {
      textDocument: { uri: textDoc, languageId: langId(absPath), version: 1, text },
    });
    this.#open.set(textDoc, { mtimeMs: stat.mtimeMs, size: stat.size });
  }

  async hover(absPath: string, pos: LspPosition): Promise<string> {
    this.openDoc(absPath);
    const r = await this.#request("textDocument/hover", {
      textDocument: { uri: uri(absPath) },
      position: pos,
    });
    return stringifyHover(r);
  }

  async definition(absPath: string, pos: LspPosition): Promise<string> {
    this.openDoc(absPath);
    const r = await this.#request("textDocument/definition", {
      textDocument: { uri: uri(absPath) },
      position: pos,
    });
    return stringifyLocations(r);
  }

  async references(absPath: string, pos: LspPosition): Promise<string> {
    const locs = await this.#referencesRaw(absPath, pos);
    return locs.length === 0 ? "(no results)" : locs.map(fmtLoc).join("\n");
  }

  async documentSymbol(absPath: string): Promise<string> {
    return stringifySymbols(await this.#documentSymbolsRaw(absPath));
  }

  // Structured references — the location list, before rendering. Shared by `references`
  // (which stringifies) and `impact` (which walks them).
  async #referencesRaw(absPath: string, pos: LspPosition): Promise<LspLocation[]> {
    this.openDoc(absPath);
    const r = await this.#request("textDocument/references", {
      textDocument: { uri: uri(absPath) },
      position: pos,
      context: { includeDeclaration: true },
    });
    if (!r) return [];
    return Array.isArray(r) ? (r as LspLocation[]) : [r as LspLocation];
  }

  // Structured document symbols — the outline before rendering.
  async #documentSymbolsRaw(absPath: string): Promise<DocumentSymbol[]> {
    this.openDoc(absPath);
    const r = await this.#request("textDocument/documentSymbol", {
      textDocument: { uri: uri(absPath) },
    });
    return Array.isArray(r) ? (r as DocumentSymbol[]) : [];
  }

  // Change blast-radius, first-order: for each symbol whose span overlaps a changed line
  // range, the EXTERNAL references to it (its callers) — the definition site and uses within
  // the symbol's own body are filtered out, leaving the reach of the change. References are
  // resolved at the symbol's NAME (`selectionRange`), not its `range` start (the `def`/`function`
  // keyword), so the language server actually binds the identifier.
  async impact(absPath: string, ranges: LineRange[]): Promise<string> {
    const touched = flattenSymbols(await this.#documentSymbolsRaw(absPath)).filter(
      (s) => s.range && ranges.some((r) => rangesOverlap(s.range!.start.line, s.range!.end.line, r)),
    );
    if (touched.length === 0) return "(no symbols touched by the change)";

    const sections: string[] = [];
    for (const s of touched) {
      const namePos = (s.selectionRange ?? s.range!).start;
      const refs = await this.#referencesRaw(absPath, namePos);
      const external = refs.filter((l) => !withinOwnBody(l, absPath, s.range!));
      const header = `${symKind(s.kind)} ${s.name} (${s.range!.start.line + 1}) — ${external.length} caller${external.length === 1 ? "" : "s"}`;
      const shown = external.slice(0, 20).map((l) => "  " + fmtLoc(l));
      const more = external.length > 20 ? [`  … ${external.length - 20} more`] : [];
      sections.push([header, ...shown, ...more].join("\n"));
    }
    return sections.join("\n\n");
  }

  // The latest diagnostics the server has published for a file (collected from
  // publishDiagnostics notifications). Empty until the server has indexed the doc.
  diagnostics(absPath: string): string {
    const list = this.#diagnostics.get(uri(absPath)) ?? [];
    if (list.length === 0) return "(no diagnostics published yet — server may still be indexing)";
    return list
      .map((d) => {
        const sev = ["Error", "Warning", "Information", "Hint"][d.severity - 1] ?? "Diagnostic";
        return `${sev} at ${d.range.start.line + 1}:${d.range.start.character + 1} — ${d.message}`;
      })
      .join("\n");
  }

  // Stop the server. Called when the extension is done with it (or on a timeout sweep).
  dispose(): void {
    if (this.#disposed) return;
    this.#disposed = true;
    try {
      this.#notify("shutdown", {});
      void this.#request("exit", {}).catch(() => {});
    } catch {
      /* best-effort */
    }
    this.#proc.kill("SIGTERM");
  }

  #onData(chunk: string): void {
    this.#buf += chunk;
    // Parse as many complete frames as the buffer holds.
    for (;;) {
      const headerEnd = this.#buf.indexOf("\r\n\r\n");
      if (headerEnd < 0) return;
      const headers = this.#buf.slice(0, headerEnd);
      const m = /content-length:\s*(\d+)/i.exec(headers);
      if (!m) {
        // Unframed junk — drop the headers and continue (some servers print a banner).
        this.#buf = this.#buf.slice(headerEnd + 4);
        continue;
      }
      const len = parseInt(m[1]!, 10);
      const bodyStart = headerEnd + 4;
      if (this.#buf.length < bodyStart + len) return; // wait for the full body
      const body = this.#buf.slice(bodyStart, bodyStart + len);
      this.#buf = this.#buf.slice(bodyStart + len);
      this.#dispatch(body);
    }
  }

  #dispatch(body: string): void {
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(body);
    } catch {
      return; // malformed frame — ignore
    }
    if (msg.method === "textDocument/publishDiagnostics" && !("id" in msg)) {
      const params = msg.params as { uri: string; diagnostics: Array<{ severity: number; message: string; range: { start: LspPosition; end: LspPosition } }> };
      this.#diagnostics.set(params.uri, params.diagnostics);
      return;
    }
    // A request FROM the server — it carries BOTH a method and an id (a response to our request
    // has an id but no method; a notification has a method but no id). Servers send
    // client/registerCapability and window/workDoneProgress/create this way right after
    // `initialized`. Per LSP the client MUST reply, and Expert issues them as a synchronous
    // GenServer.call(..., :infinity) on its protocol buffer — leaving one unanswered deadlocks
    // EVERY subsequent request on the connection (the 15s hover/symbol/diagnostic timeouts). We
    // register no dynamic capabilities and drive no progress UI, so a null result is the correct,
    // complete reply. Ack generically.
    if (typeof msg.method === "string" && "id" in msg) {
      this.#write({ jsonrpc: "2.0", id: msg.id, result: null });
      return;
    }
    if (typeof msg.id === "number" && this.#pending.has(msg.id)) {
      const p = this.#pending.get(msg.id)!;
      this.#pending.delete(msg.id);
      clearTimeout(p.timer);
      if (msg.error) p.reject(new LspError(JSON.stringify(msg.error)));
      else p.resolve(msg.result);
    }
  }

  #request(method: string, params: unknown, timeoutMs = 15_000): Promise<unknown> {
    return new Promise((resolve, reject) => {
      if (this.#disposed) {
        reject(new LspError(`${method}: server disposed`));
        return;
      }
      const id = this.#nextId++;
      const timer = setTimeout(() => {
        this.#pending.delete(id);
        reject(new LspError(`${method} timed out after ${timeoutMs}ms`));
      }, timeoutMs);
      this.#pending.set(id, { resolve, reject, timer });
      this.#write({ jsonrpc: "2.0", id, method, params });
    });
  }

  #notify(method: string, params: unknown): void {
    this.#write({ jsonrpc: "2.0", method, params });
  }

  #write(msg: Record<string, unknown>): void {
    // One byte-exact frame, written as a single Buffer — see frameMessage.
    this.#proc.stdin.write(frameMessage(msg));
  }
}

// The LSP wire frame for a message: an ASCII `Content-Length` header followed by the body as
// UTF-8 bytes. LSP is BYTE-framed — the header counts bytes, and the receiver reads exactly
// that many bytes for the body. So the count and the bytes we put on the wire must be identical.
// Building the body as an explicit UTF-8 Buffer (rather than writing a string and trusting the
// stream's default encoding) guarantees that: `body.length` IS what gets sent, whatever the
// pipe's encoding happens to be. A mismatch here — Content-Length off by even one byte for a
// multibyte character — desyncs the server's framing, landing its reader mid-character on the
// next header. Expert reads that header through a Unicode char reader and crashes with
// `{:no_translation, :unicode, :latin1}`, wedging every subsequent request. Kept pure + exported
// so the bytes-not-chars invariant is unit-tested without a live server.
export function frameMessage(msg: Record<string, unknown>): Buffer {
  const body = Buffer.from(JSON.stringify(msg), "utf-8");
  const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, "ascii");
  return Buffer.concat([header, body]);
}

function uri(absPath: string): string {
  return "file://" + absPath;
}

// The languageId the server expects for didOpen. Rough but works for the languages we serve.
function langId(absPath: string): string {
  const ext = absPath.toLowerCase().split(".").pop() ?? "";
  if (["ex", "exs"].includes(ext)) return "elixir";
  if (["heex", "eex", "leex"].includes(ext)) return "eex";
  if (["ts", "tsx", "mts", "cts"].includes(ext)) return "typescript";
  if (["js", "jsx", "mjs", "cjs"].includes(ext)) return "javascript";
  if (ext === "nix") return "nix";
  if (["sh", "bash"].includes(ext)) return "shellscript";
  if (ext === "json") return "json";
  return "plaintext";
}

function stringifyHover(result: unknown): string {
  if (!result) return "(no hover info)";
  const hover = result as { contents?: unknown };
  const c = hover.contents;
  if (typeof c === "string") return c;
  if (c && typeof c === "object" && "value" in c) return String((c as { value: string }).value);
  if (Array.isArray(c)) return c.map(stringifyHover).join("\n\n");
  return JSON.stringify(c);
}

function stringifyLocations(result: unknown): string {
  if (!result) return "(no results)";
  const locs = Array.isArray(result) ? (result as LspLocation[]) : [result as LspLocation];
  if (locs.length === 0) return "(no results)";
  return locs.map(fmtLoc).join("\n");
}

// One `file:line:col` location line, 1-based (the editor convention the tools present).
function fmtLoc(l: LspLocation): string {
  return `${l.uri.replace(/^file:\/\//, "")}:${l.range.start.line + 1}:${l.range.start.character + 1}`;
}

// Flatten a DocumentSymbol tree (a module's functions, a class's methods) to one list — impact
// tests every symbol at any depth for overlap with the change.
function flattenSymbols(syms: DocumentSymbol[]): DocumentSymbol[] {
  const out: DocumentSymbol[] = [];
  for (const s of syms) {
    out.push(s);
    if (s.children) out.push(...flattenSymbols(s.children));
  }
  return out;
}

// Is a reference the symbol's own definition or an internal use (same file, inside its span)?
// Those aren't blast radius — the reach is the EXTERNAL callers, so impact filters them out.
function withinOwnBody(l: LspLocation, absPath: string, range: { start: LspPosition; end: LspPosition }): boolean {
  const file = l.uri.replace(/^file:\/\//, "");
  return file === absPath && l.range.start.line >= range.start.line && l.range.start.line <= range.end.line;
}

function stringifySymbols(result: unknown): string {
  if (!result || !Array.isArray(result)) return "(no symbols)";
  const syms = result as Array<DocumentSymbol>;
  if (syms.length === 0) return "(no symbols)";
  return syms.map((s) => renderSymbol(s, 0)).join("\n");
}

// A DocumentSymbol nests its members (a module's functions, a class's methods) as
// `children` — recurse so the outline shows them, indented, not just the top level.
function renderSymbol(s: DocumentSymbol, depth: number): string {
  const pad = "  ".repeat(depth);
  const line = `${pad}${symKind(s.kind)} ${s.name}${s.range ? ` (${s.range.start.line + 1}:${s.range.start.character + 1})` : ""}`;
  const children = (s.children ?? []).map((c) => renderSymbol(c, depth + 1)).join("\n");
  return children ? `${line}\n${children}` : line;
}

interface DocumentSymbol {
  name: string;
  kind: number;
  // `range` is the symbol's full span (used for overlap + own-body filtering); `selectionRange`
  // is just the name (where `references` must be resolved so the server binds the identifier).
  range?: { start: LspPosition; end: LspPosition };
  selectionRange?: { start: LspPosition };
  children?: DocumentSymbol[];
}

function symKind(k: number): string {
  return (
    [, "File", "Module", "Namespace", "Package", "Class", "Method", "Property", "Field", "Constructor", "Enum", "Interface", "Function", "Variable", "Constant", "String", "Number", "Boolean", "Array"][k] ?? "Symbol"
  );
}