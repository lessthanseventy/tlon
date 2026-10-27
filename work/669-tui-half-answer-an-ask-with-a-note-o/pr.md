Closes #669 (office TUI half).

An ask in the needs inbox can now be answered with a note: `"` opens a one-line box listing the options; its first word is the option's number, key or label, the rest goes on as typed. "2 the old one leaks" + Enter sends `{"key": "no the old one leaks"}` through the same POST /api/office/prompts/:id. The server already splits the first word as the key and posts the rest on the asker's thread, so no server change. One-tap keys stay one-tap. `"` is the one free key whose verb ("note") matches.

The same key on a thread card reaches that thread's open prompt, which is a pane dialog (or the release gate), never an ask: the server types the key into the pane and then the note, which is how a "No, and tell it what to do differently" dialog takes a reason. The key's mode says so.

Checked: test/answer-note-inbox.test.ts (the inbox ask: number, key and label first words, spacing kept, plain key sends the bare key) and test/answer-note.test.ts (thread-card prompt) drive the real TUI against a stub server; keys.test.ts green.
