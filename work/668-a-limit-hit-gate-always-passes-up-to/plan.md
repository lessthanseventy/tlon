# Plan — a limit-hit gate is the operator's alone (#668)

Spec: `spec.md`. Operator confirmed (msg 14532): `approve --skip-qa` is refused the same way.
Four tasks, each its own commit, test first. **Do not start until #373 (hand_to_qa) has landed** — it
edits `server/lib/server/workline.ex` too; rebase onto main first.

All paths relative to the repo root; tests run from `server/` with `menard run test <file>` (never
pipe `mix test` through tail/grep). Gate at the end: `menard run check`.

Deviation from spec §2, on purpose: `settle_need` keeps reporting `:always` (its message already says
"always reaches the operator"). A new `:limit_hit` atom for the same refusal is speculative.

Fail-open note (tertius, msg 14520): an ungraded/failed grade is "not limit-hit" here, matching
`Grade.allows?`. Left as the operator's call at the spec gate; changing it later is one line in
`limit_hit?/1`.

---

## Task 1 — `Workline.limit_hit?/1`

**Files:** `server/lib/server/workline.ex`, `server/test/server/workline_test.exs`

**Test first** — add inside the `describe "review staffing…"`-sibling area where `graded!/2`,
`@low`, `open!/1` are in scope (top level of the module, after the `"with no threshold set…"` test's
describe is fine; any place that can see `graded!/2`):

```elixir
describe "limit_hit?/1" do
  test "a review whose newest grade names a limit is limit-hit; a clean, missing or no grade is not" do
    migrates = open!(%{slug: "lh-migrates", stage: "review"})
    graded!(migrates, %{"limits" => ["a database migration"]})
    assert Workline.limit_hit?(migrates)

    clean = open!(%{slug: "lh-clean", stage: "review"})
    graded!(clean, @low)
    refute Workline.limit_hit?(clean)

    refute Workline.limit_hit?(open!(%{slug: "lh-ungraded", stage: "review"}))
  end
end
```

Run `menard run test server/test/server/workline_test.exs` → red (`limit_hit?/1 undefined`).

**Code** — in `workline.ex`, directly above the private `defp grade(thread)` (~line 887):

```elixir
@doc """
Whether the newest risk grade since the workline entered review hit a limit (`Grade.limits/1`):
such a gate is the operator's alone. An ungraded workline, or a failed grade, is not limit-hit.
"""
def limit_hit?(%Thread{} = thread), do: match?(%{"limits" => [_ | _]}, grade(thread))
```

**Done:** test green; `menard run check` clean. Commit: `workline: limit_hit?/1 (#668)`.

---

## Task 2 — `approve/2` takes `as:` and refuses Uqbar on a limit-hit gate

**Files:** `server/lib/server/workline.ex`, `server/test/server/workline_test.exs`

**Test first** — in the describe that holds `queued_lamp!/0` (~line 820; it has the git repo setup),
add a helper and tests. The limit-hit grade must be recorded after the thread is at review:

```elixir
defp parked_lamp!(grade) do
  thread = open!(%{slug: "lamp", stage: "review"})
  if grade, do: graded!(thread, grade)
  {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
  parked
end

test "Uqbar's approval of a limit-hit gate is refused; the gate stays parked" do
  parked = parked_lamp!(%{"limits" => ["a database migration"]})

  assert {:error, :limit_hit} = Workline.approve(parked, artifacts: AllPresent, land: :queue, as: "uqbar")
  assert %{awaiting: "andrew"} = Repo.get!(Server.Thread, parked.id)
  assert Workline.approval(parked) == nil
end

test "--skip-qa goes through the same door: refused for Uqbar on a limit-hit gate, no QA skip recorded" do
  parked = parked_lamp!(%{"limits" => ["a database migration"]})

  assert {:error, :limit_hit} =
           Workline.approve(parked, artifacts: AllPresent, land: :queue, as: "uqbar", skip_qa: "in a hurry")

  refute Enum.any?(Channel.thread_messages(parked), &(&1.body =~ "QA skipped"))
end

test "the operator's own approval of a limit-hit gate is accepted, recorded by the operator" do
  parked = parked_lamp!(%{"limits" => ["a database migration"]})
  assert {:ok, queued} = Workline.approve(parked, artifacts: AllPresent, land: :queue)
  assert %{"by" => "andrew"} = Workline.approval(queued)
end

test "Uqbar may approve a no-limit gate, and the ledger says uqbar, not the operator" do
  parked = parked_lamp!(@low)
  assert {:ok, queued} = Workline.approve(parked, artifacts: AllPresent, land: :queue, as: "uqbar")
  assert %{"by" => "uqbar"} = Workline.approval(queued)
end
```

