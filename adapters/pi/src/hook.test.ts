import { expect, test } from "bun:test";
import { runHook } from "./hook";

// The scaffold every claude-code hook runs under: a body that throws resolves quietly, and a
// body that hangs is cut at the ceiling — the two ways a hook could otherwise break a session.
test("runHook: a throwing body is a silent no-op", async () => {
  await expect(
    runHook(async () => {
      throw new Error("server down");
    }, 1_000),
  ).resolves.toBeUndefined();
});

test("runHook: the ceiling wins over a hung body", async () => {
  let finished = false;
  const hung = () =>
    new Promise<void>((resolve) =>
      setTimeout(() => {
        finished = true;
        resolve();
      }, 10_000),
    );
  const started = Date.now();
  await runHook(hung, 20);
  expect(Date.now() - started).toBeLessThan(5_000);
  expect(finished).toBe(false);
});

test("runHook: a body that completes in time runs to the end", async () => {
  let ran = false;
  await runHook(async () => {
    ran = true;
  }, 1_000);
  expect(ran).toBe(true);
});
