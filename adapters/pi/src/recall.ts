// Total-recall slice D: correction detection. When the operator corrects the agent ("don't do
// that", "use ripgrep instead", "always run the gate first"), that's a working preference worth
// remembering — so the adapter proposes it as a funes HABIT (PENDING, for the operator to approve
// in the Tlön panel). It only PROPOSES: a false positive costs one line in the review queue, never
// a silent behaviour change, which is what lets the detection be a cheap heuristic instead of an
// LLM call (the extension API exposes no inference; see the total-recall design doc).
//
// detectCorrection is pure — the whole point is that it's unit-pinned without a live session.

// The signals that a user message is a correction / durable preference, not a task request. A
// terse message carrying one of these reads as "work this way from now on."
const SIGNALS: RegExp[] = [
  /\bdon'?t\b/i,
  /\b(always|never)\b/i,
  /\binstead\b/i,
  /\bprefer\b/i,
  /\bfrom now on\b/i,
  /^\s*(no|nope|actually|stop)\b/i,
];

// A preference is terse; below this it's an interjection ("ok"), above it it's a task, not a habit.
const MIN = 8;
const MAX = 240;

// Return the proposed habit text (the correction, verbatim — the operator refines it on approval),
// or null when the message doesn't read as a correction. Length-bounded to cut obvious noise.
export function detectCorrection(prompt: string): string | null {
  const text = prompt.trim();
  if (text.length < MIN || text.length > MAX) return null;
  return SIGNALS.some((re) => re.test(text)) ? text : null;
}
