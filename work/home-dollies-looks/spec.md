# Dollies step 6 — Looks: spec

Source: `docs/plans/2026-10-06-home-space-and-dollhouse-design.md` §5.1, §6, §8 step 6, §9.
Scope decided with Andrew on thread 134 (2026-10-07): ship the **mechanism** — look card, pixel
editor, importer, `looks.json` round trip, the WCAG check — with a **small seed catalogue**, not
the full 12-hair/6-tone/10-outfit/8-accessory breadth §5.1/§6 describe. The catalogue grows in
follow-up PRs; nothing here blocks that growth.

Check this step is held to (§8): *a round trip — import a PNG → `looks.json` → draw → the pixels
match the PNG's role-snapped version; WCAG on every skin tone against every tile floor.*

## 1 · What exists today, reused

- `office/kit/sprites.ts`: `Look` (`hair`, `hairRole`, `decor`, `fav`, `emote`, `slow`, `blink`),
  `lookOf(name)` (hash-derived, called once per actor in `sim.ts`), `figure()` (builds a 20-row —
  14 sitting — char-row sheet per view from `Look` + archetype `GEAR` overlay), `paints()` (maps
  each char to a `ROLE`). Skin is hardcoded to `ROLE.prose` via the `f` char — no per-look skin
  tone exists yet.
- `office/kit/palette.ts`: `ROLE` (the fixed set of theme colours), `contrast`/`luminance` (WCAG).
- `office/tui/main.ts`: the machine-palette poll pattern (`PALETTE` path from `TLON_PALETTE` or
  `~/.config/tlon/palette.json`, `followPalette()` — `realpathSync` + `statSync().mtimeMs`,
  re-read only when that signature changes, no `fs.watch`). `looks.json` follows this pattern
  exactly, polled on the same tick.
- `tasks/office.toml`: every office command is a mise task (`office:run`, `office:test`, …); no
  installed binary. `import-sprite` becomes `office:import-sprite` here, per repo law.

## 2 · Data model

### 2.1 `Look` grows two fields, both optional (an untouched look is unchanged)

```ts
// office/kit/sprites.ts
export type Look = {
  hair: Hair; hairRole: Role; decor: number; fav: Fav; emote: string; slow: boolean; blink: number
  skinRole?: Role                                    // catalogue skin tone; absent → ROLE.prose (today's skin)
  outfit?: Outfit; accessory?: Accessory              // catalogue picks; absent → none (today's look)
  custom?: Partial<Record<"front" | "side" | "back", string[]>>  // editor/importer sheet; present → skip part generation for that view
}
```

`figure()` checks `look.custom?.[view]` first: if set, those rows (already 12 wide) are the base
instead of `TOP`/`FACE`/`TORSO`/`LEGS`; sitting slice (`rows.slice(0, 14)`) and right-face mirror
still apply, and archetype `GEAR` + badge/tie still overlay on top — **a custom look still shows
whose desk it is** (plan §5.1: "the look says who; the hard hat says what they are").

`paints()` changes one line: `f: look.skinRole ? ROLE[look.skinRole] : ROLE.prose`.

### 2.2 Skin tones — reuse, no new art

§5.1/§6 ask for "6 roles, so WCAG and themes hold." The six existing archetype-flavoured roles
already satisfy that count and are already themed: `builder`, `surveyor`, `reviewer`, `assistant`,
`planner`, `body`. No new `ROLE` entries, no new hex. `SKIN_ROLES: Role[]` is this literal list in
`sprites.ts`.

### 2.3 Outfits and accessories — seed catalogue, as overlays

Same shape as archetype `GEAR` (`Record<number, string>` per view), so they compose with the
existing `overlay()` helper — applied *before* archetype gear, so gear still wins on conflicting
rows:

```ts
export type Outfit = "hoodie" | "labcoat"
export const OUTFIT: Record<Outfit, Gear> = {
  hoodie: { front: { 10: ".oooooooooo.", 11: ".oo........o" }, back: { 10: ".oooooooooo." },
            side: { 10: "..oooooooo.." } },
  labcoat: { front: { 9: ".wwwwwwwwww.", 10: "ww........ww", 11: "ww........ww" },
             back: { 9: ".wwwwwwwwww." }, side: { 9: "wwwwwwwwwwww" } },
}
export type Accessory = "glasses" | "headphones"
export const ACCESSORY: Record<Accessory, Gear> = {
  glasses: { front: { 6: "..kk..kk...." }, side: { 6: ".kk........." } },
  headphones: { front: { 5: ".k........k." }, back: { 5: ".k........k." }, side: { 5: "k..........." } },
}
```

