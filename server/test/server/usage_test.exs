defmodule Server.UsageTest do
  # The Claude plan's limits as the last session to report them saw them: the office's meter.
  use ExUnit.Case, async: false

  alias Server.Usage

  setup do
    Server.TestDB.clean!()
    path = Path.join(System.tmp_dir!(), "usage-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    prior = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      File.rm(path)

      if prior,
        do: Application.put_env(:server, :operator_config_path, prior),
        else: Application.delete_env(:server, :operator_config_path)
    end)

    {:ok, ws} = Server.Workspaces.register(%{name: "Office"})
    {:ok, lobby} = Server.Channel.open_thread(%{title: "lobby", workspace_id: ws.id, scope: "machine"})
    Usage.clear()
    %{lobby: lobby}
  end

  test "a report at the threshold pauses the office and says why on the root thread", %{lobby: lobby} do
    :ok = Usage.report(%{"five_hour" => %{"percent" => 92, "resets_at" => "2026-10-27T14:00:00Z"}})
    assert Server.Pause.state() == :pencils_down
    assert Enum.any?(Server.Channel.thread_messages(lobby), &(&1.body =~ "5h at 92%"))
  end

  test "nothing reported yet is nil, never a made-up zero" do
    assert Usage.claude() == nil
  end

  test "a report is kept with when it came; the newest wins, a window it leaves out is kept from before" do
    :ok =
      Usage.report(%{
        "five_hour" => %{"percent" => 34, "resets_at" => "2026-10-13T19:00:00Z"},
        "seven_day" => %{"percent" => 44, "resets_at" => nil}
      })

    :ok = Usage.report(%{"five_hour" => %{"percent" => 35.5, "resets_at" => "2026-10-13T19:00:00Z"}})

    assert %{
             five_hour: %{percent: 35.5, resets_at: "2026-10-13T19:00:00Z"},
             seven_day: %{percent: 44, resets_at: nil},
             at: %DateTime{}
           } =
             Usage.claude()
  end

  test "a report that isn't the plan's windows is refused and changes nothing" do
    assert {:error, _} = Usage.report(%{"five_hour" => %{"percent" => "lots"}})
    assert {:error, _} = Usage.report(%{})
    assert Usage.claude() == nil
  end
end
