# Plan: Argos fetches the newspaper

Two tasks, each its own commit. Spec: `work/whimsy-argos-fetches-the-newspaper/spec.md`.

## Task 1 — failing test

**File:** `office/test/pets.test.ts`

1. Add the import (new line after line 4, before the `WideRoom` import — keeps the existing
   alphabetical-ish grouping by source module):

   ```ts
   import { ARGOS } from "../kit/pets"
   ```

2. Add this test inside the `describe("the pets talk", ...)` block, directly after the
   `"someone idling near Nina makes a fuss of her…"` test (currently `pets.test.ts:65-75`) and
   before the `"the server's lines come first…"` test:

   ```ts
   test("Argos sometimes fetches the newspaper and brings it to your office", () => {
     const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1), pets = room as unknown as Pets
     chance(0.999, () => { for (let i = 0; i < 3_000 && (i < 600 || pets.dog.mode === "sleep" || pets.dog.path.length); i++) room.step(a) })
     chance(0, () => room.step(a))
     expect(pets.dog.mode).toBe("walk")
     expect(ARGOS.paper).toContain(pets.dog.said)
     expect(balloons(room, a).some((b) => b.t === "balloon" && b.cx === pets.dog.x)).toBe(true)
   })
   ```

**Verify (must be RED):**

```
mise run office:test -- pets.test.ts
```

Expect two failures: `ARGOS.paper` is `undefined` (TS: won't even compile clean under
`office:check`'s typecheck — that's fine, this task's job is just to get the test file in place
and confirm it fails for the right reason) and/or `pets.dog.mode` not `"walk"`.

**Commit:** test only, no implementation.

```
git add office/test/pets.test.ts
git commit -m "test: Argos sometimes fetches the newspaper (red)"
```

## Task 2 — make it pass

**File:** `office/kit/pets.ts`

In the `ARGOS` object, add a `paper` entry after `rally` and before the `fuss` key
(`pets.ts:35-36`):

```ts
  rally: ["BALL. Ball ball ball. BALL.", "Left! Right! Left! I can't take it!"],
  paper: ["The morning news! I fetch it like a trophy from Troy!", "Dispatches! Sing, O Muse, of the evening edition!", "I bring news. I do not read it. Reading is for the gods."],
  fuss: {
```

**File:** `office/rooms/wide.ts`

In `step()`, immediately after the existing muse-chime line (`wide.ts:194`):

```ts
    if (this.dog.mode !== "sleep" && this.quiet(this.dog.saidUntil) && Math.random() < 1 / 1800) this.dogSay(this.argos("muse"))
    if (!this.dog.path.length && this.dog.mode !== "sleep" && this.quiet(this.dog.saidUntil) && Math.random() < 1 / 2200) {
      this.dogDo("office")
      this.dogSay(this.argos("paper"))
    }
```

No other file changes. No new `Dog` field, no new sprite, no server route.

**Verify (must be GREEN):**

```
mise run office:check
```

This runs typecheck + the full suite, including `office/test/wide.test.ts`'s walk/furniture
tests — unaffected since no footprint changed — and the Task 1 test, now passing.

**Commit:**

```
git add office/kit/pets.ts office/rooms/wide.ts
git commit -m "feat: Argos fetches the newspaper — idle chance, existing office spot + balloon"
```

## Definition of done

- Both commits exist on `work/whimsy-argos-fetches-the-newspaper`.
- `mise run office:check` is green at HEAD.
- `git diff main --stat` touches only `office/test/pets.test.ts`, `office/kit/pets.ts`,
  `office/rooms/wide.ts`, plus this workline's own `spec.md`/`plan.md`.
