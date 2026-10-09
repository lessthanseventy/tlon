Bug report: closing a plain thread that holds unmerged commits strands the work.

A plain thread (one with no workline `stage`) works in its own git checkout. Closing it, by any door,
ends its sessions and leaves the checkout with commits nobody will ever merge. Closing should refuse
to do that: a plain thread whose checkout holds unmerged work must be tracked as a workline
instead, left open, and the closer told why.

Fix it, test-first, and commit. What has to hold:

- `Server.Channel.close_thread/1` on a plain thread whose checkout has unmerged commits does not
  close it: it promotes it with `Server.Workline.promote/1` (stage `build`, state still `open`, its
  checkout kept) and returns `{:tracked, thread}` with the promoted thread. It also posts on the
  thread, as author `"tlon"`, a message that says why and contains the word `unmerged` (and
  @mentions the thread's lead when it has one). A plain thread with no commits still returns
  `{:ok, closed}` as before; a thread that already has a stage is closed as before.
- The `close_thread` MCP tool answers a tracked thread with the JSON object
  `{"stays_open": true, "tracked": <the workline's slug>, "why": <a sentence>}` and no error;
  the `finish` tool does the same. `POST /api/threads/:id/close` returns the tracked thread's row.
- The manager's (staffing lead's) persona prompt in `Server.Profiles` must carry, in its
  ticket-intake guidance, the sentence fragment `changes code gets a workline`: a ticket that
  changes code gets a workline (stage build or later), never a plain thread, because a plain
  thread's branch is stranded when it closes.


The project is the Elixir/Phoenix app under `server/` (`cd server && mix test <file>` runs a test file).
