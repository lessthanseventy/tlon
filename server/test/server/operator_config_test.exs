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

  test "put_many writes several keys in one file write and keeps the rest", %{path: path} do
    File.write!(path, ~s({"max_leaves": 3, "pause_by": "auto:five_hour"}))
    :ok = OperatorConfig.put_many(%{"pause" => "pencils_down", "pause_by" => nil}, path)
    assert OperatorConfig.read(path) == %{"max_leaves" => 3, "pause" => "pencils_down", "pause_by" => nil}
  end

  test "knobs lists every runtime setting with its value, the default where the file is silent", %{path: path} do
    File.write!(path, ~s({"max_leaves": 3}))
    knobs = Map.new(OperatorConfig.knobs(path), &{&1.key, &1})

    assert %{value: 3, default: 6, type: "int"} = knobs["max_leaves"]
    assert %{value: true, type: "bool"} = knobs["banter"]
    assert %{value: nil, type: "int"} = knobs["auto_land_risk"]
    assert %{value: 90, type: "int", min: 1, max: 100} = knobs["auto_pause_at"]
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

  test "oneshot_model is a provider/model from the model choices, one default for every one-shot", %{path: path} do
    File.write!(path, "{}")
    assert OperatorConfig.oneshot_model(path) == "ollama-cloud/deepseek-v4.1-flash"

    :ok = OperatorConfig.put_settings(%{"oneshot_model" => "anthropic/claude-haiku-5-5"}, path)
    assert OperatorConfig.oneshot_model(path) == "anthropic/claude-haiku-5-5"

    assert {:error, "oneshot_model" <> _} = OperatorConfig.put_settings(%{"oneshot_model" => "nope/none"}, path)
    assert OperatorConfig.oneshot_model(path) == "anthropic/claude-haiku-5-5"

    File.write!(path, ~s({"oneshot_model": "nope/none"}))
    assert OperatorConfig.oneshot_model(path) == "ollama-cloud/deepseek-v4.1-flash"
  end

  test "Lifeline can never be set to take a held smoke for stuck: its floor is past the smoke's hold", %{path: path} do
    File.write!(path, "{}")
    hold_minutes = div(7200, 60)
    assert OperatorConfig.setting("lifeline_rescue_minutes", path) > hold_minutes
    assert {:error, _} = OperatorConfig.put_settings(%{"lifeline_rescue_minutes" => hold_minutes}, path)
  end

  test "boot_oban applies the boot knobs to Oban's config, leaving the rest as compiled", %{path: path} do
    File.write!(path, ~s({"intake_every_minutes": 5, "lifeline_rescue_minutes": 200}))

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
    assert {Oban.Plugins.Lifeline, rescue_after: to_timeout(minute: 200)} in booted[:plugins]
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

  test "operator is the configured handle" do
    assert OperatorConfig.operator() == Application.get_env(:server, :operator, "andrew")
  end
end

defmodule Server.OperatorConfigPathTest do
  # path/0 reads the Application env, then TLON_CONFIG, then the XDG default. Env is global, so this
  # module is not async; each test restores what it changed.
  use ExUnit.Case, async: false

  alias Server.OperatorConfig

  setup do
    prior_app = Application.get_env(:server, :operator_config_path)
    prior_env = System.get_env("TLON_CONFIG")
    prior_xdg = System.get_env("XDG_CONFIG_HOME")
    Application.delete_env(:server, :operator_config_path)
    System.put_env("XDG_CONFIG_HOME", "/xdg-home")

    on_exit(fn ->
      if prior_app, do: Application.put_env(:server, :operator_config_path, prior_app)
      if prior_env, do: System.put_env("TLON_CONFIG", prior_env), else: System.delete_env("TLON_CONFIG")
      if prior_xdg, do: System.put_env("XDG_CONFIG_HOME", prior_xdg), else: System.delete_env("XDG_CONFIG_HOME")
    end)

    :ok
  end

  test "TLON_CONFIG names the settings file ahead of the XDG default" do
    System.put_env("TLON_CONFIG", "/scratch/config.json")
    assert OperatorConfig.path() == "/scratch/config.json"
  end

  test "without TLON_CONFIG the file is the XDG default" do
    System.delete_env("TLON_CONFIG")
    assert OperatorConfig.path() == "/xdg-home/tlon/config.json"
  end

  test "the Application env still wins over TLON_CONFIG" do
    System.put_env("TLON_CONFIG", "/scratch/config.json")
    Application.put_env(:server, :operator_config_path, "/app/config.json")
    assert OperatorConfig.path() == "/app/config.json"
  end
end
