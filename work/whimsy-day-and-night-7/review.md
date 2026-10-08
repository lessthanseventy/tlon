APPROVE — whimsy-day-and-night-7 @ 75d4cbe

Previous blocker (desk lamps registering inside sc.item, after nightfall) is fixed: the push is hoisted out of the item in furniture.ts, and a new wide test asserts 3 lamps (lounge + manager + lead) are registered when nightfall runs at 03:00. I read the diff: darkness/lampsLit/dark in kit/daylight.ts match the windows' sky hours; the dim is applied after items and below the windows band; pets turn in only when idle; one `dark` predicate; goldens re-hashed. Server verify (mise run check) passed on the rebased branch (per recorded evidence).

Not verified by me: I did not re-run the suite or look at the live render.

Process note: intent/spec/plan are not committed on the branch, so the merge proof shows them missing — operator's call at the gate.