(Char `o` → `ROLE.body` hoodie orange is already mapped in `paints()`; `w` → `ROLE.prose`. The
exact rows above are placeholders for *this spec* — the implementing task draws them against the
real figure grid and checks by eye in `office:run`, same as every sprite in this file today.)

`figure()` applies, in order: base rows (custom or generated) → outfit overlay → accessory
overlay → archetype gear → badge/tie. Each overlay is skippable (`look.outfit`/`look.accessory`
undefined → no-op, exactly how `GEAR[archetype ?? ""]` already no-ops for an unknown archetype).

### 2.4 `looks.json`

```jsonc
// ~/.config/tlon/looks.json — TLON_LOOKS to point elsewhere; re-read within a second of a change
{
  "yu": { "hair": "bun", "hairRole": "meta", "skinRole": "builder", "outfit": "labcoat", "accessory": "glasses" },
  "andrew": { "custom": { "front": ["............", … 21 more rows …], "side": […], "back": […] } }
}
```

A **parts** entry (any of `hair`/`hairRole`/`skinRole`/`outfit`/`accessory`/`decor`/`fav`/`emote`/
`slow`/`blink`) overrides only those fields on top of `lookOf(name)`'s hash defaults — the look
card writes this shape. A **custom** entry (`custom`, from the editor or the importer) replaces
the generated views wholesale for whichever views it has, still using the fields above for
anything `custom` leaves out (e.g. `hairRole` still tints balloons/UI elsewhere if anything reads
it directly — `figure()` itself no longer reads hair fields for a view `custom` covers).

New file `office/kit/looks.ts`:

```ts
import type { Look } from "./sprites"
export type LookOverride = Partial<Look>
let overrides: Record<string, LookOverride> = {}
/** take the machine's looks.json if it changed; same poll shape as useRoles/followPalette */
export function useLookOverrides(o: Record<string, LookOverride>) { overrides = o }
export function overrideFor(name: string): LookOverride | undefined { return overrides[name] }
```

`sim.ts`'s one call site, `lookOf(r.agent)` → `{ ...lookOf(r.agent), ...overrideFor(r.agent) }`.
`main.ts` gains a `LOOKS` path constant and a `followLooks()` mirroring `followPalette()` exactly
(same `realpathSync`/`mtimeMs` signature cache, same silent-catch-on-missing-file), called on the
same tick `followPalette()` is.

## 3 · The look card

`l` on a person (room click or the finder) opens `{ kind: "look", name }` — same shape as the
existing `{ kind: "pet", who }` card (`main.ts:31`, rendered at `main.ts:846`). Shows the four
views (front/back/left/right, `figure()` already renders all four from `face`) at 2x, and five
cycled rows — hair, hair colour, skin tone, outfit, accessory — left/right arrows step each
through its catalogue (`HAIRS`, `HAIR_ROLES`, `SKIN_ROLES`, `keys(OUTFIT)` + "none", `keys
(ACCESSORY)` + "none"), up/down move the selected row, live-previewed on the card's own figure
(no draw to the room until saved). `⏎` writes the parts object to `looks.json` under that agent's
name (read-merge-write: only this entry changes); `e` jumps into the editor (§4) on the currently
selected view; `esc` discards and closes. This is the only door that *picks from* the catalogue;
§4 and §5 are the two doors that *replace* a view outright.

## 4 · The editor

Reachable as `e` from the look card, on the view currently showing. A 12×22 grid (figure width ×
full standing height), arrows move a cursor cell, a letter key paints the role it names in
`paints()`'s legend (shown as a one-line key at the top of the pane — `h`air `f`ace `k`ink
`s`hirt `p`ink `b`oots `y`body `o`hoodie `w`labcoat, i.e. every char `paints()` maps, so a drawn
sprite re-themes exactly like a generated one), `.` clears a cell, `m` toggles mirroring (paint
the left half, right half follows) default **on**. Four tabs (`1`-`4`, front/back/left/right)
share one 12×22 buffer per view; switching tabs keeps each view's buffer. `⏎` saves all four
views into that agent's `looks.json` entry as `custom`; `esc` discards.

