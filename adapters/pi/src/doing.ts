// What a tool call looks like from across the office (`presence_doing`): the server's closed set
// of kinds, read off a tool's name — pi's built-ins, Claude Code's, and MCP tools by their own
// name — so both adapters show the same animation for the same work. Unknown is plain thinking.
export type Doing = "read" | "edit" | "bash" | "search" | "web" | "test" | "delegate";

const SHELL = /^(bash|shell|powershell|exec)$/;
const SUITE = /\b(test|check|pytest|vitest|jest|rspec|precommit)\b/;
const KINDS: [RegExp, Doing][] = [
  [/^(agent|task|consult|delegate|staff_child|spawn_crew|ask)/, "delegate"],
  [/^web|fetch|browser/, "web"],
  [/^(grep|glob|find|search|lsp)/, "search"],
  [/^(edit|write$|multiedit|notebookedit|rename|patch|apply)/, "edit"],
  [/^(read|view|ls$|outline|get_|list_)/, "read"],
];

const MCP_PREFIX = /^mcp__[^_]+(?:_[^_]+)*?__/;

export function doingOf(tool: string, input: unknown): Doing | undefined {
  const name = tool.replace(MCP_PREFIX, "").toLowerCase();
  if (SHELL.test(name)) {
    const command = (input as { command?: unknown } | null)?.command;
    return typeof command === "string" && SUITE.test(command) ? "test" : "bash";
  }
  return KINDS.find(([re]) => re.test(name))?.[1];
}

// The one input field that says what a tool call is aimed at, by preference: never a field that
// carries contents (a file's text, an edit's strings, a prompt), so a summary cannot leak them.
const TARGETS = ["command", "file_path", "notebook_path", "url", "query", "pattern", "path", "description"];
const SECRETS: [RegExp, string][] = [
  [/\b(bearer|basic|token)\s+\S+/gi, "$1 …"],
  [/\b([A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD)[A-Z0-9_]*|token|key|secret|password|passwd|api[_-]?key)=\S+/gi, "$1=…"],
  [/\b(?:sk|pk|rk|ghp|gho|ghs|ghu|github_pat|glpat|xox[abpr]|AKIA)[-_][A-Za-z0-9_-]{8,}/g, "…"],
  [/[A-Za-z0-9+_-]{40,}/g, "…"],
];
const MAX = 120;

/**
 * A tool call as the activity feed's one line — "Bash · mise run check", "Read · lib/x.ex" — the
 * tool and its target, a path made relative to `cwd`, one line, capped, credentials redacted. A
 * tool with no target field (an MCP verb) is just its name.
 */
export function summaryOf(tool: string, input: unknown, cwd: string): string {
  const bare = tool.replace(MCP_PREFIX, "");
  const name = bare === tool ? bare.charAt(0).toUpperCase() + bare.slice(1) : bare;
  const args = (input ?? {}) as Record<string, unknown>;
  const raw = TARGETS.map((k) => args[k]).find((v): v is string => typeof v === "string" && v.trim() !== "");
  if (!raw) return name;
  const base = cwd.endsWith("/") ? cwd : `${cwd}/`;
  let target = raw.startsWith(base) ? raw.slice(base.length) : raw;
  target = target.trim().replace(/\s*\n\s*/g, " ⏎ ");
  for (const [re, by] of SECRETS) target = target.replace(re, by);
  const line = `${name} · ${target}`;
  return line.length > MAX ? `${line.slice(0, MAX - 1)}…` : line;
}
