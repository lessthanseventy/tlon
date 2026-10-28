edit_clause: a refused write is an error reply naming the file, and a raise names its cause (#442)

`Server.Source.Tools.clause/6` wrote with `File.write!`, so a write the filesystem refused
reached the agent as a bare "Internal error". The write now returns `{:error, "<path>: <reason>"}`,
and `clause/6` rescues any other raise into its message, so the cause is never hidden again.

Not reproduced: the reported body-only replace of `tool_denied/2` ("open, listed", multi-line
body) lands through `Tools.clause` on HEAD with menard 0.6.3, and a commit pins that shape. The
crash was on 10-19, when the pin was menard 0.5.0, and its cause is still unknown. The next
occurrence will name itself.

Checked: `menard run test --in server test/server/source/tools_test.exs` (14 tests; the
read-only-file test went red on `File.Error` at tools.ex:51, green after); `menard run check --in server`
(2355 tests, 0 failures).
