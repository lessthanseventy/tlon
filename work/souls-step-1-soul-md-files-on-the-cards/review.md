APPROVE — souls step 1 (kit/souls.ts + card rows + TLON_SOULS poll).

Verified: read the full diff (main...HEAD, 5 files); `bun test test/souls.test.ts` → 10 pass / 0 fail; gate `mise run check` exit 0 per the thread's recorded check.

What's right: scope matches the ask (parse, table, poll, read-only card rows); poll shape mirrors looks.json; a missing dir is `{}` with signature ""; an unreadable file drops one soul, not the TUI; `###` headings don't match; the `||` chain in the 1s tick defers followSouls by at most a tick, same as the existing pets/looks pattern. AGENTS.md updated in the same change.

One real defect, non-blocking (filed as follow-up): `parseSoul` keys `body`/`sections` by heading text on plain `{}` objects, so a heading named after an Object.prototype member throws — reproduced: `parseSoul("## constructor\nx\n")` and `## __proto__` → `TypeError: body[head].push is not a function`. `loadSouls` swallows it, so the whole soul silently vanishes, contradicting the "forgiving" contract. Unlikely input, one-line fix (`Object.create(null)` / Map).

Minor, unfiled: CRLF files leave a trailing `\r` on body lines; card rows render lines unwrapped/unsanitised — fine for a file the operator owns.