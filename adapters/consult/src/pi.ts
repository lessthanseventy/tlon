// The slice of pi's ExtensionAPI that consult depends on — hand-declared against pi's
// documented surface, deliberately minimal like adapters/pi/src/pi.ts: it names exactly the
// command API, the session-reader, and the message-injector this adapter uses, so a change
// in what we rely on is a change to THIS file. Type-only — erased at runtime.
//
// Sources: pi docs/extensions.md §ExtensionContext, §ExtensionCommandContext,
// §pi.registerCommand, §pi.sendUserMessage, §registerTool. The session-reader is
// ctx.sessionManager.buildContextEntries() (the active branch with compaction applied).
//
// typebox is the one import we take from a pi-bundled package (the schema lib pi uses for
// tool parameters — a peer dep, not bundled), matching adapters/lsp. The rest is hand-declared.

import { Type } from "typebox";

export interface ExtensionUI {
  setStatus(key: string, text: string): void;
  notify(message: string, level?: "info" | "warning" | "error"): void;
}

export interface SessionEntry {
  type: string;
  message?: {
    role?: string;
    content?: unknown;
  };
}

export interface SessionManager {
  // Active branch entries with compaction applied — the same view the model gets.
  buildContextEntries(): SessionEntry[];
}

export interface ExtensionContext {
  ui: ExtensionUI;
  cwd: string;
  // Read-only session state — available to ALL handlers (the doc puts ctx.sessionManager
  // on the base ExtensionContext, not just the command context). The auto-vision hook reads
  // the latest user message here to target the vision prompt at what the operator asked.
  sessionManager: SessionManager;
  // Present on active-turn handlers (tool_call, tool_result, message_update, turn_end)
  // so Esc can cancel nested async work started by the extension.
  signal?: AbortSignal;
}

// Command handlers receive this — it extends ExtensionContext with session-control methods
// that are only safe in commands (they'd deadlock from event handlers). We use isIdle to
// refuse delegation while the main agent is mid-turn; sessionManager is inherited from the
// base context (read access is safe everywhere).
export interface ExtensionCommandContext extends ExtensionContext {
  isIdle(): boolean;
}

export interface CommandOptions {
  description?: string;
  // arg completions are optional; omitted here.
  handler: (args: string, ctx: ExtensionCommandContext) => void | Promise<void>;
}

// A registered tool's execute context. Unlike lsp's (cwd/ui/signal only), the consult tool
// needs sessionManager too: context:"transcript" reads the live session the same way the
// /consult command does. pi puts sessionManager on the base ExtensionContext, so it's here.
export interface ToolExecuteContext {
  cwd: string;
  ui: ExtensionUI;
  signal?: AbortSignal;
  sessionManager: SessionManager;
}

// What a tool returns — a text result (isError distinguishes a failure the model should see).
export interface ToolResult {
  content: Array<{ type: "text"; text: string }>;
  isError?: boolean;
}

// The live-progress callback pi hands a tool's execute: call it with a partial ToolResult to
// stream output into the tool's on-screen box before the final result lands. pi's own bash
// tool uses this to show a command's output as it runs; we use it to stream the consulted
// model's answer token-by-token. Source: pi's AgentToolUpdateCallback / the built-in bash
// tool's `onUpdate({ content })` usage in dist/core/tools/bash.js.
export type ToolUpdateCallback = (update: {
  content: Array<{ type: "text"; text: string }>;
  details?: unknown;
}) => void;

export interface ToolHandler {
  execute: (
    toolCallId: string,
    params: Record<string, unknown>,
    signal: AbortSignal,
    onUpdate: ToolUpdateCallback,
    ctx: ToolExecuteContext,
  ) => Promise<ToolResult>;
}

// A read tool result that pi emits when the model can't ingest images — the text block pi's
// read tool returns verbatim: "Read image file [image/png]\n[Current model does not support
// images. The image will be omitted from this request.]". The auto-delegation hook keys on
// the "does not support images" marker and pulls the path + mime out.
export interface ToolResultEvent {
  toolName: string;
  toolCallId: string;
  // The tool's input args — for `read`, `{ path, offset?, limit? }`.
  input: unknown;
  content: unknown;
  isError?: boolean;
}

// What a tool_result handler returns to patch the result. Omitted fields keep their current
// value; we only ever replace `content` (the image-omission text → a real description).
export interface ToolResultPatch {
  content?: unknown;
  isError?: boolean;
}

export interface ExtensionAPI {
  registerCommand(name: string, options: CommandOptions): void;
  // Register a model-callable tool. The consult tool uses this to give the model the same
  // delegate as /consult, but returning the answer AS the tool result (mid-turn-safe — no
  // sendUserMessage turn to stack). See pi docs/extensions.md §registerTool.
  registerTool(opts: {
    name: string;
    label?: string;
    description: string;
    parameters: ReturnType<typeof Type.Object>;
    execute: ToolHandler["execute"];
  }): void;
  // Inject a user message into the conversation and trigger a turn — how the delegate's
  // output is handed back to the main model (it appears in the transcript and the main
  // agent responds to it). See pi docs §pi.sendUserMessage.
  sendUserMessage(text: string): void;
  // Middleware over tool results: fires after a tool runs, before the result message is
  // emitted to the model. Return a patch to modify. Used here to transparently upgrade an
  // image-omitted `read` result into a real description produced by a multimodal model.
  on(
    event: "tool_result",
    handler: (event: ToolResultEvent, ctx: ExtensionContext) => ToolResultPatch | undefined | Promise<ToolResultPatch | undefined>,
  ): void;
}

export { Type };