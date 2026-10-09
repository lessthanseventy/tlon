**request_changes**

1. **Blocker: `reply_to` never reaches the client.** `Server.Office.thread_view/2` (server/lib/server/office.ex:~118) maps messages to `%{id, author, body, at, kind}`. It has no `reply_to`. The `replies()` branch "replying to an operator post" is therefore dead against the real API. The unit test passes only because it hand-builds `reply_to`. Only the `@X` heuristic works live. Fix: add `reply_to: &1.reply_to` to that map, and add a server test that `thread_view` carries it. `kit/types.ts` already claims the field, so the type is currently lying.

2. **Minor: the `@X` heuristic is sticky.** `asked` persists until the operator's next post. Any later post by X on the lobby, even unrelated chatter, counts as an answer and gets a balloon and a notification. Clear `asked[X]` after X's first post, or limit it to the next post.

3. **Minor: first-poll seeding.** `answered === null` seeds silently, which is right. But `data.thread` returns only one page, so an operator post that scrolled out of the page makes `mine` miss its replies. Acceptable, but name it in the doc comment.

Otherwise the diff is clean and small.

Verified by reading the diff and the `thread_view` code. I did not run the tests.