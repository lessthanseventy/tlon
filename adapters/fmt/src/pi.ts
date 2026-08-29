// The slice of pi's ExtensionAPI that fmt depends on — hand-declared, minimal, type-only
// (erased at runtime), matching the adapters idiom. fmt uses only the tool_result middleware
// hook; it needs no context (formatting is fire-and-forget, no UI, no session reads).
// See pi docs/extensions.md §tool_result.

export interface ToolResultEvent {
  toolName: string;
  toolCallId: string;
  input: unknown;
  content: unknown;
  isError?: boolean;
}

export interface ToolResultPatch {
  content?: unknown;
  isError?: boolean;
}

export interface ExtensionContext {
  cwd: string;
}

export interface ExtensionAPI {
  on(
    event: "tool_result",
    handler: (event: ToolResultEvent, ctx: ExtensionContext) => ToolResultPatch | undefined | Promise<ToolResultPatch | undefined>,
  ): void;
}