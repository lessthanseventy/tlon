Closes #669 (office TUI half).

An ask on the thread card or in the needs inbox can now be answered with a note: `"` opens a one-line box listing the options; "2 the old one leaks" + Enter sends `{"key": "no the old one leaks"}` through the same POST /api/office/prompts/:id. The server already splits the first word as the key and posts the rest on the asker's thread, so no server change. Digits 1–9 stay one-tap; dialogs (which type into a pane) get no note key. `"` is the one free key whose verb ("note") matches.

Checked: test/answer-note.test.ts drives the real TUI against a stub server (note body is "<key> <note>", plain 1 still sends the bare key); keys.test.ts, reply-box.test.ts green.
