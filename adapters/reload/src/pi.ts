// The slice of pi's ExtensionAPI that reload depends on — hand-declared, minimal, type-only,
// matching the adapters idiom. reload registers one tool; it needs the registerTool surface and
// the execute context's cwd (to run the typecheck gate from the repo). See pi docs/extensions.md
// §registerTool. typebox is the one import we take from a pi-bundled package (the schema lib pi
// uses for tool parameters — a peer dep, not bundled).

import { Type } from "typebox";

export interface ToolExecuteContext {
  cwd: string;
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
    execute: (
      toolCallId: string,
      params: Record<string, unknown>,
      signal: AbortSignal,
      onUpdate: unknown,
      ctx: ToolExecuteContext,
    ) => Promise<ToolResult>;
  }): void;
}

export { Type };
