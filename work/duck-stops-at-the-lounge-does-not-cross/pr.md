Office toy: the duck crosses the whole hall, not just the lounge's edge.

The duck's crossing stopped at `leftX + 80`, the lounge's left side, so it turned back before reaching the hallway the toy-step-5 spec has it cross. The hall runs from the room's left wall to the door, so the crossing now ends at x=12 (the hall's left end) before the look round and the walk back out.

Closes #349.

Checked:
- `office/test/events.test.ts` "the duck crosses the whole hall": red first (lowest x was 142, stuck at the lounge's edge), then green after the change (lowest x is 12).
- `bun test` in `office/`: 559 pass, 0 fail.
- `bunx tsc --noEmit` in `office/`: clean.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
