defmodule Server.Hardening.CrashPathsTest do
  # Faults the always-up service must answer as values, never raise through: a raise in a shared read
  # (the office snapshot, the inbox) fails every caller, and one in a GenServer crash-loops the supervisor.
  use ExUnit.Case, async: false

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "tmux missing from the service's PATH is a value, not a raise" do
    enoent = fn _cmd, _args, _opts -> raise ErlangError, original: :enoent end
    assert {out, 127} = Server.Tmux.run(1, ["list-windows"], runner: enoent)
    assert out =~ "not found"
  end

  test "a schedule or routine on @reboot is refused — it has no next time, and dispatch would raise on it" do
    {:ok, ws} = Server.Workspaces.create(%{name: "Reboot"})

    assert {:error, cs} =
             Server.Schedules.create(%{
               workspace_id: ws.id,
               kind: "script",
               title: "boot",
               body: "true",
               cron: "@reboot"
             })

    assert {"needs a next time" <> _, _} = cs.errors[:cron]
    refute Server.Routine.create_changeset(%{workspace_id: ws.id, title: "boot", every: "@reboot"}).valid?
  end

  test "a delivery that raises doesn't take the switchboard runner down" do
    assert {:noreply, %{}} = Server.Switchboard.Runner.handle_info({:message_posted, :not_a_message}, %{})
  end
end
