VERDICT: approve

Scope: garden tile kind (22fb740) plus its art (96e283f): office/kit/home.ts, office/kit/homeart.ts, and the home and homeart tests. I read the diff only. I did not run the gate myself; the server recorded `mise run check` green on 96e283f.

The earlier open item is closed. The first review noted the fence and garden drawing were missing. 96e283f adds the `garden` sprite: a fence row, then bed rows with plants and dirt. It also adds the `garden` palette. The sprite is 12x12, matching the other kinds, and it uses only roles that already exist (structure, live, borderInactive, attention).

Checks:
- `garden` is last in CATALOGUE, so build-mode `place` cycles street→garden→living. The wrap is tested.
- A garden next to a living tile saves and loads back unchanged. Connectivity is still pure grid adjacency.
- The rotation test loops over CATALOGUE, so it now covers garden.
- The no-art fallback test used `garden` as its art-less example, which would now be false. It uses a stand-in kind `shed` instead, and the test still checks the same thing.

Not verified: how the sprite looks on screen. QA is nolan's step via submit_qa, which I have not seen pass. This approval does not claim visual QA.