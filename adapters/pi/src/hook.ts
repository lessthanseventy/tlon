// The claude-code hook runner. Every cc-*.ts hook is a fresh bun process per fire with the same
// contract: read the hook's JSON from stdin, do its one job, and NEVER be the reason a session
// looks broken — bounded by a hard ceiling, every failure a silent no-op, always exit 0. This
// is that scaffold once, so the four hooks carry only their body and their ceiling.

// Parse the hook payload Claude Code writes to stdin. An unparseable payload is null — the hook
// treats it as "nothing to do", never as an error.
export async function readHookInput<T>(): Promise<T | null> {
  try {
    return JSON.parse(await Bun.stdin.text()) as T;
  } catch {
    return null;
  }
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Run a hook body against a ceiling: whichever finishes first wins the race, and a throw from
// the body is swallowed. If the ceiling wins mid-work the body's side effects simply stop
// where they were (each hook's own doc states what that costs it — e.g. capture re-extracts
// the same delta next turn). Resolves regardless; the entry point exits 0 on it.
export async function runHook(body: () => Promise<void>, timeoutMs: number): Promise<void> {
  try {
    await Promise.race([body(), delay(timeoutMs)]);
  } catch {
    // silent no-op — a hook must never surface a failure or block the session
  }
}
