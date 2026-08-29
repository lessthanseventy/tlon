import { describe, expect, test } from "bun:test";
import { renderBrief, type Dossier } from "./brief.ts";

// A fixed "now" so staleness is deterministic. Every `at` below is offset from it.
const NOW = new Date("2026-08-16T12:00:00Z");
const minsAgo = (m: number) => new Date(NOW.getTime() - m * 60_000).toISOString();

// The get_dossier shape funes' Funes.MCP.Brief.scope/1 returns — the contract this
// renderer consumes. Overridable per test.
function dossier(over: Partial<Dossier> = {}): Dossier {
  return {
    thread_id: 7,
    north_star: "review PR 329",
    lead: "Carl",
    todos: { shown: [], more: 0 },
    next: null,
    learnings: { shown: [], more: 0 },
    unknowns: { shown: [], more: 0 },
    done: { shown: [], more: 0 },
    blockers: { shown: [], more: 0 },
    checks: { shown: [], more: 0 },
    chatter: [],
    ...over,
  };
}

describe("renderBrief — the honest brief (pi doc §2b)", () => {
  test("the goal, the lead and the thread head the brief", () => {
    const out = renderBrief(dossier(), NOW);
    expect(out).toContain("review PR 329");
    expect(out).toContain("Carl");
    expect(out).toContain("thread 7");
  });

  test("the brief names the model that signs this session's commits (self-report)", () => {
    const out = renderBrief(dossier(), NOW, "deepseek-v4-flash");
    expect(out).toContain("You are deepseek-v4-flash (pi)");
    // An unannounced model adds no line — the brief doesn't invent an identity.
    expect(renderBrief(dossier(), NOW)).not.toContain("You are");
  });

  test("the brief nudges the agent to post its work to the thread (coordinate-via-funes)", () => {
    // The skill is loaded but a flash model reads it once and forgets; the brief is injected
    // every turn, so the one behavior that keeps the thread from going cold rides here too.
    const out = renderBrief(dossier(), NOW);
    expect(out).toContain("post_message");
  });

  test("a stated fact is the operator's own quoted words", () => {
    const out = renderBrief(
      dossier({
        learnings: {
          shown: [
            {
              id: 1,
              kind: "constraint",
              text: "tabs, not splits",
              provenance: "stated",
              check_cmd: null,
              certainty: "stated",
              at: minsAgo(10),
            },
          ],
          more: 0,
        },
      }),
      NOW,
    );
    expect(out).toContain("[stated]");
    expect(out).toContain('"tabs, not splits"');
  });

  test("a checked fact carries the command that re-runs it", () => {
    const out = renderBrief(
      dossier({
        learnings: {
          shown: [
            {
              id: 2,
              kind: "learned",
              text: "the flaky test is a race in drain/0",
              provenance: "derived",
              check_cmd: "mix test test/funes/switchboard_test.exs",
              certainty: "checked",
              at: minsAgo(10),
            },
          ],
          more: 0,
        },
      }),
      NOW,
    );
    expect(out).toContain("[checked]");
    expect(out).toContain("mix test test/funes/switchboard_test.exs");
  });

  test("an opinion renders AS a hunch — never as flat truth (anti-laundering)", () => {
    const out = renderBrief(
      dossier({
        learnings: {
          shown: [
            {
              id: 3,
              kind: "learned",
              text: "the footer flicker is probably the double repaint",
              provenance: "derived",
              check_cmd: null,
              certainty: "opinion",
              at: minsAgo(10),
            },
          ],
          more: 0,
        },
      }),
      NOW,
    );
    expect(out).toContain("[hunch]");
    expect(out.toLowerCase()).toContain("unverified");
    // The certainty markers that would launder a guess into truth must be absent.
    expect(out).not.toContain("[checked]");
    expect(out).not.toContain("[stated]");
  });

  test("an unmodeled certainty fails closed to a hunch — never an unmarked line", () => {
    const out = renderBrief(
      dossier({
        learnings: {
          shown: [
            {
              id: 9,
              kind: "learned",
              text: "some claim with a certainty we don't model",
              provenance: "derived",
              check_cmd: null,
              // funes emits a value this renderer has never seen.
              certainty: "surprise" as unknown as "opinion",
              at: minsAgo(5),
            },
          ],
          more: 0,
        },
      }),
      NOW,
    );
    expect(out).toContain("[hunch]");
    expect(out).not.toContain("undefined");
    expect(out).not.toContain("[checked]");
    expect(out).not.toContain("[stated]");
  });

  test("a capped section states its cut — every +N more (empty-world lie in miniature)", () => {
    const out = renderBrief(
      dossier({
        learnings: {
          shown: [
            {
              id: 4,
              kind: "learned",
              text: "one shown",
              provenance: "derived",
              check_cmd: "cmd",
              certainty: "checked",
              at: minsAgo(5),
            },
          ],
          more: 12,
        },
      }),
      NOW,
    );
    expect(out).toContain("12 more");
  });

  test("blockers and the DONE merge render with their evidence", () => {
    const out = renderBrief(
      dossier({
        blockers: {
          shown: [
            {
              id: 1,
              summary: "termbox NIF crashes on resize",
              evidence: "aleph pane, 2026-08-15",
              found_by: "Carl",
              state: "open",
              at: minsAgo(30),
            },
          ],
          more: 0,
        },
        done: {
          shown: [
            { source: "todo", id: 4, text: "wired the composer", at: minsAgo(5) },
            {
              source: "event",
              id: 1,
              kind: "work_landed",
              summary: "review shipped",
              evidence: "mise run check → 0 failures",
              at: minsAgo(3),
            },
          ],
          more: 0,
        },
      }),
      NOW,
    );
    expect(out).toContain("termbox NIF crashes on resize");
    expect(out).toContain("aleph pane, 2026-08-15");
    // a completed todo renders as a checked box; a work_landed event as its summary
    expect(out).toContain("[x] wired the composer");
    expect(out).toContain("review shipped");
    expect(out).toContain("mise run check → 0 failures");
  });

  test("Unknowns renders open questions with a marker and a count", () => {
    const out = renderBrief(
      dossier({
        unknowns: {
          shown: [{ id: 1, text: "does raxol support embedding?", state: "open", resolution: null, at: minsAgo(8) }],
          more: 2,
        },
      }),
      NOW,
    );
    expect(out).toContain("## Unknowns");
    expect(out).toContain("? does raxol support embedding?");
    expect(out).toContain("2 more unknowns");
  });

  test("Checks render measured pass/fail with the failing exit code", () => {
    const out = renderBrief(
      dossier({
        checks: {
          shown: [
            { passed: true, cmd: "mise run check", exit: 0, tail: "0 failures", at: minsAgo(2) },
            { passed: false, cmd: "mix test", exit: 1, tail: "1 failure", at: minsAgo(4) },
          ],
          more: 0,
        },
      }),
      NOW,
    );
    expect(out).toContain("## Checks");
    expect(out).toContain("✓ mise run check");
    expect(out).toContain("✗ mix test (exit 1)");
  });

  test("the Plan renders open todos with NEXT marked", () => {
    const out = renderBrief(
      dossier({
        todos: {
          shown: [
            { id: 1, text: "wire the composer", done_at: null, at: minsAgo(10) },
            { id: 2, text: "then the footer", done_at: null, at: minsAgo(9) },
          ],
          more: 3,
        },
        next: { id: 1, text: "wire the composer", done_at: null, at: minsAgo(10) },
      }),
      NOW,
    );
    expect(out).toContain("## Plan");
    expect(out).toContain("→ [ ] wire the composer");
    expect(out).toContain("  [ ] then the footer");
    expect(out).toContain("3 more todos");
  });

  test("the brief states its own staleness from the newest banked row (§6)", () => {
    const out = renderBrief(
      dossier({
        done: {
          shown: [
            {
              source: "event",
              id: 1,
              kind: "work_landed",
              summary: "did a thing",
              evidence: "proof",
              at: minsAgo(40),
            },
          ],
          more: 0,
        },
      }),
      NOW,
    );
    expect(out).toContain("40m ago");
    expect(out.toLowerCase()).toContain("unrecorded");
  });

  test("a thread with nothing banked says so — never a false-empty confidence", () => {
    const out = renderBrief(dossier(), NOW);
    expect(out.toLowerCase()).toContain("nothing");
    // No section headings when there is nothing under them (§6: don't teach skimming).
    expect(out).not.toContain("## What's known");
    expect(out).not.toContain("## Blockers");
  });

  test("recent chatter is carried so a fresh session has the conversation", () => {
    const out = renderBrief(
      dossier({
        chatter: [
          { id: 1, author: "andrew", body: "start with the drain race", reply_to: null, at: minsAgo(20) },
        ],
      }),
      NOW,
    );
    expect(out).toContain("andrew");
    expect(out).toContain("start with the drain race");
  });

  test("a consult ask renders as a request for an answer, not ambient chatter", () => {
    const out = renderBrief(
      dossier({
        chatter: [
          { id: 1, author: "pi", body: "is this design sound?", reply_to: null, at: minsAgo(5), consult: true },
        ],
      }),
      NOW,
    );
    expect(out).toContain("pi is consulting you — reply to answer");
    expect(out).toContain("is this design sound?");
  });
});
