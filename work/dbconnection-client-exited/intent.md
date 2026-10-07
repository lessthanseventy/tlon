# Intent — workline dbconnection-client-exited (ticket #9)

## Originator's words (thread 131, andrew)

> server:check logs DBConnection "client exited" from a test that ends while holding a connection
>
> Intermittent since 2026-09-25 09:13: 0-2 lines per gate run like [info] Postgrex.Protocol disconnected: ** (DBConnection.ConnectionError) client #PID<...> exited. Some test (a spawned Task or a process killed mid-query) exits while checked out. Find it (grep the run log for the PID), make it await or allow the connection.

## Restatement

Find the server test that exits while holding a checked-out DB connection, and make it await or allow the connection so `server:check` stops logging "client exited".
