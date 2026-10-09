Bug report: a ticket whose thread was closed without merging holds a workline slot forever.

Ticket #40 sat at `todo` for hours after its promoted thread was closed at stage `build` (its work
landed through another workline). `Server.Intake` counts every `todo` ticket as in flight, so that
ticket held one of the `max_worklines` slots indefinitely; nothing ever moves it on, because the
stalled-ticket pass skips a ticket that has a promoted thread.

Fix it, test-first, and commit: a `todo` ticket whose promoted thread (a `ticket_threads` row of
kind `"promoted"`) is closed must hold no slot, so `Server.Intake.run/1` routes the next backlog
ticket instead of waiting behind it.

This is a change to existing behaviour: no new public function, field or tool is involved. The
project is the Elixir/Phoenix app under `server/` (`cd server && mix test <file>` runs a test file).