## 5 · The importer

`mise run office:import-sprite -- <path.png> [agent-name]` (new `office/cli.ts`, a bun
entrypoint; the mise task in `tasks/office.toml` just runs it with `bun office/cli.ts "$@"`):

1. Decode the PNG to RGBA. **New dependency**: `pngjs` (pure JS, no native build, MIT) — this
   repo's encoder (`tui/png.ts`) is hand-rolled because it only ever writes one filter-free IDAT;
   decoding arbitrary PNGs (Aseprite's own filters, palettes, bit depths) is not a one-screen
   function, so it is not hand-rolled here. Added to `office/package.json` `dependencies`, but
   **imported only from `office/cli.ts`** — the compiled TUI ships one runtime dep (`office/AGENTS.md`),
   so nothing under `tui/` or `kit/` may import `pngjs`. `kit/snap.ts` (below) takes plain RGBA,
   never a PNG buffer, so it needs no PNG library and stays reachable from `tui/main.ts` clean.
2. Refuse (print the actual size, exit 1) anything that isn't exactly 12×22 **or** a 48×22 sheet
   (4 views side by side, the plan's "whole-sheet" form) — no scaling, per §5.1.
3. Snap every pixel to the nearest `ROLE` by Lab distance (convert each `ROLE` hex and each pixel
   to Lab once; nearest by Euclidean distance in Lab space), reverse-mapped through `paints()`'s
   char legend so the output uses the *same* chars the editor and `figure()` use; a transparent
   pixel (alpha `< 128`) → `.`.
4. Print the char rows (so the result is inspectable in the terminal before it's trusted) and
   write them into `looks.json` as that agent's `custom` (single view for a 12×22 input — front,
   unless `--view=` is given; all four for a 48×22 sheet).

```ts
// office/kit/snap.ts — shared by the importer and (later) any other pixel-in, role-out path
export function labOf(hex: string): [number, number, number] { /* sRGB → linear → XYZ → Lab */ }
export function nearestRole(lab: [number, number, number], roles: Record<string, [number, number, number]>): string
```

## 6 · Checks (§8's gate for this step)

- **Round trip** (`office/test/looks.test.ts`): a small synthetic PNG (built in-test from raw
  RGBA, no fixture file) with pixels at exact `ROLE` hex values at known coordinates → import →
  the `custom` char rows in the returned `looks.json` entry are exactly the role-snapped char at
  each coordinate (property: `snap(decode(png)) === expected`, not a pixel-fuzz comparison, since
  the input pixels are chosen to already be exact role hexes).
- **WCAG** (extends `office/test/wcag.test.ts`): for every `SKIN_ROLES` entry, `contrast(ROLE[s],
  bg) >= MIN_CONTRAST` against every background colour a figure can stand in front of *today*
  (the wide room's floor/wall fills — tiles per §2 don't exist yet, so "every tile floor" is read
  as "every floor colour the current rooms paint," re-run again once step 1 lands actual tiles).
- Existing `office/test/wide.test.ts`, `pets.test.ts`, `tui.test.ts` stay green unchanged — no
  field is required, so an agent with no `looks.json` entry renders exactly as it does today
  (plan §9: "nothing here, from moving a wall to making Nina sassy, ever needs a restart" — same
  bar applies to "nobody changes overnight," §5.1).

## 7 · Out of scope for this PR (tracked, not forgotten)

- The full 12-hair/10-outfit/8-accessory catalogue (§5.1/§6) — seed is 5 hairs (existing),
  2 outfits, 2 accessories; grows in follow-up PRs, each just adding entries to `OUTFIT`/
  `ACCESSORY`/`HAIRS`, no shape change.
- `preset`/fork semantics for `looks.json` (§6's "preset plus overrides" rule) — this step's file
  is flat overrides only; the preset layer is shared machinery across `home.json`/`pets.json` too
  and belongs with whichever of those lands it first.
- Drag-drop import — the plan calls it "a later idea."
- Re-running the WCAG check against real tile floors once §2 (the floor) ships.
