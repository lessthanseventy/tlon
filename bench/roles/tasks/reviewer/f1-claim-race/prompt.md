Review this diff. It is on a workline whose ticket reads: "intake: an idle builder claims the next
todo ticket itself (`Tickets.claim(ticket_id, agent)`). Several builders poll intake at once; two of
them must never both claim the same ticket."

```diff
diff --git a/server/lib/server/tickets.ex b/server/lib/server/tickets.ex
@@ -120,6 +120,20 @@ defmodule Server.Tickets do
+  @doc """
+  Claim a todo ticket for `agent`: `{:ok, ticket}`, or `{:error, :taken}` when someone already has it.
+  """
+  @spec claim(pos_integer(), String.t()) :: {:ok, Ticket.t()} | {:error, :taken | Ecto.Changeset.t()}
+  def claim(ticket_id, agent) do
+    ticket = Repo.get!(Ticket, ticket_id)
+
+    if ticket.claimed_by do
+      {:error, :taken}
+    else
+      ticket
+      |> Ticket.claim_changeset(%{claimed_by: agent, status: "doing"})
+      |> Repo.update()
+    end
+  end
diff --git a/server/test/server/tickets_test.exs b/server/test/server/tickets_test.exs
@@ -140,6 +140,16 @@ defmodule Server.TicketsTest do
+  describe "claim/2" do
+    test "the first claim wins; a second is refused" do
+      t = ticket!(workspace!(), status: "todo")
+
+      assert {:ok, %{claimed_by: "pierre", status: "doing"}} = Tickets.claim(t.id, "pierre")
+      assert {:error, :taken} = Tickets.claim(t.id, "emma")
+    end
+  end
```

End your reply with your verdict as a fenced JSON block, exactly this shape:

```json
{"verdict": "approve" | "request_changes", "findings": ["one finding per entry, naming the line and what is wrong"]}
```
