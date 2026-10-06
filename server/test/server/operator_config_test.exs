defmodule Server.OperatorConfigTest do
  # The operator's runtime settings file: the office's banter switch, read live and written back
  # without losing the keys the operator wrote by hand.
  use ExUnit.Case, async: true

  alias Server.OperatorConfig

  setup do
    path = Path.join(System.tmp_dir!(), "tlon-config-#{System.unique_integer([:positive])}.json")
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

  test "put makes the file, and its directory, when there is none", %{path: path} do
    nested = Path.join([Path.rootname(path), "tlon", "config.json"])
    on_exit(fn -> File.rm_rf(Path.rootname(path)) end)
    :ok = OperatorConfig.put("banter", true, nested)
    assert OperatorConfig.read(nested) == %{"banter" => true}
  end
end
