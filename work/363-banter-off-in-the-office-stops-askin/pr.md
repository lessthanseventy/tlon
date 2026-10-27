Banter off in the office stops asking the server (closes #363).

With the dial's banter off, `chatter()` still GET /office/pets, /corkboard and /banter every tick; the server writes those lines lazily with model tokens, and the office dropped them. Now `chatter()` skips pets, corkboard and banter when `dials.banter` is false (talk was already gated). The per-terminal dial stays office-side; no server knob.

Checked: `office/test/banter-off-quiet.test.ts` drives the real TUI against a stub server with the dial off and asserts no banter/pets/corkboard/talk request (red before, green after).
