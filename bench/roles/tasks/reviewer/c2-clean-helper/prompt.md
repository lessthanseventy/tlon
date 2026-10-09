Review this diff. It is on a workline whose ticket reads: "office: a coworker's badge shows their
initials — the first letter of each of the first two words of their name, uppercased; one letter for a
one-word name; `?` for a blank name".

```diff
diff --git a/server/lib/server/office/badge.ex b/server/lib/server/office/badge.ex
@@ -12,6 +12,21 @@ defmodule Server.Office.Badge do
+  @doc """
+  A coworker's initials for their badge: the first letter of each of the first two words of
+  `name`, uppercased; `"?"` when the name is blank.
+  """
+  @spec initials(String.t()) :: String.t()
+  def initials(name) do
+    case String.split(name) do
+      [] -> "?"
+      words -> words |> Enum.take(2) |> Enum.map_join(&String.first/1) |> String.upcase()
+    end
+  end
diff --git a/server/test/server/office/badge_test.exs b/server/test/server/office/badge_test.exs
@@ -30,6 +30,16 @@ defmodule Server.Office.BadgeTest do
+  describe "initials/1" do
+    test "two words, two letters, uppercased" do
+      assert Badge.initials("pierre menard") == "PM"
+      assert Badge.initials("Herbert Quain Ashe") == "HQ"
+    end
+
+    test "one word is one letter; a blank name is ?" do
+      assert Badge.initials("tertius") == "T"
+      assert Badge.initials("   ") == "?"
+    end
+  end
```

End your reply with your verdict as a fenced JSON block, exactly this shape:

```json
{"verdict": "approve" | "request_changes", "findings": ["one finding per entry, naming the line and what is wrong"]}
```
