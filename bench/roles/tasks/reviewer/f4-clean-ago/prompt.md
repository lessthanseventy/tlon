Review this diff. It is on a workline whose ticket reads: "office: a thread card shows how long ago
its thread last moved — `now` under a minute, then whole minutes `Nm` under an hour, whole hours `Nh`
under a day, else whole days `Nd`, always rounded down."

```diff
diff --git a/office/kit/ago.ts b/office/kit/ago.ts
new file mode 100644
@@ -0,0 +1,12 @@
+/** How long ago, for a card: `now` under a minute, then whole minutes, hours or days, rounded down. */
+export function ago(seconds: number): string {
+  if (seconds < 60) return "now";
+  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
+  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
+  return `${Math.floor(seconds / 86400)}d`;
+}
diff --git a/office/test/ago.test.ts b/office/test/ago.test.ts
new file mode 100644
@@ -0,0 +1,22 @@
+import { expect, test } from "bun:test";
+import { ago } from "../kit/ago";
+
+test("under a minute is now", () => {
+  expect(ago(0)).toBe("now");
+  expect(ago(59)).toBe("now");
+});
+
+test("minutes, hours and days, rounded down at each boundary", () => {
+  expect(ago(60)).toBe("1m");
+  expect(ago(3599)).toBe("59m");
+  expect(ago(3600)).toBe("1h");
+  expect(ago(86399)).toBe("23h");
+  expect(ago(86400)).toBe("1d");
+  expect(ago(3 * 86400 + 5)).toBe("3d");
+});
```

End your reply with your verdict as a fenced JSON block, exactly this shape:

```json
{"verdict": "approve" | "request_changes", "findings": ["one finding per entry, naming the line and what is wrong"]}
```
