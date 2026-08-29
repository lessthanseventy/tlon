// The slice of pi's ExtensionAPI that lsp depends on — hand-declared, minimal, type-only,
// matching the adapters idiom. lsp registers tools (hover/definition/references/symbols/
// diagnostics); it needs the registerTool surface and the tool-execute context (cwd, signal
// so Esc can cancel an LSP request). See pi docs/extensions.md §registerTool.
//
// typebox is the one import we take from a pi-bundled package (it's the schema lib pi uses
// for tool parameters — a peer dep, not bundled). The rest is hand-declared.

import { Type } from "typebox";

export interface ExtensionUI {
  setStatus(key: string, text: string): void;
  notify(message: string, level?: "info" | "warning" | "error"): void;
}

export interface ToolExecuteContext {
  cwd: string;
  ui: ExtensionUI;
  signal?: AbortSignal;
}

// A registered tool's execute signature (the bits we use). onUpdate is omitted — lsp tools
// return a final result, no streaming.
export interface ToolHandler {
  execute: (
    toolCallId: string,
    params: Record<string, unknown>,
    signal: AbortSignal,
    onUpdate: unknown,
    ctx: ToolExecuteContext,
  ) => Promise<ToolResult>;
}

export interface ToolResult {
  content: Array<{ type: "text"; text: string }>;
  isError?: boolean;
}

export interface ExtensionAPI {
  registerTool(opts: {
    name: string;
    label?: string;
    description: string;
    parameters: ReturnType<typeof Type.Object>;
    execute: ToolHandler["execute"];
  }): void;
}

export { Type };