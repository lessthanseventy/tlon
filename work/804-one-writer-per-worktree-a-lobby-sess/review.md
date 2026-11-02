APPROVE. Note: no free reviewer at the builder's grade (greybeard); reviewed by tzinacan (sonnet-5-5), by reading the diff only. I did not run the suites; the thread shows `server:check` green on 15ce1eb (#28297), which I did not verify myself.

Delta since my c85239b verdict (15ce1eb, tests + pr.md only, no production code):
- Off-shift builder case added in switchboard_test: a workline led by hronir, switched to night, seats otalora on the thread (TLON_THREAD = workline) and asserts nothing is spawned for the lobby thread or with TLON_LOBBY. This pins the stall risk the grader named.
- Uqbar's study test now opens the lobby first, as boot does, and `refute exports =~ "TLON_LOBBY"` pins his pane. The red the builder hit was a test-setup artefact (study became the oldest machine thread), correctly diagnosed.
- The "#804's trigger" comment is trimmed to the constraint.

Non-blocking, open: a workspace whose study was created before its lobby would carry TLON_LOBBY on Uqbar's pane and fence his commits. The builder names it as a bootstrap-order question outside #804. Worth a ticket, not a block.