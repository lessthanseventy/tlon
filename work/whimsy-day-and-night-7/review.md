VERDICT: request_changes

Reviewed 7fa5196 (fixes to 79ea6dd) against §7 and my earlier review. Read the diff; probed one render; did not run the full gate.

Fixed and fine
- Pyjamas (boss figure: no tie, planner colours, `dark` = clock-out), one `dark` predicate, `season()` on `darkness`, bedtime without Math.random, 0.4x lower bound on night luminance, 3am WCAG pass.

Must fix
1. Only ONE lamp ever lights; the desk lamps never do. `execDesk` pushes to `sc.lamps` inside an `sc.item(...)` callback (office/kit/furniture.ts, `sc.lamps.push([d.x + d.w - 5, d.y + 15])`), and item callbacks run in `Scene.finish()`. But `WideRoom.render` calls `this.nightfall(sc, now)` BEFORE `return sc.finish()` (rooms/wide.ts:312-313), so `nightfall` reads `sc.lamps` when it holds only the lounge lamp (pushed outside an item, in lounge.ts). Probe: render at 03:00 with a manager+lead office (wcag.test's `office()`): `sc.lamps.length` is 1 before `finish()`, 3 after. So "lamps come on one by one" is a single lamp, and the commit/AGENTS.md claim that the manager/lead desk lamps light is false. The new lamp test only checks the lounge patch, so it passes.
   Fix: register the desk lamp outside the item callback (as lounge.ts does), or run the lamp glow after items are drawn. Add a test: night render with manager and lead seated has sc.lamps.length >= 3 and a desk-lamp patch is brighter, relative to day, than distant floor.

Should fix
2. Same ordering: the dim (`glow` of ROLE.ground from BAND down) is painted before furniture and people, so items/figures are drawn at full day brightness over a dimmed base. The 3am WCAG pass is green, but the floor won't read as dark around furniture. If intended, say so in `nightfall`'s doc; otherwise apply the dim after items (fixes 1 and 2 together).

Nit
- The lamp-pool test patch (L0+10..+18, y 62..70) only partly overlaps the glow (y 54..63); a patch on the shade (L0+14,58) would make it a tighter assertion.
