Whimsy: sleep (#35).

The bedroom routine ("in bed by 23:00") now shows on the bedroom tile. Stamped, your figure lies on the bed (a long shape from the pillow down); still unstamped past its due time, a short curled cat with ears is already there. The two silhouettes differ, so it reads without colour. No bed routine, or not yet due, leaves the bedroom as it was.

The scene is derived from the life status's `today` list (`bedScene`, matched on a routine titled with "bed") and never stored; the server has no tile on a routine, so the title is the link. Office only; no server change.

Closes #35.

Checked: RED first (`bedScene` not exported; the bed tests found the bedroom unchanged). GREEN: life.test.ts and homeart.test.ts pass (48 pass, 0 fail) and `tsc --noEmit` is clean.
