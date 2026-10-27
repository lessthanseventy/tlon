APPROVE. Right then: small, matches the ask.

- `office/tui/main.ts` `chatter()`: with `dials.banter` off, pets, corkboard and banter are no longer fetched. `talk` was already gated through `onTogether`. The trailing `if (banter)` around `converse` is now redundant but harmless. Each gate sits at the fetch it names, and the comment states the why (the server spends model tokens lazily).
- `office/test/banter-off-quiet.test.ts`: drives the real TUI against a stub server. It waits for `/office/suggestions/` (so `chatter()` ran to the end), then asserts no banter/pets/corkboard/talk request. I ran it: 1 pass, 0 fail, 1.8s. I did not run the red-before half of the PR's claim.
- `/office/toys` is still fetched with banter off whenever weirdness isn't `curated`. If the server writes toys with tokens too, that is a separate gap, not a blocker (follow-up below).

Not run: the full `mise run check`. It runs at verify.