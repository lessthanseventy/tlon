Closes #713.

`Server.Recurrence.similar_tickets/2` matched on summed word rarity alone, so a few generic words ("test", "script", "smoke") shared with a long title crossed the threshold. A ticket now also needs the shared words to make up 40% of the smaller title's weight. Issue headlines (200 chars, matched on a few words by design) are unchanged.

Checked: a new test files the reported look-alikes over a long unrelated ticket (red before, green after); `menard run test` on recurrence_test.exs is green; `menard run check --in server` below.
