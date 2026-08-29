// The slice of pi's ExtensionAPI that adapters actually uses — hand-declared against pi's
// documented surface (github.com/earendil-works/pi, packages/coding-agent/docs), and
// deliberately minimal: it names exactly the hooks and ctx methods this adapter depends
// on, so a change in what we rely on is a change to THIS file. When pi publishes its own
// types, this is what to replace with them. Type-only — erased at runtime.

export interface ExtensionUI {
  // A one-line footer status (keyed; re-call to replace).
  setStatus(key: string, text: string): void;
  // A multi-line block above the editor (keyed; re-call with the same key to update).
  setWidget(key: string, lines: string[]): void;
  // A transient toast.
  notify(message: string, level?: "info" | "warning" | "error"): void;
}

// The session reader capture needs — the running context entries, same source /consult serializes
// (buildContextEntries). Typed to just what capture.ts consumes.
export interface SessionManager {
  buildContextEntries(): Array<{ message?: { role?: string; content?: unknown } }>;
}

export interface ExtensionContext {
  ui: ExtensionUI;
  cwd: string;
  sessionManager: SessionManager;
}

export interface SessionStartEvent {
  // "startup" | "reload" | "new" | "resume" | "fork"
  reason: string;
  previousSessionFile?: string;
}

export interface BeforeAgentStartEvent {
  prompt: string;
  systemPrompt: string;
}

// A message injected into the session and sent to the model — the brief's vehicle.
export interface InjectedMessage {
  customType: string;
  content: string;
  display?: boolean;
}

export interface BeforeAgentStartResult {
  message?: InjectedMessage;
  systemPrompt?: string;
}

export interface ExtensionAPI {
  on(
    event: "session_start",
    handler: (event: SessionStartEvent, ctx: ExtensionContext) => void | Promise<void>,
  ): void;
  on(
    event: "before_agent_start",
    handler: (
      event: BeforeAgentStartEvent,
      ctx: ExtensionContext,
    ) => BeforeAgentStartResult | undefined | Promise<BeforeAgentStartResult | undefined>,
  ): void;
  on(event: "turn_start", handler: (event: unknown, ctx: ExtensionContext) => void | Promise<void>): void;
  on(event: "turn_end", handler: (event: unknown, ctx: ExtensionContext) => void | Promise<void>): void;
  // Boundary hooks for total-recall capture: before the context is compacted (the key moment to
  // flush the delta) and at session end (best-effort final flush).
  on(event: "session_before_compact", handler: (event: unknown, ctx: ExtensionContext) => void | Promise<void>): void;
  on(event: "session_shutdown", handler: (event: unknown, ctx: ExtensionContext) => void | Promise<void>): void;
}
