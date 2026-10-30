# send_back `unqueue`: pull a queued landing with the move

Closes #569.

A workline whose landing is queued could not be sent back: `send_back` refused ("its landing is
queued or running; let it finish"), and cancelling the Oban job by hand was not enough, because
`KeepUp` → `requeue_stranded/0` puts a review thread with a standing approval back in the queue on
its next tick. The cancel and the move had to happen in one transaction (hronir #11839; seen on
#329 and #415).

- `Server.Workline.send_back/5` takes `unqueue: true`: landing jobs still waiting
  (`available`/`scheduled`/`retryable`) are cancelled inside `move_back`'s locked transaction, so
  the thread leaves `review` in the same commit the jobs leave the queue and `requeue_stranded`
  finds nothing. A landing already `executing`, and a verify in any state, refuse as before.
  Without the option nothing changes.
- `Server.Jobs.cancel/1` is the queue door's cancel: `Oban.cancel_job/1` when Oban is up on the
  node, an honest `{:error, :no_oban}` otherwise, never a raise.
- Three surfaces, one function: the `send_back` MCP tool's `unqueue` field, the operator API's
  `POST /api/threads/:id/send_back` body `unqueue`, and `tlon-cli send-back <id> <stage> --unqueue <why>`.
- `needs.ex` / `needs_test.exs` untouched (PR #675 is changing them).

The one window left: a landing that starts executing between the in-flight select and the cancel.
`Server.Jobs.Land.perform/1` takes the same `FOR UPDATE` row lock, so it waits on the send-back,
then finds the thread moved and does nothing.

## How it was checked

- `workline_send_back_test.exs`: the design's assumption pinned first (a cancel inside a
  rolled-back transaction leaves the job `available`, so the cancel joins the caller's
  transaction); then pull → build + cancelled + `requeue_stranded() == []`; executing → refused,
  untouched; queued verify → refused; not permitted → refused and nothing pulled; a later enqueue
  after a pull has `conflict?: false`. 18/18 green.
- `server_test.exs` (tool) and `gateway_test.exs` (API): refused without the flag, pulled with it.
- cli: `bash -n`, the usage path exits 2, and with the server binary stubbed the rpc code it
  emits parses as Elixir with `unqueue: true` / `unqueue: false`.
- Live check owed after the cut: a real queued landing pulled with
  `scripts/tlon-cli.sh send-back <id> build --unqueue <why>`, the Land row `cancelled`, no requeue
  on the next KeepUp tick.
