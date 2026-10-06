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

export function doingOf(tool: string, input: unknown): Doing | undefined {
  const name = tool.replace(/^mcp__[^_]+(?:_[^_]+)*?__/, "").toLowerCase();
  if (SHELL.test(name)) {
    const command = (input as { command?: unknown } | null)?.command;
    return typeof command === "string" && SUITE.test(command) ? "test" : "bash";
  }
  return KINDS.find(([re]) => re.test(name))?.[1];
}
