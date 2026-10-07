# Music corner: stereo marquee + tempo-synced pet dance

Ticket #24, §7 whimsy (`docs/plans/2026-10-06-home-space-and-dollhouse-design.md` §7):
whatever `playerctl` reports as playing scrolls on a stereo; the pets dance to anything over
120 bpm, if the player reports a bpm. Works in today's room — needs no new tiles.

**Scope: exactly this, one PR.** No new furniture tile, no new pixel art, no server route.

## Where it lives

The stereo is a label drawn against the existing wide room (`office/rooms/wide.ts`), the same
way the TV (`kit/tv.ts`, wired at `wide.ts:253`) sits against existing furniture rather than
needing a tile of its own. Exact placement (which wall segment or piece of furniture it reads
against) is the implementer's call within the current room layout — not a design decision this
spec needs to pin down, since nothing else depends on where the label sits.

## playerctl: polling and fallback

- Polled directly from the TUI process (`office/tui/main.ts`), via `Bun.spawnSync`, the same
  pattern already used for `tmux` calls there (e.g. `main.ts:409`) — not routed through
  `Server.Office` or an operator-API route. This is local desktop media state, not office/crew
  state, so a server round-trip would be a detour for data the server has no use for.
- Poll interval: ~2s.
- Command: `playerctl metadata --format '{{ title }} - {{ artist }}|{{ mpris:length }}|{{ xesam:title }}'` —
  exact format string is a build-time detail; what matters is the contract below.
- **No player running** (`playerctl` exits non-zero, or errors "No players found"): stereo shows
  its idle state — no marquee text. Pets stay in their normal idle/walk/sit behavior; dance never
  triggers.
- **Player running, title available, no bpm field**: marquee scrolls the title/artist text as
  normal. `playerctl` has no standard bpm metadata field — this case is the common one, not an
  edge case — so dance only triggers when a bpm *is* present and the inference below says to.
- **bpm inference**: `playerctl` doesn't expose bpm directly for most players. Treat this as the
  ticket does — "if the player reports a bpm" — and only wire the dance trigger off a metadata
  field if/when one is actually present (e.g. some players surface `xesam:useCount` or custom
  fields; none reliably carries tempo). If no such field is available at build time, the dance
  trigger is simply dead code behind the same `> 120` check — correct per spec, inert until a
  player supplies the data. This is not a blocker: the marquee ships regardless.

## The marquee

Whatever text `playerctl` reports (title + artist, or just title if artist is blank) scrolls
across the stereo's label area, same text-scroll idiom the room already uses elsewhere (ticker/
marquee text, not a new widget kind). Updates once per poll (~2s), not continuously re-rendered
mid-scroll from stale data.

## "Dance" for Nina and Argos

No new sprite art. Both pets already carry a `mode` state machine (`Cat.mode` in
`kit/sim.ts:30`, `Dog.mode` in `rooms/wide.ts:247`) that `draw.ts` reads to pick a frame set
(`draw.ts:158-166` for the cat: walk/sit/sleep/play frames, animated by ticking an index into
`CAT.walk` etc.). Dance follows the same shape:

- A pet dances by cycling its **existing** walk/sit frames with a tempo-synced bob (vertical
  offset, like the bob already applied to a working coworker's sprite in `draw.ts:139`) and a
  left/right flip, instead of drawing a new frame set.
- Trigger: bpm present and `> 120` → dance; otherwise the pet's normal idle/walk/sit logic runs
  unchanged.
- Timing: the bob/flip cadence derives from the reported bpm (faster bpm → faster bob), not a
  fixed rate — this is the "tempo-synced" part. With no bpm (the common case per above), there is
  nothing to sync to, so dance cannot trigger at all; this isn't a missing fallback, it's the
  direct consequence of the trigger condition.
- Only applies while a pet is on the floor of the room the stereo is in and not already in a
  conflicting mode (asleep, fussed, mid-zoomies) — same precedence the existing mode machine
  already enforces for its other states.

## Exit / verification

This is a TUI whimsy feature with no natural automated assertion for "does it look right" — the
check is manual, via the `drive-office` skill once built:

1. With a player running and playing (`playerctl` reachable), confirm the stereo's marquee scrolls
   the current title/artist and updates within one poll interval of a track change.
2. Stop the player (or run with none active): confirm the marquee goes idle and pets are
   unaffected — no stale text, no dance stuck on.
3. If a bpm field is wired and reports >120: confirm Nina and/or Argos switch to the bob+flip
   dance using their existing frames (no new art), and drop out of it when the track ends or bpm
   drops.

No `office:check` assertion is expected to cover the playerctl integration itself (it shells out
to a host binary); the room's existing WCAG/walk tests should stay green since no footprint or
furniture changes. `mise run office:check` gates the rest as usual.
