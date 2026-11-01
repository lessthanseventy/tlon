APPROVE

Diff read: `Tools.clause/6` rescue now does `Logger.error(Exception.format(:error, e, __STACKTRACE__))` before the same `{:error, Exception.message(e)}` reply. The change is minimal, `require Logger` is added, and the reply contract is unchanged. The test is fine in shape: capture_log, checks the error reply, the "** (" header, the Menard.Clause frame, and that the file is untouched.

Not verified by me: `run_verb test` returned "Internal error" in my seat, so I did not run the new test. The test depends on a non-binary CODE (123) raising inside Menard.Clause. If that doesn't raise there, the `log =~ "Menard.Clause"` assertion fails, and verify's full gate will show it.