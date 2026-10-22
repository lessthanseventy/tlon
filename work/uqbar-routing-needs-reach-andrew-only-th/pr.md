# Uqbar routing: needs reach Andrew only through Uqbar (dark, behind `uqbar_routing`)

Closes #578 and #579. Spec and plan (with the review's amendments) are beside this file.

**What changed**
- `Server.Office.Needs`: `pass_up_rule/1` per item (always / info / `{:when, reasons}`); a `need_routing`
  table; `grouped/1` gives each item a `route` and adds the `uqbar` and `settled` (24h digest) groups.
  `settle/3` and `pass_up/4` take the caller's handle, and only `uqbar`'s is honoured. `overrule/1` sends a
  settled item back to Uqbar. Fail-open: an item unrouted past the `uqbar_route_minutes` knob (30) passes up.
- A hook's tool refusal is Uqbar's to judge; a permission refusal always rings. The one tell is Claude
  Code's `PreToolUse:` wording (`Needs.hook_refusal?/1`), because the adapter sees both refusals through
  the same check, so it sends no `source` field.
- MCP `settle_need` / `pass_up_need` (every seat sees them, and every seat but Uqbar's is refused);
  `POST /api/office/needs/overrule`.
- #579: "Hand it to Uqbar" on a tool_denied card is a post to Uqbar on the thread, not `/hand-off`, so the
  lead stays. A hook card offers no "Allowed it". Fixed on the server card and in the TUI.
- Office: the inbox runs PHONE, MACHINE, SETTLED BY UQBAR, CLIPBOARD, WITH UQBAR. The top bar still
  counts the phone only. A passed-up row shows `tip:`, and so does the room clipboard's hover tip.
- Flag `uqbar_routing` ships **off**. Off reads no rows and passes every conditional item up, which is
  today's behaviour.

**Departures from the plan:** the overrule key is `u` (hand to Uqbar), not `o`: `o` already means
"notes" and the key table keeps one meaning per key. There is no adapter `source` field (see above).

**Open:** the adapter's own holds ("Push through the server…") match neither refusal rule, so they ring
as permission refusals. Noted on #581, which is Uqbar's judgement: its playbook, the digest job, and
flipping the flag on.

**Checked:** each task red first, then green (`menard run test --in server …`). `menard run check --in
server`, `mise run office:check` (831 pass, both clock hours) and `check:names` are green. The TUI was
driven against a fixture payload: the sections, both tips and the settled `why` render, and `u` on a
settled row POSTs `/api/office/needs/overrule {"key":"question:15"}`.
