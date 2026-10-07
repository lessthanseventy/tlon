# Whimsy: Argos fetches the newspaper

Decisions locked by @andrew ("defaults are fine", thread #143):

1. **Data source: flavor text.** Argos "fetches" a canned line — no real digest, no new
   `GET /api/office` field, zero `server/` changes. Same tier as the other still-unbuilt
   whimsies (weather, day/night) — a pure `office/` PR.
2. **Trigger: idle chance, no day-gating.** Same shape as his existing low-probability per-tick
   behaviors (`stepDog`'s `0.0015`, `wide.ts`'s muse chime at `1/1800`) — it just happens
   sometimes. No "last fetched" date, no calendar-day concept (doesn't exist in `office/` yet).
3. **Render: existing primitives only.** He walks to the office spot (`60, 140`, the existing
   "your office" stand-in used by `dogDo(d, "office", …)` — there is no player avatar) and says
   the line in his existing speech balloon. No new sprite, no note icon, no click target.

**Scope: exactly this, one PR.** No new tile, no new art, no server route, no new `Dog` field.

## Where it lives

- `office/kit/pets.ts` — add one canned-line occasion, `paper`, to the `ARGOS` object
  (`pets.ts:22`), same shape as `muse`/`rally`/etc. (plain `string[]`, no `{name}` — this isn't
  addressed to anyone).
- `office/rooms/wide.ts` — one new idle check in `step()` (`wide.ts:192-217`), right beside the
  existing muse chime at `wide.ts:194`. It reuses `this.dogDo("office")` (already walks Argos to
  the office spot and sets a said-line via `dogDo`'s own `ctx.say`) and then overwrites that
  said-line with the `paper` line via `this.dogSay(...)`. No new walking/arrival logic — `dogDo`
  and `stepDog` are untouched.

Why overwrite rather than add a new `dogDo` variant: `dogDo`'s `what` union
(`"bed" | "walk" | "office" | "sit"`) is a destination, not an occasion — adding a fifth
destination that's identical to `"office"` except for which line it says would duplicate the
goal/path logic for no reason. Calling the line last wins; `dogSay` just assigns `d.said`/
`d.saidFrom`/`d.saidUntil`, so this is one extra line, not a new code path.

## The change

`office/kit/pets.ts`, inside `ARGOS` (after the `rally` entry, before the `fuss` key):

```ts
  rally: ["BALL. Ball ball ball. BALL.", "Left! Right! Left! I can't take it!"],
  paper: ["The morning news! I fetch it like a trophy from Troy!", "Dispatches! Sing, O Muse, of the evening edition!", "I bring news. I do not read it. Reading is for the gods."],
  fuss: {
```

`office/rooms/wide.ts`, inside `step()`, immediately after the existing muse-chime line
(`wide.ts:194`):

```ts
    if (this.dog.mode !== "sleep" && this.quiet(this.dog.saidUntil) && Math.random() < 1 / 1800) this.dogSay(this.argos("muse"))
    if (!this.dog.path.length && this.dog.mode !== "sleep" && this.quiet(this.dog.saidUntil) && Math.random() < 1 / 2200) {
      this.dogDo("office")
      this.dogSay(this.argos("paper"))
    }
```

`!this.dog.path.length` guards against retargeting him mid-walk (same guard `dogDo`'s callers
never need elsewhere because clicks are the only other caller, and a click already implies he's
free to redirect — this one is autonomous, so it must check).

## Test first

`office/test/pets.test.ts`, new test in the `"the pets talk"` describe block (follows the exact
shape of the existing `"someone idling near Nina…"` test just above it — step past the sleep
window with trivial rolls, then force the one roll that matters):

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

Needs `ARGOS` imported in the test file: add it to the existing `import { ... } from "../kit/pets"`
import if one exists, else add `import { ARGOS } from "../kit/pets"`.

This test fails today (`paper` doesn't exist on `ARGOS`, the trigger doesn't exist in `step()`) —
confirm red before writing the implementation, then green after.

## Definition of done

- The test above exists, was red, is green.
- `mise run office:check` is green (typecheck + full suite, including the untouched
  `wide.test.ts` walk/furniture tests — no footprint changed, so these shouldn't move).
- No `server/` file touched, no new `Dog` field, no new sprite.

## Verify

```
mise run office:check
```

Manual sanity (optional, no new drive-office step needed — this is a one-line variant of
behavior drive-office already exercises for Argos' other idle chimes): run `mise run office:run`
against the live server, wait, watch for Argos making an unprompted trip to the office corner
with a newspaper-flavored line in his balloon.
