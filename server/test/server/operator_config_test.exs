defmodule Server.OperatorConfigTest do
  # The operator's runtime settings file: the office's banter switch, read live and written back
  # without losing the keys the operator wrote by hand.
  use ExUnit.Case, async: true

  alias Server.OperatorConfig

  setup do
    path = Path.join(System.tmp_dir!(), "tlon-config-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "banter is on unless the file turns it off", %{path: path} do
    assert OperatorConfig.banter?(path)
    File.write!(path, ~s({"banter": false}))
    refute OperatorConfig.banter?(path)
  end

  test "put writes one key and keeps the rest", %{path: path} do
    File.write!(path, ~s({"max_leaves": 3}))
    :ok = OperatorConfig.put("banter", false, path)
    assert OperatorConfig.read(path) == %{"max_leaves" => 3, "banter" => false}
    refute OperatorConfig.banter?(path)
  end

  test "knobs lists every runtime setting with its value, the default where the file is silent", %{path: path} do
    File.write!(path, ~s({"max_leaves": 3}))
    knobs = Map.new(OperatorConfig.knobs(path), &{&1.key, &1})

    assert %{value: 3, default: 6, type: "int"} = knobs["max_leaves"]
    assert %{value: true, type: "bool"} = knobs["banter"]
    assert %{value: nil, type: "int"} = knobs["auto_land_risk"]
    assert OperatorConfig.setting("continuation_turns", path) == 3
  end

  test "put_settings validates every key before writing any", %{path: path} do
    File.write!(path, ~s({"weather_location": "Denver"}))

    assert {:error, "max_leaves" <> _} = OperatorConfig.put_settings(%{"max_leaves" => 0, "banter" => false}, path)
    assert {:error, "no setting named" <> _} = OperatorConfig.put_settings(%{"nope" => 1}, path)
    assert {:error, _} = OperatorConfig.put_settings(%{"banter" => "loud"}, path)
    assert OperatorConfig.read(path) == %{"weather_location" => "Denver"}

    :ok = OperatorConfig.put_settings(%{"max_leaves" => 2, "auto_land_risk" => 3}, path)
    assert OperatorConfig.read(path) == %{"weather_location" => "Denver", "max_leaves" => 2, "auto_land_risk" => 3}

    :ok = OperatorConfig.put_settings(%{"auto_land_risk" => nil}, path)
    refute Map.has_key?(OperatorConfig.read(path), "auto_land_risk")
  end

  test "boot_oban applies the boot knobs to Oban's config, leaving the rest as compiled", %{path: path} do
    File.write!(path, ~s({"intake_every_minutes": 5, "lifeline_rescue_minutes": 60}))

    compiled = [
      queues: [default: 5],
      plugins: [
        {Oban.Plugins.Lifeline, rescue_after: to_timeout(minute: 30)},
        {Oban.Plugins.Cron,
         crontab: [
           {"* * * * *", Server.Jobs.Drain},
           {"*/30 * * * *", Server.Jobs.Maintain},
           {"*/15 * * * *", Server.Jobs.Intake}
         ]}
      ]
    ]

    booted = OperatorConfig.boot_oban(compiled, path)
    assert booted[:queues] == [default: 5]
    assert {Oban.Plugins.Lifeline, rescue_after: to_timeout(hour: 1)} in booted[:plugins]
    {_, cron} = List.keyfind(booted[:plugins], Oban.Plugins.Cron, 0)

    assert cron[:crontab] == [
             {"* * * * *", Server.Jobs.Drain},
             {"*/30 * * * *", Server.Jobs.Maintain},
             {"*/5 * * * *", Server.Jobs.Intake}
           ]

    assert OperatorConfig.boot_oban([testing: :manual], path) == [testing: :manual]
    assert Enum.find(OperatorConfig.knobs(path), &(&1.key == "intake_every_minutes")).boot
  end

  test "put makes the file, and its directory, when there is none", %{path: path} do
    nested = Path.join([Path.rootname(path), "tlon", "config.json"])
    on_exit(fn -> File.rm_rf(Path.rootname(path)) end)
    :ok = OperatorConfig.put("banter", true, nested)
    assert OperatorConfig.read(nested) == %{"banter" => true}
  end
end
