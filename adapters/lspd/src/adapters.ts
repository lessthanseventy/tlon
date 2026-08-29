// The language adapter registry — the pluggable seam. Adding a language is one object here:
// { name, command, the extensions it owns, how to find its project root, serverPackage }.
// The extension routes a file to its adapter by extension; LspClient spawns/reuses the
// adapter's server per project root. If a server binary isn't on PATH, the tool surfaces a
// clear error rather than hanging.
//
// Expert (expert-lsp.org) is the Elixir server here — the current standard, not elixir-ls.

import * as fs from "node:fs";
import * as path from "node:path";

export interface LanguageAdapter {
  name: string;
  // The LSP server command + args. `--stdio` is the common transport; the client speaks
  // the LSP base protocol (Content-Length framing) over the child's stdio.
  command: string;
  args: string[];
  // File extensions this adapter owns (lowercase, no dot). Used to route a file to a server.
  extensions: string[];
  // Find the project root for a file — the dir the server should run in and that scopes
  // its index. null when no root marker is found (the tool then declines).
  rootFor: (file: string) => string | null;
  // A human label for "server not found" messages.
  serverPackage: string;
}

// Walk up from the file to the nearest marker file (capped — a project root is never deep).
export function findRootWith(file: string, marker: string): string | null {
  let dir = path.dirname(file);
  for (let i = 0; i < 16; i++) {
    if (fs.existsSync(path.join(dir, marker))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

export const ADAPTERS: LanguageAdapter[] = [
  {
    name: "elixir",
    command: "expert",
    args: ["--stdio"],
    extensions: ["ex", "exs", "heex", "eex", "leex"],
    rootFor: (f) => findRootWith(f, "mix.exs"),
    serverPackage: "Expert (expert-lsp.org — `expert` on PATH)",
  },
  {
    name: "typescript",
    command: "typescript-language-server",
    args: ["--stdio"],
    extensions: ["ts", "tsx", "mts", "cts", "js", "jsx", "mjs", "cjs"],
    rootFor: (f) => findRootWith(f, "tsconfig.json"),
    serverPackage: "typescript-language-server",
  },
  {
    name: "nix",
    command: "nil",
    args: [],
    extensions: ["nix"],
    rootFor: (f) => findRootWith(f, "flake.nix") ?? path.dirname(f),
    serverPackage: "nil (the Nix LSP)",
  },
  {
    name: "bash",
    command: "bash-language-server",
    args: ["start"],
    extensions: ["sh", "bash"],
    rootFor: (f) => path.dirname(f),
    serverPackage: "bash-language-server",
  },
  {
    name: "json",
    command: "vscode-json-language-server",
    args: ["--stdio"],
    extensions: ["json"],
    rootFor: (f) => path.dirname(f),
    serverPackage: "vscode-json-language-server",
  },
];

// Route a file to its adapter by extension. Pure — pinned by tests.
export function adapterForFile(file: string): LanguageAdapter | null {
  const ext = file.toLowerCase().split(".").pop() ?? "";
  return ADAPTERS.find((a) => a.extensions.includes(ext)) ?? null;
}