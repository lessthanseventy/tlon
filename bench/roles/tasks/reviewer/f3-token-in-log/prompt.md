Review this diff. It is on a workline whose ticket reads: "mcp: when the channel refuses a request,
log one warning line saying which path and why, so a stale token can be told apart from a wrong
url." The channel authenticates every request with a signed bearer token in the `authorization`
header; the service's log is the systemd journal, readable by any process of the user.

```diff
diff --git a/server/lib/server/mcp/auth.ex b/server/lib/server/mcp/auth.ex
@@ -58,9 +58,14 @@ defmodule Server.MCP.Auth do
   defp refuse(conn, reason) do
+    Logger.warning(
+      "mcp: refused #{conn.method} #{conn.request_path} (#{inspect(reason)}) " <>
+        "headers=#{inspect(conn.req_headers)}"
+    )
+
     conn
     |> Plug.Conn.put_resp_content_type("application/json")
     |> Plug.Conn.send_resp(401, ~s({"error":"unauthorized"}))
     |> Plug.Conn.halt()
   end
diff --git a/server/test/server/mcp/auth_test.exs b/server/test/server/mcp/auth_test.exs
@@ -77,6 +77,15 @@ defmodule Server.MCP.AuthTest do
+  test "a refused request is logged with its path and reason" do
+    log =
+      ExUnit.CaptureLog.capture_log(fn ->
+        conn(:post, "/mcp") |> put_req_header("authorization", "Bearer expired") |> Auth.call([])
+      end)
+
+    assert log =~ "mcp: refused POST /mcp (:expired)"
+  end
```

End your reply with your verdict as a fenced JSON block, exactly this shape:

```json
{"verdict": "approve" | "request_changes", "findings": ["one finding per entry, naming the line and what is wrong"]}
```
