# Plan — Life step 4: home workspace, routines, quests, XP

Source: `work/home-life-routines/spec.md` (read first — every decision below cites it).
Each task is one commit, on `work/home-life-routines`, rebased on top of the last. Verify each
with `~/projects/menard/bin/menard run test --in server [file[:line]]` unless noted; the whole
branch's gate is `~/projects/menard/bin/menard run check --in server` (run once, after task 13).

All file paths are relative to `server/`.

## Task 1 — `home` becomes a fourth `workspace.type` value

Spec §2.1/§8.5. Migration only; nothing reads the new value yet, so this is safe alone.

**`priv/repo/migrations/20261007000000_workspace_home_type.exs`** (new file):

```elixir
defmodule Server.Repo.Migrations.WorkspaceHomeType do
  @moduledoc false
  use Ecto.Migration

  # home joins code|life|blank (life step 4): the life side's workspace kind.
  def up do
    execute "ALTER TABLE workspace DROP CONSTRAINT workspace_type_check"
    execute "ALTER TABLE workspace ADD CONSTRAINT workspace_type_check CHECK (type IN ('code','life','blank','home'))"
  end

  def down do
    execute "ALTER TABLE workspace DROP CONSTRAINT workspace_type_check"
    execute "ALTER TABLE workspace ADD CONSTRAINT workspace_type_check CHECK (type IN ('code','life','blank'))"
  end
end
```

**Failing test first** — append to `test/server/workspaces_test.exs` (check the file for its
existing `describe`/alias setup and match its style; the assertion is what matters):

```elixir
test "home joins the type closed set" do
  assert {:ok, ws} = Server.Workspaces.register(%{name: "home-test-#{System.unique_integer()}", type: "home"})
  assert ws.type == "home"
end
```

Run the migration: `mix ecto.migrate` (against the test db — `MIX_ENV=test mix ecto.migrate`).
**Definition of done**: the test above goes from erroring (CHECK violation) to green.
**Verify**: `~/projects/menard/bin/menard run test --in server test/server/workspaces_test.exs`

## Task 2 — `routine` / `routine_run` / `quest` tables

Spec §2. Raw-SQL migration, matching `20261005000000_schedule.exs`'s style exactly. Singular
table names (`routine`, `routine_run`, `quest`), matching `workspace`/`schedule`/`schedule_run`.

**`priv/repo/migrations/20261007010000_life.exs`** (new file):

```elixir
defmodule Server.Repo.Migrations.Life do
  @moduledoc false
  use Ecto.Migration

  # The life side's two rows (life step 4, spec §2): a recurring routine and its runs (the only
  # thing written when it's done), and a one-off quest. xp/level/streak are views — nothing here.
  def up do
    execute """
    CREATE TABLE routine (
      id BIGSERIAL PRIMARY KEY,
      workspace_id BIGINT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      every TEXT NOT NULL,
      window_minutes INTEGER NOT NULL DEFAULT 60,
      xp INTEGER NOT NULL DEFAULT 10,
      tile TEXT,
      enabled BOOLEAN NOT NULL DEFAULT true,
      created_at TIMESTAMPTZ NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX routine_workspace ON routine (workspace_id)"

    execute """
    CREATE TABLE routine_run (
      id BIGSERIAL PRIMARY KEY,
      routine_id BIGINT NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
      due_at TIMESTAMPTZ NOT NULL,
      done_at TIMESTAMPTZ NOT NULL,
      late BOOLEAN NOT NULL,
      created_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX routine_run_routine ON routine_run (routine_id, due_at DESC)"

    execute """
    CREATE TABLE quest (
      id BIGSERIAL PRIMARY KEY,
      workspace_id BIGINT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      due_at TIMESTAMPTZ,
      xp INTEGER NOT NULL DEFAULT 10,
      done_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX quest_workspace ON quest (workspace_id)"
  end

  def down do
    execute "DROP TABLE quest"
    execute "DROP TABLE routine_run"
    execute "DROP TABLE routine"
  end
end
```

