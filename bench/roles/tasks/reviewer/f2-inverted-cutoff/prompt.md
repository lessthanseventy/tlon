Review this diff. It is on a workline whose ticket reads: "staffing: a session nobody has heard from
in 30 minutes is ended by the sweep (`Staff.reap_stale/1`); a session active within the last 30
minutes is left alone."

```diff
diff --git a/server/lib/server/staff.ex b/server/lib/server/staff.ex
@@ -210,6 +210,19 @@ defmodule Server.Staff do
+  @stale_after_s 30 * 60
+
+  @doc """
+  End every open session not active in the last #{div(@stale_after_s, 60)} minutes.
+  Returns `{count, nil}` as `Repo.update_all/2` does.
+  """
+  def reap_stale(now \\ DateTime.utc_now()) do
+    cutoff = DateTime.add(now, -@stale_after_s, :second)
+
+    from(s in Session, where: is_nil(s.ended_at) and s.last_active_at > ^cutoff)
+    |> Repo.update_all(set: [ended_at: DateTime.truncate(now, :second)])
+  end
diff --git a/server/test/server/staff_test.exs b/server/test/server/staff_test.exs
@@ -301,6 +301,12 @@ defmodule Server.StaffTest do
+  describe "reap_stale/1" do
+    test "returns how many sessions it ended" do
+      assert {n, nil} = Staff.reap_stale()
+      assert is_integer(n)
+    end
+  end
```

End your reply with your verdict as a fenced JSON block, exactly this shape:

```json
{"verdict": "approve" | "request_changes", "findings": ["one finding per entry, naming the line and what is wrong"]}
```
