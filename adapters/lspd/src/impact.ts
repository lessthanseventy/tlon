// Pure helpers for the `impact` (change blast-radius) tool — the diff→ranges parse and the
// range-overlap test, kept out of client.ts so they're unit-pinned without a live LSP server.
// The daemon (client.ts) uses rangesOverlap to pick touched symbols; the pi shim (extension.ts)
// uses parseDiff to turn `git diff` into the per-file ranges it sends the daemon.

// A 1-based, inclusive line range (editor convention) — the shape the codec carries.
export interface LineRange {
  startLine: number;
  endLine: number;
}

// Parse `git diff --unified=0` output into the NEW-file line ranges per file, keyed by the
// path as the diff writes it in `+++ b/<path>` (repo-relative). Only added/changed new lines
// matter for "what did this change touch", so we read the `+c,d` half of each `@@` hunk header
// (`+c` alone means one line; `+c,0` is a pure deletion with no new lines to attribute).
export function parseDiff(diff: string): Map<string, LineRange[]> {
  const out = new Map<string, LineRange[]>();
  let file: string | null = null;

  for (const line of diff.split("\n")) {
    if (line.startsWith("+++ ")) {
      const p = line.slice(4).trim();
      file = p === "/dev/null" ? null : p.replace(/^b\//, "");
      continue;
    }

    if (file && line.startsWith("@@")) {
      const m = /\+(\d+)(?:,(\d+))?/.exec(line);
      if (!m) continue;
      const start = parseInt(m[1]!, 10);
      const count = m[2] === undefined ? 1 : parseInt(m[2], 10);
      if (count === 0) continue; // pure deletion — no new lines
      const ranges = out.get(file) ?? [];
      ranges.push({ startLine: start, endLine: start + count - 1 });
      out.set(file, ranges);
    }
  }

  return out;
}

// Does a 0-based symbol line span (from an LSP DocumentSymbol range) overlap a 1-based
// inclusive changed range? Converts the changed range to 0-based and tests interval overlap.
export function rangesOverlap(symStartLine0: number, symEndLine0: number, r: LineRange): boolean {
  const changedStart0 = r.startLine - 1;
  const changedEnd0 = r.endLine - 1;
  return symStartLine0 <= changedEnd0 && changedStart0 <= symEndLine0;
}
