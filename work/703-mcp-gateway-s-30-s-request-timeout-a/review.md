APPROVE — #703

Right then. One line plus a test; it does what it says.

Checked by reading:
- `Server.MCP.Gateway.init/1` now passes `request_timeout: 200_000`. In anubis's streamable_http plug, `init` maps `:request_timeout` to `timeout:` (default 30_000), and `Session.dispatch_request` uses `opts.timeout`. The option name is right and it reaches the dispatch.
- The test asserts `%{timeout: 200_000} = Gateway.init([])`. It pins the init map, not end-to-end behaviour.
- 200 s covers the drive's 180 s wait ceiling with 20 s of margin. I took the 180 s from the code comment and pr.md, not from the drive code.

Not verified by me: I did not run the suite. pr.md reports RED then GREEN on the new test and a green gate of 2561 tests. The end-to-end smoke repro was not run, as pr.md says.

Note, not blocking: plug.ex:696 also passes `timeout` as `read_timeout` to `Plug.Conn.read_body`, so the longer value applies to reading the request body too. Harmless.