`Channel` is already aliased in this file (used at line ~832). Run → red (the first two return
`{:ok, _}` / ignore `as:`; the last records `"andrew"`).

**Code** — `workline.ex`:

1. Update `approve/2`'s `@doc` (add one paragraph): "`as: handle` is the caller's seat (tlon-cli
   passes `TLON_AUTHOR`); nil is the operator. `as: "uqbar"` on a gate whose grade hit a limit is
   refused `{:error, :limit_hit}` — before anything else (a `skip_qa` included). An approval is
   recorded `by` the caller, not the gate's holder."
2. Replace the `cond` in `approve/2` with a leading guard:

```elixir
def approve(%Thread{} = thread, opts) do
  reason = opts |> Keyword.get(:skip_qa) |> to_string() |> String.trim()

  cond do
    Keyword.get(opts, :as) == "uqbar" and limit_hit?(thread) ->
      {:error, :limit_hit}

    reason != "" and qa_owed(thread, opts) ->
      landing(thread.id, fn ->
        skip_qa(thread, reason)
        do_approve(thread, opts)
      end)

    thread.awaiting ->
      landing(thread.id, fn -> do_approve(thread, opts) end)

    true ->
      {:error, :nothing_awaiting}
  end
end
```

3. In `do_approve/2`, change the one `queue(thread, "approved", thread.awaiting || operator())` call to
   `queue(thread, "approved", Keyword.get(opts, :as) || thread.awaiting || operator())`.

   (Only the review/queue path records an approval event today; non-review gates land via
   `approve_now/3` with no event — unchanged, out of scope.)

**Done:** the four tests + existing `approve` tests green (`menard run test server/test/server/workline_test.exs`);
`menard run check`. Commit: `workline: approve refuses a limit-hit gate from Uqbar; records who approved (#668)`.

---

## Task 3 — a limit-hit gate is `:always` for routing

**Files:** `server/lib/server/office/needs.ex`, `server/test/server/office/needs_test.exs`

**Test first** — in `describe "routing — a conditional need reaches the operator only through Uqbar"`
(~line 973; its setup turns `uqbar_routing` on). Add a helper next to `parked_gate/1`'s siblings and
the tests:

```elixir
defp review_gate(ws, grade) do
  {:ok, t} =
    Server.Workline.open(%{title: "g", slug: "rg-#{System.unique_integer([:positive])}", stage: "review", workspace_id: ws.id})

  {:ok, t} = t |> Server.Thread.workline_stage_changeset(%{awaiting: "andrew"}) |> Server.Repo.update()

  {:ok, _} =
    Server.Dossier.record_event(%{
      thread_id: t.id,
      kind: "check_passed",
      correlation: "workline:#{t.slug}:grade",
      detail: grade
    })

  "gate:#{t.id}"
end

test "a gate that hit a limit goes straight to the phone, never Uqbar's group; settle refuses it", %{ws: ws} do
  key = review_gate(ws, %{"limits" => ["a database migration"]})

  assert %{limits: ["a database migration"]} = Enum.find(Needs.list(), &(&1.key == key))
  assert Needs.pass_up_rule(Enum.find(Needs.list(), &(&1.key == key))) == :always

  g = Needs.grouped()
  assert [%{key: ^key, route: "pass_up"}] = Enum.filter(g.phone, &(&1.key == key))
  assert g.uqbar == []
  assert {:error, :always} = Needs.settle(key, "migration is fine", "uqbar")
  assert {:error, :always} = Needs.pass_up(key, "w", "r", "uqbar")
end

test "a gate with a clean grade still waits with Uqbar and takes a verdict", %{ws: ws} do
  key = review_gate(ws, %{"limits" => [], "decisions" => [], "scores" => %{}, "reasons" => %{}})
  assert [%{key: ^key, route: "uqbar"}] = Needs.grouped().uqbar
  assert :ok = Needs.settle(key, "fine", "uqbar")
end
```

If `Needs.grouped/0` filters by workspace or hides an item for another reason, mirror how the
neighbouring tests read `g.phone`/`g.uqbar`. Run → red (first test: no `limits` key).