No addition to `test/support/test_db.ex`'s `@ordered` list: all three tables cascade from
`workspace` on delete (same as `schedule`/`schedule_run`, which also aren't in `@ordered` —
`Workspace`'s own delete at the end of that list clears them). Note this in the commit so nobody
"fixes" it later.

**Verify**: `MIX_ENV=test mix ecto.migrate && mix compile` — no schema yet, so this task is just
the migration applying cleanly. No ExUnit test (nothing to assert against yet); the next task's
tests are what exercise these tables.

## Task 3 — schema modules: `Server.Routine`, `Server.RoutineRun`, `Server.Quest`

Spec §2. Mirrors `Server.Schedule`'s shape (`lib/server/schedule.ex`) exactly: plain
`Ecto.Schema`, a `create_changeset/1`, app-stamped `created_at`/`updated_at`.

**`lib/server/routine.ex`** (new file):

```elixir
defmodule Server.Routine do
  @moduledoc """
  A recurring thing the operator does (life step 4, spec §2): "brush teeth", nightly. `every` is
  a cron expression or a shortcut (`@daily`, `@weekly` — `Server.Schedules`' own parser, no
  second one). `window_minutes` is how long after `every` fires it still counts on time.
  `tile`, if set, names a room tile (uninterpreted here — the Floor track's business).
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "routine" do
    field :title, :string
    field :every, :string
    field :window_minutes, :integer, default: 60
    field :xp, :integer, default: 10
    field :tile, :string
    field :enabled, :boolean, default: true
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime
    belongs_to :workspace, Server.Workspace
  end

  @mutable [:title, :every, :window_minutes, :xp, :tile, :enabled]

  def create_changeset(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %__MODULE__{}
    |> cast(attrs, [:workspace_id | @mutable])
    |> validate_required([:workspace_id, :title, :every])
    |> validate_every()
    |> foreign_key_constraint(:workspace_id)
    |> put_change(:created_at, now)
    |> put_change(:updated_at, now)
  end

  def update_changeset(%__MODULE__{} = r, attrs) do
    r
    |> cast(attrs, @mutable)
    |> validate_required([:title, :every])
    |> validate_every()
    |> put_change(:updated_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  defp validate_every(cs) do
    case get_field(cs, :every) do
      nil -> cs
      every -> if match?({:ok, _}, Oban.Cron.Expression.parse(every)), do: cs, else: add_error(cs, :every, "not a cron: #{every}")
    end
  end
end
```

**`lib/server/routine_run.ex`** (new file):

```elixir
defmodule Server.RoutineRun do
  @moduledoc """
  One completion of a `Server.Routine` (life step 4, spec §2) — the ONLY row written when the
  operator does the thing. `due_at` is the occurrence it satisfies; `late` is computed once, at
  the stamp, and never recomputed. Immutable: no `updated_at`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "routine_run" do
    field :due_at, :utc_datetime
    field :done_at, :utc_datetime
    field :late, :boolean
    field :created_at, :utc_datetime
    belongs_to :routine, Server.Routine
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:routine_id, :due_at, :done_at, :late])
    |> validate_required([:routine_id, :due_at, :done_at, :late])
    |> foreign_key_constraint(:routine_id)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end
end
```

**`lib/server/quest.ex`** (new file):

```elixir
defmodule Server.Quest do
  @moduledoc """
  A one-off thing the operator does (life step 4, spec §2): "book the dentist". `due_at` is
  optional. `done_at` is set once, by `Server.Life.quest_done/2`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "quest" do
    field :title, :string
    field :due_at, :utc_datetime
    field :xp, :integer, default: 10
    field :done_at, :utc_datetime
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime
    belongs_to :workspace, Server.Workspace
  end

  @mutable [:title, :due_at, :xp]

  def create_changeset(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %__MODULE__{}
    |> cast(attrs, [:workspace_id | @mutable])
    |> validate_required([:workspace_id, :title])
    |> foreign_key_constraint(:workspace_id)
    |> put_change(:created_at, now)
    |> put_change(:updated_at, now)
  end

  def done_changeset(%__MODULE__{} = q, at) do
    q |> change(done_at: DateTime.truncate(at, :second), updated_at: DateTime.truncate(DateTime.utc_now(), :second))
  end
end
```

No test of its own — these are exercised by task 5 onward. **Verify**: `mix compile
--warnings-as-errors` (the schemas alone must compile clean).

## Task 4 — `Server.Schedules.next_occurrence/2`: the one shared cron parser

Spec §3's "`every`'s parser is reused whole from `Server.Schedule`". `Server.Schedules`
(`lib/server/schedules.ex`) already has the local-time plumbing (`to_local/1`, `from_local/2`,
`after_local/2`) as private functions, used by `slot/1` for "when does this fire next". Expose
one public wrapper so `Server.Life` doesn't duplicate it.

**Failing test first** — append to `test/server/schedules_test.exs`:

```elixir
test "next_occurrence/2 is the next local firing strictly after the given time" do
  after_at = DateTime.new!(~D[2026-01-01], ~T[00:00:00], "Etc/UTC")
  next = Server.Schedules.next_occurrence("0 9 * * *", after_at)
  assert %DateTime{hour: 9} = Server.Schedules.local_now() |> Map.put(:hour, next.hour)
  assert DateTime.compare(next, after_at) == :gt
end
```

(The assertion only needs to prove "after, and at the cron's hour" — `local_now()` is reused here
only to get a correctly-typed sentinel for the pattern match; the real check is the two lines
below it. If that reads awkwardly once written, simplify to `assert next.hour == 9` directly —
whichever is clearer in context.)

**`lib/server/schedules.ex`** — add, near `next_at/2`:

```elixir
@doc "The next local occurrence of `cron` (or `@daily`/`@weekly`/…) strictly after `after_at`."
@spec next_occurrence(String.t(), DateTime.t()) :: DateTime.t()
def next_occurrence(cron, after_at), do: cron |> Expression.parse!() |> after_local(after_at)
```

**Verify**: `~/projects/menard/bin/menard run test --in server test/server/schedules_test.exs`

## Task 5 — `Server.Life`: `level/1`, `next_level_at/1` (pure)

Spec §3. No DB — these are integer math, tested as such first.

**`test/server/life_test.exs`** (new file):

```elixir
defmodule Server.LifeTest do
  use ExUnit.Case, async: true

  describe "level/1" do
    test "0 xp is level 0" do
      assert Server.Life.level(0) == 0
    end

    test "just under a boundary stays at the lower level" do
      assert Server.Life.level(99) == 0
      assert Server.Life.level(399) == 1
    end

    test "at a boundary reaches the next level" do
      assert Server.Life.level(100) == 1
      assert Server.Life.level(400) == 2
    end
  end

  describe "next_level_at/1" do
    test "the absolute xp threshold for the next level" do
      assert Server.Life.next_level_at(0) == 100
      assert Server.Life.next_level_at(100) == 400
      assert Server.Life.next_level_at(399) == 400
    end
  end
end
```

**`lib/server/life.ex`** (new file):

```elixir
defmodule Server.Life do
  @moduledoc """
  XP, level and streaks as DERIVED VIEWS over `Server.RoutineRun`/`Server.Quest` (life step 4,
  spec §3) — nothing is cached. Every function scopes to one `workspace_id` except the pure
  integer math (`level/1`, `next_level_at/1`).
  """

  import Ecto.Query

  alias Server.Quest
  alias Server.Repo
  alias Server.Routine
  alias Server.RoutineRun
  alias Server.Schedules

  @doc "floor(sqrt(xp / 100)) — quick at first, slows down. A placeholder curve (spec §10)."
  @spec level(integer) :: integer
  def level(xp) when xp >= 0, do: xp |> Kernel./(100) |> :math.sqrt() |> Float.floor() |> trunc()

  @doc "The absolute xp threshold for `level(xp) + 1` — a stable target, not a remaining count."
  @spec next_level_at(integer) :: integer
  def next_level_at(xp) do
    next = level(xp) + 1
    100 * next * next
  end
end
```

**Verify**: `~/projects/menard/bin/menard run test --in server test/server/life_test.exs`

## Task 6 — `Server.Life.current_due_at/2` and `previous_due_at/2` (pure)

Spec §3's `current_due`. Takes a `%Routine{}` struct and a `now` — no DB read, so testable with
an in-memory struct (never inserted). Walks forward from `routine.created_at` one occurrence at a
time via task 4's `Schedules.next_occurrence/2`, keeping the last one `<= now`.

**Append to `test/server/life_test.exs`**:

```elixir
describe "current_due_at/2" do
  test "the most recent occurrence at or before now" do
    created = DateTime.new!(~D[2026-01-01], ~T[00:00:00], "Etc/UTC")
    routine = %Server.Routine{every: "0 9 * * *", created_at: created}
    now = DateTime.new!(~D[2026-01-05], ~T[12:00:00], "Etc/UTC")

    due = Server.Life.current_due_at(routine, now)

    assert due.hour == 9
    assert Date.compare(DateTime.to_date(due), ~D[2026-01-05]) == :eq
  end

  test "nil before the routine's first occurrence" do
    created = DateTime.new!(~D[2026-01-05], ~T[10:00:00], "Etc/UTC")
    routine = %Server.Routine{every: "0 9 * * *", created_at: created}
    now = DateTime.new!(~D[2026-01-05], ~T[11:00:00], "Etc/UTC")

    assert Server.Life.current_due_at(routine, now) == nil
  end
end
```

**Append to `lib/server/life.ex`**:

```elixir
@doc "The most recent occurrence of `routine.every` at or before `now`, or nil if none has fired yet."
@spec current_due_at(Routine.t(), DateTime.t()) :: DateTime.t() | nil
def current_due_at(%Routine{every: every, created_at: created_at}, now) do
  walk_due(every, created_at, now, nil)
end

defp walk_due(every, cursor, now, last) do
  next = Schedules.next_occurrence(every, cursor)

  if DateTime.compare(next, now) == :gt do
    last
  else
    walk_due(every, next, now, next)
  end
end

@doc "The occurrence of `routine.every` strictly before `before_due_at`, or nil."
@spec previous_due_at(Routine.t(), DateTime.t()) :: DateTime.t() | nil
def previous_due_at(%Routine{} = routine, before_due_at) do
  current_due_at(routine, DateTime.add(before_due_at, -1, :second))
end
```

This walk is bounded by how many occurrences have fired since the routine was created — fine for
daily/weekly habits (the plan's actual use); flagged, not optimized (YAGNI) unless it bites.

**Verify**: `~/projects/menard/bin/menard run test --in server test/server/life_test.exs`

## Task 7 — `Server.Life.xp/1` and `late?/3`

Spec §3. Needs real rows — the first DB-backed test in this suite. Uses
`Server.Workspaces.register/1` (type `"home"`, from task 1) to seed a workspace, then inserts
routine/routine_run/quest rows directly through the schema modules from task 3.

**Append to `test/server/life_test.exs`**, with a `setup` the later tasks' tests reuse:

```elixir
describe "xp/1" do
  setup do
    {:ok, ws} = Server.Workspaces.register(%{name: "life-xp-#{System.unique_integer()}", type: "home"})
    {:ok, routine} = Server.Routine.create_changeset(%{workspace_id: ws.id, title: "stretch", every: "@daily"}) |> Server.Repo.insert()
    %{ws: ws, routine: routine}
  end

  test "on-time runs count full xp, late runs count half, quests add their own", %{ws: ws, routine: routine} do
    due = DateTime.utc_now() |> DateTime.truncate(:second)
    insert_run!(routine, due, done_at: due, late: false)
    insert_run!(routine, DateTime.add(due, -86400), done_at: DateTime.add(due, -86400), late: true)

    {:ok, quest} = Server.Quest.create_changeset(%{workspace_id: ws.id, title: "dentist", xp: 20}) |> Server.Repo.insert()
    quest |> Server.Quest.done_changeset(DateTime.utc_now()) |> Server.Repo.update!()

    # routine.xp defaults to 10: 10 (on time) + 5 (late, integer div) + 20 (quest) = 35
    assert Server.Life.xp(ws.id) == 35
  end

  defp insert_run!(routine, due_at, done_at: done_at, late: late) do
    %{routine_id: routine.id, due_at: due_at, done_at: done_at, late: late}
    |> Server.RoutineRun.create_changeset()
    |> Server.Repo.insert!()
  end
end

describe "late?/3" do
  test "on time at the boundary" do
    due = ~U[2026-01-01 09:00:00Z]
    refute Server.Life.late?(due, DateTime.add(due, 60 * 60), 60)
  end

  test "late one second past the window" do
    due = ~U[2026-01-01 09:00:00Z]
    assert Server.Life.late?(due, DateTime.add(due, 60 * 60 + 1), 60)
  end
end
```

**Append to `lib/server/life.ex`**:

```elixir
@doc "done_at strictly after due_at + window_minutes is late; at the boundary or before is on time."
@spec late?(DateTime.t(), DateTime.t(), integer) :: boolean
def late?(due_at, done_at, window_minutes) do
  DateTime.compare(done_at, DateTime.add(due_at, window_minutes * 60)) == :gt
end

@doc "Σ routine.xp over on-time runs + half (integer div) over late runs + Σ quest.xp over done quests."
@spec xp(integer) :: integer
def xp(workspace_id) do
  routine_xp =
    from(rr in RoutineRun,
      join: r in Routine,
      on: r.id == rr.routine_id,
      where: r.workspace_id == ^workspace_id,
      select: sum(fragment("CASE WHEN ? THEN ? / 2 ELSE ? END", rr.late, r.xp, r.xp))
    )
    |> Repo.one()

  quest_xp =
    from(q in Quest, where: q.workspace_id == ^workspace_id and not is_nil(q.done_at), select: sum(q.xp))
    |> Repo.one()

  (routine_xp || 0) + (quest_xp || 0)
end
```

**Verify**: `~/projects/menard/bin/menard run test --in server test/server/life_test.exs`

## Task 8 — `Server.Life.due/1` and `streak/2`

Spec §3's "streak with a gap" is the headline test here.

**Append to `test/server/life_test.exs`**:

```elixir
describe "streak/2" do
  setup do
    {:ok, ws} = Server.Workspaces.register(%{name: "life-streak-#{System.unique_integer()}", type: "home"})
    created = ~U[2026-01-01 00:00:00Z]
    {:ok, routine} =
      Server.Routine.create_changeset(%{workspace_id: ws.id, title: "stretch", every: "0 9 * * *", created_at: created})
      |> Ecto.Changeset.force_change(:created_at, created)
      |> Server.Repo.insert()

    %{routine: routine}
  end

  test "counts back from now, stopping at the first totally-missed due", %{routine: routine} do
    now = DateTime.new!(~D[2026-01-08], ~T[10:00:00], "Etc/UTC")
    # due instances: 01-02 .. 01-08 at 09:00. Run everything except 01-05 (the gap).
    for day <- [2, 3, 4, 6, 7, 8] do
      due = DateTime.new!(Date.new!(2026, 1, day), ~T[09:00:00], "Etc/UTC")
      insert_run!(routine, due, done_at: due, late: false)
    end

    assert Server.Life.streak(routine, now) == 3
  end

  defp insert_run!(routine, due_at, done_at: done_at, late: late) do
    %{routine_id: routine.id, due_at: due_at, done_at: done_at, late: late}
    |> Server.RoutineRun.create_changeset()
    |> Server.Repo.insert!()
  end
end
```

(`created_at` is normally app-stamped at insert — `force_change` here only to seed a controlled
start date for the test; production callers never do this.)

**Append to `lib/server/life.ex`**:

```elixir
@doc "Every enabled routine whose current due has no run yet, with how long is left in its window."
@spec due(integer, DateTime.t()) :: [map()]
def due(workspace_id, now \\ DateTime.utc_now()) do
  for routine <- Repo.all(from r in Routine, where: r.workspace_id == ^workspace_id and r.enabled),
      due_at = current_due_at(routine, now),
      due_at != nil,
      not has_run?(routine.id, due_at) do
    %{
      routine_id: routine.id,
      title: routine.title,
      due_at: due_at,
      window_remaining: DateTime.diff(DateTime.add(due_at, routine.window_minutes * 60), now)
    }
  end
end

@doc "Consecutive met dues counted back from now; 0 if the current due is unmet. Late still counts."
@spec streak(Routine.t(), DateTime.t()) :: integer
def streak(%Routine{} = routine, now \\ DateTime.utc_now()) do
  case current_due_at(routine, now) do
    nil -> 0
    due_at -> if has_run?(routine.id, due_at), do: 1 + streak_before(routine, due_at), else: 0
  end
end

defp streak_before(routine, due_at) do
  case previous_due_at(routine, due_at) do
    nil -> 0
    prev -> if has_run?(routine.id, prev), do: 1 + streak_before(routine, prev), else: 0
  end
end

defp has_run?(routine_id, due_at) do
  Repo.exists?(from rr in RoutineRun, where: rr.routine_id == ^routine_id and rr.due_at == ^due_at)
end
```

**Verify**: `~/projects/menard/bin/menard run test --in server test/server/life_test.exs`

## Task 9 — `Server.Life.routine_done/2`, `quest_done/2`

Spec §3's `level_up` and "already done" guard. The level_up test sits a workspace one xp below a
boundary and stamps across it.

**Append to `test/server/life_test.exs`**:

```elixir
describe "routine_done/2" do
  setup do
    {:ok, ws} = Server.Workspaces.register(%{name: "life-done-#{System.unique_integer()}", type: "home"})
    {:ok, routine} =
      Server.Routine.create_changeset(%{workspace_id: ws.id, title: "stretch", every: "@daily", xp: 2})
      |> Server.Repo.insert()

    %{ws: ws, routine: routine}
  end

  test "stamps a run and reports level_up only on the crossing stamp", %{ws: ws, routine: routine} do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    due = Server.Life.current_due_at(routine, now) || now

    # 49 xp of prior quests: one short of the level-1 boundary (100).
    {:ok, pad} = Server.Quest.create_changeset(%{workspace_id: ws.id, title: "pad", xp: 49}) |> Server.Repo.insert()
    pad |> Server.Quest.done_changeset(now) |> Server.Repo.update!()

    {:ok, _run, level_up} = Server.Life.routine_done(routine.id, now)
    assert level_up == true

    assert Server.Life.routine_done(routine.id, now) == {:error, :already_done}
  end

  test "a second stamp of the same instance is refused, not a second run", %{routine: routine} do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    assert {:ok, _run, _} = Server.Life.routine_done(routine.id, now)
    assert Server.Life.routine_done(routine.id, now) == {:error, :already_done}
  end
end
```

(49 + routine.xp=2 doesn't reach 100 on its own — re-check against task 5's curve before trusting
this literally: `level(49) == 0`, `level(51) == 0` since `next_level_at(0) == 100`. Pick xp values
that actually straddle the boundary when writing this for real — e.g. pad to 99, routine xp 2, so
49→101 crosses level 0→1. The point proven, not the arithmetic pasted here, is load-bearing;
recompute against `Server.Life.level/1` directly before trusting a magic number in the test.)

**Append to `lib/server/life.ex`**:

```elixir
@doc """
Stamps the routine's current due instance as done at `at` (default now). `{:ok, run, level_up}`,
or `{:error, :not_found | :not_due | :already_done}`. `level_up` compares the workspace's level
before and after this one write.
"""
@spec routine_done(integer, DateTime.t()) :: {:ok, RoutineRun.t(), boolean} | {:error, atom}
def routine_done(routine_id, at \\ DateTime.utc_now()) do
  at = DateTime.truncate(at, :second)

  case Repo.get(Routine, routine_id) do
    nil -> {:error, :not_found}
    routine -> stamp_routine(routine, at)
  end
end

defp stamp_routine(routine, at) do
  case current_due_at(routine, at) do
    nil -> {:error, :not_due}
    due_at -> if has_run?(routine.id, due_at), do: {:error, :already_done}, else: insert_run(routine, due_at, at)
  end
end

defp insert_run(routine, due_at, at) do
  xp_before = xp(routine.workspace_id)

  {:ok, run} =
    %{routine_id: routine.id, due_at: due_at, done_at: at, late: late?(due_at, at, routine.window_minutes)}
    |> RoutineRun.create_changeset()
    |> Repo.insert()

  {:ok, run, level(xp(routine.workspace_id)) > level(xp_before)}
end

@doc "Marks a quest done at `at` (default now). `{:ok, quest, level_up}` or `{:error, :not_found | :already_done}`."
@spec quest_done(integer, DateTime.t()) :: {:ok, Quest.t(), boolean} | {:error, atom}
def quest_done(quest_id, at \\ DateTime.utc_now()) do
  case Repo.get(Quest, quest_id) do
    nil -> {:error, :not_found}
    %Quest{done_at: done_at} when not is_nil(done_at) -> {:error, :already_done}
    quest -> do_quest_done(quest, at)
  end
end

defp do_quest_done(quest, at) do
  xp_before = xp(quest.workspace_id)
  {:ok, quest} = quest |> Quest.done_changeset(at) |> Repo.update()
  {:ok, quest, level(xp(quest.workspace_id)) > level(xp_before)}
end
```

**Verify**: `~/projects/menard/bin/menard run test --in server test/server/life_test.exs`

## Task 10 — `Server.Life.status/1` and `create_routine/2`, `update_routine/2`, `create_quest/2`

Spec §3/§4. Assembles everything above into the `/api/life` body; the create/update wrappers are
what the routes (task 12) call. `today` uses `Schedules.local_now/0` (spec §8.5), not UTC.

**Append to `test/server/life_test.exs`**:

```elixir
describe "status/1" do
  test "assembles xp, level, next_level_at, streaks, due, quests, today" do
    {:ok, ws} = Server.Workspaces.register(%{name: "life-status-#{System.unique_integer()}", type: "home"})
    {:ok, routine} = Server.Life.create_routine(ws.id, %{title: "stretch", every: "@daily"})
    {:ok, _quest} = Server.Life.create_quest(ws.id, %{title: "dentist"})

    status = Server.Life.status(ws.id)

    assert status.xp == 0
    assert status.level == 0
    assert status.next_level_at == 100
    assert Map.has_key?(status.streaks, routine.id)
    assert is_list(status.due)
    assert is_list(status.quests)
    assert is_list(status.today)
  end
end
```

**Append to `lib/server/life.ex`**:

```elixir
@doc "A new routine. `{:ok, routine}` or `{:error, changeset}`."
@spec create_routine(integer, map) :: {:ok, Routine.t()} | {:error, Ecto.Changeset.t()}
def create_routine(workspace_id, attrs), do: Map.put(attrs, :workspace_id, workspace_id) |> Routine.create_changeset() |> Repo.insert()

@doc "Edit a routine's mutable fields."
@spec update_routine(Routine.t(), map) :: {:ok, Routine.t()} | {:error, Ecto.Changeset.t()}
def update_routine(%Routine{} = routine, attrs), do: routine |> Routine.update_changeset(attrs) |> Repo.update()

@doc "A new quest. `{:ok, quest}` or `{:error, changeset}`."
@spec create_quest(integer, map) :: {:ok, Quest.t()} | {:error, Ecto.Changeset.t()}
def create_quest(workspace_id, attrs), do: Map.put(attrs, :workspace_id, workspace_id) |> Quest.create_changeset() |> Repo.insert()

@doc "The `GET /api/life` body for one workspace."
@spec status(integer) :: map
def status(workspace_id) do
  now = Schedules.local_now()
  routines = Repo.all(from r in Routine, where: r.workspace_id == ^workspace_id and r.enabled)
  xp = xp(workspace_id)

  %{
    xp: xp,
    level: level(xp),
    next_level_at: next_level_at(xp),
    streaks: Map.new(routines, &{&1.id, streak(&1, now)}),
    due: due(workspace_id, now),
    quests: open_quests(workspace_id),
    today: today(routines, now)
  }
end

defp open_quests(workspace_id) do
  Repo.all(
    from q in Quest,
      where: q.workspace_id == ^workspace_id and is_nil(q.done_at),
      order_by: [asc_nulls_last: q.due_at]
  )
end

defp today(routines, now) do
  today_date = DateTime.to_date(now)

  for routine <- routines,
      due_at = current_due_at(routine, now),
      due_at != nil,
      Date.compare(DateTime.to_date(due_at), today_date) == :eq do
    %{routine_id: routine.id, title: routine.title, due_at: due_at, done: has_run?(routine.id, due_at)}
  end
end
```

**Verify**: `~/projects/menard/bin/menard run test --in server test/server/life_test.exs`

## Task 11 — the `home` template and widened `type` enums

Spec §2.1/§8.5, and the `RegisterWorkspace`/`EditWorkspace` MCP tools' hardcoded enum lists
(`lib/server/mcp/tools/workspace.ex`), which must grow `"home"` too or the DB CHECK from task 1
is unreachable through those tools.

**Failing test first** — append to `test/server/workspaces_test.exs`:

```elixir
test "the home template registers a type: home workspace" do
  assert {:ok, ws} = Server.Workspaces.register_from("home", "home-template-#{System.unique_integer()}")
  assert ws.type == "home"
end
```

**`lib/server/workspaces.ex`** — in `@templates`:

```elixir
@templates %{
  "code" => %{type: "code", roster: ~w(surveyor builder reviewer planner)},
  "life" => %{type: "life", roster: ~w(assistant)},
  "home" => %{type: "home", roster: []},
  "blank" => %{type: "blank", roster: []}
}
```

And update its `@doc` line above `templates/0` to add `, home (no bench yet)`.

**`lib/server/mcp/tools/workspace.ex`** — in both `RegisterWorkspace` and `EditWorkspace`
schemas, change:

```elixir
field :type, :enum, values: ["code", "life", "blank"], default: "code"
```

to (drop the stray `default:` on `EditWorkspace`'s copy if it has none — check the file; only
`RegisterWorkspace`'s has a default):

```elixir
field :type, :enum, values: ["code", "life", "blank", "home"], default: "code"
```

**Verify**: `~/projects/menard/bin/menard run test --in server test/server/workspaces_test.exs`

## Task 12 — `/api/life` routes

Spec §4. `Server.MCP.OperatorAPI` (`lib/server/mcp/operator_api.ex`) is a hand-rolled dispatcher,
not Phoenix macros — new clauses alongside the existing `"schedules"` ones, same `with_workspace`/
`with_row`/`reply`/`body` helpers already in the file.

**Add to the route-table comment block** (top of the file, after the `schedules` block):

```
      GET    /api/life/:ws               Server.Life.status; {xp, level, next_level_at, streaks, due, quests, today}
      POST   /api/life/:ws/routines      {"title", "every", "window_minutes"?, "xp"?, "tile"?} → Life.create_routine; 201
      PATCH  /api/life/routines/:id      any of those, + "enabled" → Life.update_routine
      POST   /api/life/routines/:id/done Life.routine_done; {run, level_up}
      POST   /api/life/:ws/quests        {"title", "due_at"?, "xp"?} → Life.create_quest; 201
      POST   /api/life/quests/:id/done   Life.quest_done; {quest, level_up}
```

(`:ws` on the two GET/create-under-workspace routes because, unlike `schedules`, a life read/create
has no other way to name its workspace — `routines`/`quests` are workspace children, not
machine-global rows with their own id until created. This mirrors `/api/office/triage/:ws` etc.)

**Add route clauses** near the `"schedules"` clauses:

```elixir
defp route(conn, "GET", "life", [ws]), do: with_workspace(conn, ws, &json(conn, 200, Server.Life.status(&1.id)))

defp route(conn, "POST", "life", [ws, "routines"]), do: with_workspace(conn, ws, &new_routine(conn, &1))
defp route(conn, "POST", "life", [ws, "quests"]), do: with_workspace(conn, ws, &new_quest(conn, &1))

defp route(conn, "PATCH", "life", ["routines", id]), do: with_row(conn, Server.Routine, id, &edit_routine(conn, &1))
defp route(conn, "POST", "life", ["routines", id, "done"]), do: with_row(conn, Server.Routine, id, &done_routine(conn, &1))
defp route(conn, "POST", "life", ["quests", id, "done"]), do: with_row(conn, Server.Quest, id, &done_quest(conn, &1))
```

**Add handlers** near `new_schedule/1`/`edit_schedule/2`:

```elixir
defp new_routine(conn, ws) do
  {b, conn} = body(conn)
  reply(conn, Server.Life.create_routine(ws.id, routine_attrs(b)), &routine_row/1, 201)
end

defp edit_routine(conn, r) do
  {b, conn} = body(conn)
  reply(conn, Server.Life.update_routine(r, routine_attrs(b)), &routine_row/1)
end

defp done_routine(conn, r) do
  case Server.Life.routine_done(r.id) do
    {:ok, run, level_up} -> json(conn, 200, %{run: routine_run_row(run), level_up: level_up})
    {:error, reason} -> refused(conn, reason)
  end
end

defp new_quest(conn, ws) do
  {b, conn} = body(conn)
  reply(conn, Server.Life.create_quest(ws.id, quest_attrs(b)), &quest_row/1, 201)
end

defp done_quest(conn, q) do
  case Server.Life.quest_done(q.id) do
    {:ok, quest, level_up} -> json(conn, 200, %{quest: quest_row(quest), level_up: level_up})
    {:error, reason} -> refused(conn, reason)
  end
end

defp routine_attrs(b), do: for {k, v} <- b, k in ~w(title every window_minutes xp tile enabled), into: %{}, do: {String.to_atom(k), v}
defp quest_attrs(b), do: for {k, v} <- b, k in ~w(title due_at xp), into: %{}, do: {String.to_atom(k), v}

defp routine_row(r), do: %{id: r.id, title: r.title, every: r.every, window_minutes: r.window_minutes, xp: r.xp, tile: r.tile, enabled: r.enabled}
defp routine_run_row(rr), do: %{id: rr.id, routine_id: rr.routine_id, due_at: rr.due_at, done_at: rr.done_at, late: rr.late}
defp quest_row(q), do: %{id: q.id, title: q.title, due_at: q.due_at, xp: q.xp, done_at: q.done_at}
```

(`refused/2`'s existing clauses already cover `:not_found` → 404 and any other atom → 409 —
`:not_due`/`:already_done` fall through the catch-all `defp refused(conn, why), do: json(conn, 409,
%{error: inspect(why)})`, which is the right status: a conflict with current state, not a 404 or a
validation error.)

**Failing tests first** — new file `test/server/mcp/operator_api_life_test.exs`, matching whatever
test helper the existing `operator_api_test.exs` (or similarly named file — check for it) uses to
drive `OperatorAPI.call/2`/a test conn. Mirror its exact setup/helpers; sketch of the cases to
cover (fill in the real conn-building boilerplate from that file):

```elixir
test "GET /api/life/:ws returns the status body"
test "POST /api/life/:ws/routines creates a routine, 201"
test "PATCH /api/life/routines/:id edits it"
test "POST /api/life/routines/:id/done stamps it and returns {run, level_up}"
test "POST /api/life/routines/:id/done twice the same instance is a 409"
test "POST /api/life/:ws/quests creates a quest, 201"
test "POST /api/life/quests/:id/done stamps it"
```

**Verify**: `~/projects/menard/bin/menard run test --in server test/server/mcp/operator_api_life_test.exs`

## Task 13 — the six MCP tools

Spec §5. Six new modules, each `use Server.MCP.Tool`, same shape as
`Server.MCP.Tool.RegisterWorkspace` (`lib/server/mcp/tools/workspace.ex`) — thin callers of the
same `Server.Life` functions task 12's routes call. No change to any TS `adapters/` package
(spec's correction: tools aren't derived from routes, they're independent callers).

**`lib/server/mcp/tools/life.ex`** (new file):

```elixir
defmodule Server.MCP.Tool.LifeStatus do
  @moduledoc "The LIFE status for a workspace: xp, level, next_level_at, streaks, due, quests, today."
  use Server.MCP.Tool

  schema do
    field :workspace_id, :integer, required: true
  end

  @impl true
  def execute(params, frame), do: ok(frame, Server.Life.status(params.workspace_id))
end

defmodule Server.MCP.Tool.RoutineCreate do
  @moduledoc "A new ROUTINE: recurring, yours. `every` is a cron expression or @daily/@weekly."
  use Server.MCP.Tool

  schema do
    field :workspace_id, :integer, required: true
    field :title, :string, required: true
    field :every, :string, required: true
    field :window_minutes, :integer, default: 60
    field :xp, :integer, default: 10
    field :tile, :string
  end

  @impl true
  def execute(params, frame) do
    {workspace_id, attrs} = Map.pop!(params, :workspace_id)
    reply(frame, Server.Life.create_routine(workspace_id, attrs), fn r -> %{"routine_id" => r.id} end)
  end
end

defmodule Server.MCP.Tool.RoutineUpdate do
  @moduledoc "Edit a ROUTINE's mutable fields, by id."
  use Server.MCP.Tool

  alias Server.Repo
  alias Server.Routine

  schema do
    field :routine_id, :integer, required: true
    field :title, :string
    field :every, :string
    field :window_minutes, :integer
    field :xp, :integer
    field :tile, :string
    field :enabled, :boolean
  end

  @impl true
  def execute(params, frame) do
    {routine_id, attrs} = Map.pop!(params, :routine_id)

    case Repo.get(Routine, routine_id) do
      nil -> error(frame, "no such routine #{routine_id}")
      routine -> reply(frame, Server.Life.update_routine(routine, attrs), fn r -> %{"routine_id" => r.id} end)
    end
  end
end

defmodule Server.MCP.Tool.RoutineDone do
  @moduledoc "Stamp a ROUTINE done now — \"I brushed my teeth\". Returns level_up if it crossed a level."
  use Server.MCP.Tool

  schema do
    field :routine_id, :integer, required: true
  end

  @impl true
  def execute(params, frame) do
    case Server.Life.routine_done(params.routine_id) do
      {:ok, run, level_up} -> ok(frame, %{"run_id" => run.id, "level_up" => level_up})
      {:error, reason} -> error(frame, inspect(reason))
    end
  end
end

defmodule Server.MCP.Tool.QuestCreate do
  @moduledoc "A new QUEST: one-off, due optional — \"book the dentist\"."
  use Server.MCP.Tool

  schema do
    field :workspace_id, :integer, required: true
    field :title, :string, required: true
    field :due_at, :string
    field :xp, :integer, default: 10
  end

  @impl true
  def execute(params, frame) do
    {workspace_id, attrs} = Map.pop!(params, :workspace_id)
    reply(frame, Server.Life.create_quest(workspace_id, attrs), fn q -> %{"quest_id" => q.id} end)
  end
end

defmodule Server.MCP.Tool.QuestDone do
  @moduledoc "Stamp a QUEST done now. Returns level_up if it crossed a level."
  use Server.MCP.Tool

  schema do
    field :quest_id, :integer, required: true
  end

  @impl true
  def execute(params, frame) do
    case Server.Life.quest_done(params.quest_id) do
      {:ok, quest, level_up} -> ok(frame, %{"quest_id" => quest.id, "level_up" => level_up})
      {:error, reason} -> error(frame, inspect(reason))
    end
  end
end
```

(Check `Server.MCP.Tool`'s actual `reply/3`/`ok/2`/`error/2` helper names and arities against
another existing tool before trusting the names above literally — `workspace.ex`'s `reply/3`
closure shape was read directly for this plan, but confirm `error/2` exists the same way; if not,
match whatever that behaviour module actually exports.)

**`lib/server/mcp/endpoint.ex`** — add, near the other `component(...)` lines:

```elixir
component(Server.MCP.Tool.LifeStatus, name: "life_status")
component(Server.MCP.Tool.RoutineCreate, name: "routine_create")
component(Server.MCP.Tool.RoutineUpdate, name: "routine_update")
component(Server.MCP.Tool.RoutineDone, name: "routine_done")
component(Server.MCP.Tool.QuestCreate, name: "quest_create")
component(Server.MCP.Tool.QuestDone, name: "quest_done")
```

No dedicated ExUnit test required beyond compilation — tool execution is exercised through
`Server.Life`'s own tests (task 5-10); if the existing MCP tool test suite has a generic
"every registered tool's schema is well-formed" check, this task must pass it.

**Verify**: `~/projects/menard/bin/menard run check --in server` (compiles, warnings-as-errors,
and the full suite — the first point in the plan where every new module must link together).

## Task 14 — the office snapshot's `life` block

Spec §6. `Server.Office.status/0` (`lib/server/office.ex`), following the `triage` precedent
(`Map.new(ws_ids, &{&1, Room.triage(&1).count})`) exactly.

**Failing test first** — append to whatever `test/server/office_test.exs` already covers
`status/0`'s shape (check that file's existing style and reuse its fixtures):

```elixir
test "status/0 carries a life summary only for type: home workspaces" do
  {:ok, home} = Server.Workspaces.register(%{name: "office-life-#{System.unique_integer()}", type: "home"})
  {:ok, code} = Server.Workspaces.register(%{name: "office-code-#{System.unique_integer()}", type: "code"})

  status = Server.Office.status()

  assert Map.has_key?(status.life, home.id)
  assert status.life[home.id] |> Map.keys() |> Enum.sort() == [:due, :level, :xp]
  refute Map.has_key?(status.life, code.id)
end
```

**`lib/server/office.ex`** — in `status/0`'s map, add:

```elixir
life: Map.new(home_ws_ids(wss), &{&1, Server.Life.status(&1) |> Map.take([:level, :xp, :due])}),
```

and above the map, alongside `ws_ids`:

```elixir
defp home_ws_ids(wss), do: wss |> Enum.filter(&(&1.type == "home")) |> Enum.map(& &1.id)
```

(called as `home_ws_ids(wss)` inside `status/0`, where `wss` is already bound from
`Server.Workspaces.all()`).

**Verify**: `~/projects/menard/bin/menard run test --in server test/server/office_test.exs`

## Task 15 — `server.ex` exports, if the boundary compiler demands it

Spec §2's note. Only needed if `mix compile --warnings-as-errors` actually fails without it —
`Server.Schedules` is notably *not* in the current `exports:` list in `lib/server.ex`, so it's
possible the boundary doesn't gate `Server.MCP.OperatorAPI`'s calls into sibling `Server.*`
modules the way it gates calls from outside the `Server` app entirely. Don't pre-guess: run

```
mix compile --warnings-as-errors
```

after task 13. If it's clean, this task is a no-op — say so in the commit and skip it. If it
fails naming `Server.Life`, add `Life,` to the `exports:` list in `lib/server.ex` (alongside
`Workspaces`) and recompile.

**Verify**: `mix compile --warnings-as-errors` exits 0.

## Task 16 — the privacy README note

Spec §9/§10, pulled forward into this PR per §8.5. A short, factual note — not a new doc.

**`server/AGENTS.md`** (or wherever the server's own README-ish doc lives — check for a existing
"Still deferred"/privacy-adjacent section first, and add alongside it rather than inventing a new
heading) — one short paragraph:

```markdown
**The life side has no privacy boundary yet.** `routine`/`routine_run`/`quest` rows are plain
Postgres, readable by any coworker holding a `home`-type workspace's MCP tools — same trust
model as everything else on this box, named here before anyone runs a second `home` workspace
that isn't andrew's own.
```

**Verify**: none mechanical — a human-readable addition. Confirm placement reads naturally in
context before committing.

## After task 16

Run the gate once: `~/projects/menard/bin/menard run check --in server`. Green means every task's
test still holds together, not just in isolation. Then `check:names`'s existing scope (task 11's
`server.ex` export if task 15 added one, any new `mise.toml`/script references — there shouldn't
be any from this step) via `mise run check` at the repo root, per spec §8.5's "no addition, the
route-dispatch tests are the gate."
