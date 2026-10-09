# Lobby north wall: the poster of the day

lonnrot's original suggestion (a corkboard) is lost, and the back wall of the wide room already
has a calendar, whiteboard, notes board, suggestion box, windows, TV, stereo and clock. So this adds
the one thing it lacks: **a framed poster** between the stereo and the clock (`WideRoom.poster`,
`office/rooms/wide.ts`) whose line is chosen by the local date from a short fixed list
(`POSTERS` in new `office/kit/poster.ts`, `posterOf(now): string`): the same all day, a different one
tomorrow, no server data and no flag. Hovering it shows the line (`tip`); the frame is drawn with
the palette roles only, and the wall stays as it was at widths too narrow to hold it.

## Test it starts from (`office/test/poster.test.ts`)

```ts
test("the poster's line is fixed for a day and changes the next", () => {
  expect(posterOf(new Date(2026, 9, 10, 8))).toBe(posterOf(new Date(2026, 9, 10, 22)))
  expect(posterOf(new Date(2026, 9, 10))).not.toBe(posterOf(new Date(2026, 9, 11)))
})
test("the wide room hangs a poster whose tip is today's line", () => {
  const hit = new WideRoom(560).render(view, focus, measure, now).hits.find((h) => h.act.kind === "poster")!
  expect(hit.tip).toContain(posterOf(now))
})
```
Then a render-differs test (poster present vs. width too small) as in `mailbox.test.ts`.
