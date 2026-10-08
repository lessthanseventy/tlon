VERDICT: APPROVE

Scope: the diff on work/home-tile-renderer-draw-home-tiles-in-th (office/kit/homeart.ts, office/tui/main.ts, office/test/homeart.test.ts, office/AGENTS.md), read against spec.md. I did not re-run the gates: the server's recorded `mise run check` on this branch is exit 0, and the builder reports `office:check` at 232 pass / 0 fail with the golden unchanged. I did not drive the TUI.

## Spec compliance
- The hook is as specced. `TILE_ART` maps kind to painter, and `paintTile` falls back to `plainTile` for an unregistered kind. The test registers and removes a `garden` stub, so #176/#185/#172/#40 can plug in by adding a key (plus a `CATALOGUE` entry in `kit/home.ts`).
- `rotated()` is correct. The clockwise 90/180/270 outputs are tested against the expected strings.
- All 5 kinds have 12x12 sprites. The tests check that kinds differ from each other and that rot 90 differs from rot 0.
- `renderHome` iterates `gridWindow` and centres the grid. The cursor is drawn as brackets, alarm-coloured when refused. A carried tile is shown dimmed at the cursor. Colours come from `ROLE` only.
- `main.ts` swaps the room image for the home frame while building. Leaving build mode sets `roomChanged` and `imageDirty` via `homeShown`, so the room comes back on any exit path.

## Deviations from spec.md (none block)
1. `plainTile` has no kind initial, only a bordered floor square. The spec said "+ kind initial in font.ts". A new kind with no art is unlabelled until it registers.
2. `hits: []`, so cells are not clickable to move the cursor. The spec listed `Hit`s per cell. Keyboard build still works. Clicking is a follow-up if wanted.
3. The spec's open question (swap the image versus a preview pane) was resolved as swap, and the operator said "your call". It is recorded in learning #622.

## Notes (non-blocking)
- While building, `imageDirty = true` is set on every `draw()`, so the kitty image is re-sent on every redraw. This is correct but wasteful. If it flickers or lags over ssh, gate it on a build-state change.
- `build!` inside `draw()` is guarded by `building`, so it is safe.

## Unverified
- The TUI has not been driven live, because the build_mode flag is off on the live service. The builder checked renderHome via a PNG render. A scratch server with the flag on would confirm the wiring, but I do not consider it blocking.