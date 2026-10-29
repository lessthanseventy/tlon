**approve** — update_ticket add_labels / append_body (#542), 6fbbef1

Read the diff (workspace.ex, server_test.exs, pr.md). I did not run the suite; pr.md reports 103 tests green, which I did not re-verify.

- `add_labels` unions with the explicit `labels` if given, else the ticket's labels; `Enum.uniq` dedupes and existing order is kept.
- `append_body` appends after an explicit `body` if given, else the ticket's body, separated by a blank line. An empty or nil body takes the text bare.
- A close's evidence is added after the appends (`Map.get(attrs, :body, ...)`), so it still lands last.
- `labels` and `body` replace exactly as before.
- Both new params are popped from `params` before the nil-reject, so they never reach the changeset as unknown attrs.
- The test covers the add path, the replace path, and a bare ticket with no body or labels.

Nits, none blocking:
- `append_body` trims the existing body, so trailing whitespace in the stored body is dropped on append. That is harmless.
- No test combines `append_body` with `status: done`. By reading the code, the order is right.