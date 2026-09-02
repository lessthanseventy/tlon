// The slice of pi's ExtensionAPI the footer uses — hand-declared against pi's documented
// surface (github.com/earendil-works/pi), deliberately minimal, type-only (erased at runtime).
// When pi publishes its own types, this is what to replace with them.
//
// The footer needs the reactive footer API (setFooter + FooterData), the model/context/session
// readers it renders from, and the theme. It shares no types with the server adapter's pi.ts —
// the footer is its own package precisely so it doesn't ride on the server's surface.

import type { AssistantMessage } from "@earendil-works/pi-ai";

export interface FooterData {
  getGitBranch(): string | null;
  getExtensionStatuses(): ReadonlyMap<string, string>;
  onBranchChange(cb: () => void): () => void;
}

export interface FooterComponent {
  render(width: number): string[];
  invalidate(): void;
  dispose?: () => void;
}

export interface ContextUsage {
  tokens: number;
  percent: number | null;
  contextWindow: number;
}

export interface Model {
  id: string;
  provider: string;
  contextWindow: number;
}

export interface TUI {
  requestRender(): void;
}

export interface Theme {
  fg(color: string, text: string): string;
  bg(color: string, text: string): string;
  bold(text: string): string;
}

export interface ExtensionUI {
  // A one-line footer status (keyed; re-call to replace).
  setStatus(key: string, text: string): void;
  // Replace the built-in footer with a custom component.
  setFooter(factory: ((tui: TUI, theme: Theme, footerData: FooterData) => FooterComponent) | undefined): void;
  theme: Theme;
}

export interface SessionManager {
  getEntries(): SessionEntry[];
  getBranch(): SessionEntry[];
}

export interface SessionEntry {
  type: string;
  message: AssistantMessage;
}

export interface ExtensionContext {
  ui: ExtensionUI;
  cwd: string;
  model: Model | undefined;
  sessionManager: SessionManager;
  getContextUsage(): ContextUsage | null;
}

export interface SessionStartEvent {
  // "startup" | "reload" | "new" | "resume" | "fork"
  reason: string;
  previousSessionFile?: string;
}

export interface ExtensionAPI {
  on(
    event: "session_start",
    handler: (event: SessionStartEvent, ctx: ExtensionContext) => void | Promise<void>,
  ): void;
  getThinkingLevel(): string;
}
