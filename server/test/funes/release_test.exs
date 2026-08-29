defmodule Server.ReleaseTest do
  # The release-time migration path: a `mix release` has no `mix`, so booting the
  # service must bring an empty (or behind) schema fully up on its own. This proves
  # the invariant the always-up service depends on — a fresh boot ends fully
  # migrated, nothing pending — through the exact function the service's
  # ExecStartPre calls (`bin/funes eval 'Server.Release.migrate()'`).
  use ExUnit.Case, async: false

  alias Server.Doctor
  alias Server.Release

  test "migrate/0 applies every migration, leaving nothing pending" do
    assert :ok = Release.migrate()
    assert Doctor.pending() == []
  end

  test "migrate/0 is idempotent — a second call on an up-to-date schema is a no-op" do
    assert :ok = Release.migrate()
    assert :ok = Release.migrate()
    assert Doctor.pending() == []
  end
end
