# Review: uqbar-step-4-marginalia-plan-margin-kind @ dd5ba82

**Verdict: request_changes** — the fix is right, its cost is not.

Since 44461f9 one commit, dd5ba82: `inkInto`'s `behind` judges a label's box by its worst pixel instead of the box average. Correct for nolan's finding (a strip at the box edge hid in the average), and the red-first test in `office/test/paint.test.ts` pins it.

## Blocking: the worst-pixel scan is 10–40× the painter's old cost, on the animation loop

`behind` now builds a `#rrggbb` string and calls `contrast()` (two `rgb()` parses, six `**2.4`, a sort) for every pixel under every label. Measured on a wide-room frame (`office()` fixture, 35 labels, kitty), `inkInto` alone:

| scale | before (44461f9) | after (dd5ba82) | png encode of the same frame |
|---|---|---|---|
| k=3, 1680×600 | ~2 ms | 55–85 ms | 20–45 ms |
| k=5, 2800×1000 | ~3 ms | 15–40 ms | 15–70 ms |

`kittyImage` runs on every fresh frame, and `main.ts:1981` steps the room every 100 ms and draws when it moved, so while anyone walks the frame budget at k=3 is now ~100 ms of painter + encode: visible stutter, and keys queue behind it. The WCAG sweeps (hundreds of viewports × `inkInto`) pay it too.

The fix keeps the worst-pixel rule and drops the per-pixel strings and pows: a 256-entry sRGB→linear table, luminance from the bytes, the ratio compared numerically, and the hex string built once for the winner. Same answer on a 300k-pixel scan (`#8c7b6a`, 1.03), 723 ms → 15 ms.

```diff
--- a/office/kit/palette.ts
+++ b/office/kit/palette.ts
@@
-/** WCAG relative luminance of an #rrggbb colour */
-export function luminance(c: string): number {
-  const [r, g, b] = rgb(c).map((v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4 })
-  return 0.2126 * r! + 0.7152 * g! + 0.0722 * b!
-}
+/** sRGB channel byte → linear, tabled once: the per-pixel half of `luminance`, for scans over raw bitmaps */
+export const LINEAR = Float64Array.from({ length: 256 }, (_, v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4 })
+/** WCAG relative luminance of an #rrggbb colour */
+export function luminance(c: string): number {
+  const [r, g, b] = rgb(c)
+  return 0.2126 * LINEAR[r!]! + 0.7152 * LINEAR[g!]! + 0.0722 * LINEAR[b!]!
+}
--- a/office/tui/paint.ts
+++ b/office/tui/paint.ts
@@
-import { contrast, rgb, ROLE } from "../kit/palette"
+import { contrast, LINEAR, luminance, rgb, ROLE } from "../kit/palette"
@@
   const behind = (x: number, y: number, bw: number, bh: number, c: string) => {
-    let worst: string | null = null, low = Infinity
+    const L = luminance(c)
+    let worst = -1, low = Infinity
     for (let j = Math.max(0, Math.round(y)); j < Math.min(h, Math.round(y + bh)); j++)
       for (let i = Math.max(0, Math.round(x)); i < Math.min(w, Math.round(x + bw)); i++) {
-        const o = (j * w + i) * 4, px = "#" + [big[o]!, big[o + 1]!, big[o + 2]!].map((v) => v.toString(16).padStart(2, "0")).join(""), r = contrast(c, px)
-        if (r < low) { low = r; worst = px }
+        const o = (j * w + i) * 4, l = 0.2126 * LINEAR[big[o]!]! + 0.7152 * LINEAR[big[o + 1]!]! + 0.0722 * LINEAR[big[o + 2]!]!
+        const r = l > L ? (l + 0.05) / (L + 0.05) : (L + 0.05) / (l + 0.05)
+        if (r < low) { low = r; worst = o }
       }
-    return worst ?? ROLE.ground
+    return worst < 0 ? ROLE.ground : "#" + [big[worst]!, big[worst + 1]!, big[worst + 2]!].map((v) => v.toString(16).padStart(2, "0")).join("")
   }
```

Check: `office:check` green (paint, wcag sweeps), and `inkInto` on the wide-room frame back near single-digit ms (a one-off timing like the table above is enough; it need not land as a test).

## Not re-verified
nolan's PNG samples on the new tip (emma flagged the same). The patch does not change which pixel wins, so the backing decision is identical to dd5ba82's.
