# office: ticket board counts open tickets per node, with an orphans group

Closes #684. The TICKETS column said "3" because it counted top-level rows, and group rows showed
done/total over direct epic children only.

- Server: `Room.board/1` counts open (not-done) tickets recursively under every node (epic, initiative), plus `loose_open` and `open_total`. Tickets filed straight under an initiative and started loose tickets are counted. The office payload carries `open` on group rows and `ticket_open` per workspace.
- Office: group rows, the column title and the sticky show the server's numbers (`Toy 11 open`), never a client-side length; loose tickets sit under a synthetic "orphans · N open" group at the bottom.

Checked: `room_test` (seeded initiative → epic → tickets plus a direct-under-initiative and a started-loose ticket), `office_test` (payload), `office/test/board.test.ts`; `mise run check` passed on 9ee2df3. Not yet verified: the live-db screenshot (kids 585 → Toy 588; engine 587), because the running service predates this server change — it needs `server:restart` first.
