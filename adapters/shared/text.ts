// Shared across adapter packages by relative import (the way lsp imports lspd's codec) — no
// package of its own, so every consumer typechecks it under its own tsconfig.

// Pull the text out of a pi message's content: a string as-is, or the `{type:"text",text}`
// blocks of a content array joined with newlines (trimmed); anything else is "".
export function extractText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  const parts: string[] = [];
  for (const block of content) {
    if (
      block &&
      typeof block === "object" &&
      (block as { type?: string }).type === "text" &&
      typeof (block as { text?: string }).text === "string"
    ) {
      parts.push((block as { text: string }).text);
    }
  }
  return parts.join("\n").trim();
}