**Code** — `needs.ex`:

1. `wait/2` (~line 289): add `limits` to the gate item for review gates only (the grade is
   review-scoped):

```elixir
defp wait(%Thread{stage: stage} = t, nil) when not is_nil(stage) do
  if Server.Workline.at_gate?(t),
    do: item("gate", "blocking", t, gate_text(t, stage), gated_at(t), %{stage: stage, limits: limits(t)}),
    else: question(t)
end

# the limits the review's risk grade hit (`Server.Workline.limit_hit?/1`'s reading), [] when none
defp limits(%Thread{stage: "review"} = t), do: Server.Workline.grade_limits(t)
defp limits(_t), do: []
```

2. Add to `workline.ex` (next to `limit_hit?/1`) and redefine `limit_hit?/1` through it so there is one
   reading of the grade:

```elixir
@doc "The limits the newest review grade hit — `[]` when none, ungraded, or failed."
def grade_limits(%Thread{} = thread) do
  case grade(thread) do
    %{"limits" => [_ | _] = limits} -> limits
    _ -> []
  end
end

def limit_hit?(%Thread{} = thread), do: grade_limits(thread) != []
```

3. `pass_up_rule/1`: new clause **before** the `~w(gate question …)` one:

```elixir
def pass_up_rule(%{kind: "gate", limits: [_ | _]}), do: :always
```

4. Moduledoc table: change the gate row to
   `| gate that hit a limit (db migration, …) | always |` above the existing
   `gate, question, …` row. Update the `pass_up_rule/1` `@doc` first sentence list only if it names gates.

The existing test at ~line 880 (`Needs.pass_up_rule("gate")` = broad) still holds: a bare kind has no
`limits`.

**Done:** both tests + the whole `needs_test.exs` green; `menard run check`. Commit:
`needs: a limit-hit gate always passes up (#668)`.

---

## Task 4 — `tlon-cli approve` says who is asking

**Files:** `scripts/tlon-cli.sh`

No unit harness for the rpc string; verify by hand (below). Edit the `approve)` branch:

1. Build `opts` as an Elixir keyword list, adding `as:` when `TLON_AUTHOR` is set:

```sh
    opts="[]"
    if [ "${1:-}" = "--skip-qa" ]; then
      shift
      [ "$#" -gt 0 ] || { echo 'approve --skip-qa needs a reason' >&2; exit 2; }
      opts="[skip_qa: \"$(esc "$*")\"]"
    fi
    # an agent's shell has TLON_AUTHOR (Uqbar's = uqbar); the operator's has none. The service
    # refuses a limit-hit gate to uqbar and records the approval by this handle (workline.ex approve/2).
    if [ -n "${TLON_AUTHOR:-}" ]; then
      opts="${opts%]}"; [ "$opts" = "[" ] || opts="$opts, "
      opts="${opts}as: \"$(esc "$TLON_AUTHOR")\"]"
    fi
```

2. Add to the header comment (line ~75): `#     (TLON_AUTHOR set → approved as that seat; Uqbar's cannot approve a limit-hit gate)`.

**Verify:** `sh -n scripts/tlon-cli.sh` (exit 0). Then print the rpc string without running it: temporarily
`echo` instead of `exec "$SERVER" rpc` is NOT needed — instead run
`SERVER=echo TLON_AUTHOR=uqbar scripts/tlon-cli.sh approve 1 --skip-qa why` and check the output
contains `[skip_qa: "why", as: "uqbar"]`; with `env -u TLON_AUTHOR` it contains `[skip_qa: "why"]` and
no `as:`; bare `approve 1` as uqbar gives `[as: "uqbar"]`. (If `$SERVER` is not overridable from env,
read the script's `SERVER=` line and use whatever seam it offers; if none, paste the three expanded
`opts` values by sourcing the snippet in a subshell.) Record the three outputs with `record_check`.

**Done:** the three `opts` shapes are right; `sh -n` clean. Commit: `tlon-cli: approve passes the caller's seat (#668)`.

---

## Final check (before review)
`menard run check` green on the branch. In the hand-off to review, state plainly: an Uqbar approval of
a no-limit gate is now recorded `by: "uqbar"` (previously the operator); the env var is a convention,
not a boundary (spec §1); ungraded counts as not limit-hit (fail-open, tertius's note).
