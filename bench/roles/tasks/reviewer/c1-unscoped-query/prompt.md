Review this diff. It is on a workline whose ticket reads: "tickets: the board can filter by status
(`Tickets.list(workspace_id, status: "todo")`)". Several workspaces share one database; a board must
only ever show its own workspace's tickets.

```diff
diff --git a/server/lib/server/tickets.ex b/server/lib/server/tickets.ex
@@ -41,10 +41,14 @@ defmodule Server.Tickets do
-  @doc "The workspace's tickets, in board order."
-  def list(workspace_id) do
-    from(t in Ticket, where: t.workspace_id == ^workspace_id)
+  @doc "The workspace's tickets, in board order; `status:` keeps one column."
+  def list(workspace_id, opts \\ []) do
+    status = opts[:status]
+
+    from(t in Ticket)
+    |> then(fn q -> if status, do: where(q, [t], t.status == ^status), else: q end)
     |> order_by([t], asc: t.position)
     |> Repo.all()
   end
diff --git a/server/test/server/tickets_test.exs b/server/test/server/tickets_test.exs
@@ -88,6 +88,16 @@ defmodule Server.TicketsTest do
+  test "status: keeps one column" do
+    ws = workspace!()
+    todo = ticket!(ws, status: "todo")
+    _doing = ticket!(ws, status: "doing")
+
+    assert [%{id: id}] = Tickets.list(ws.id, status: "todo")
+    assert id == todo.id
+  end
```

End your reply with your verdict as a fenced JSON block, exactly this shape:

```json
{"verdict": "approve" | "request_changes", "findings": ["one finding per entry, naming the line and what is wrong"]}
```
