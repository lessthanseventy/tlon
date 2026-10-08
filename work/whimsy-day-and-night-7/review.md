APPROVE — whimsy day and night (§7), branch work/whimsy-day-and-night-7 at 2a983b5.

Verified by reading the diff (office/ only) and the recorded gate (`mise run check` passed on this branch; I did not re-run it).

- daylight.ts: `darkness` is a pure function of the clock on the windows' own hours. `lampsLit` and `dark` derive from it, so there is one night predicate.
- Lamps register at real positions only (lounge lamp, manager and lead desk lamps). The desk-lamp push is hoisted out of `sc.item`, so lamps exist before `nightfall` runs. A test asserts 3 lamps at 03:00 (fixes my earlier finding).
- The dim starts at BAND, below the windows, so the sky is not double-darkened. Night luminance is bounded: the test requires it above 0.4× day and below 0.85× day.
- The boss wears pyjamas when dark. The pets bed down at `dark` once idle, with no dice (`tick % 20`, only when not on an errand or fussing).
- Tests are deterministic: goldens use a fixed render date and a pinned `hour()`. The cat and dog antics tests pin the hour to 16. A WCAG contrast test covers full dark.
- office/AGENTS.md is updated in the same change.

Non-blocking nit: `season()` uses `darkness(h) > 0.5` for its night check, while the lamp uses `dark`. That is a second threshold.