defmodule Server.ModelCliTest do
  use ExUnit.Case, async: false

  alias Server.ModelCli

  setup do
    dir = Path.join(System.tmp_dir!(), "model-cli-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp cli(dir, body) do
    path = Path.join(dir, "cli")
    File.write!(path, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(path, 0o755)
    path
  end

  test "the prompt and the model reach the CLI as -p and --model", %{dir: dir} do
    assert {:ok, "-p hi --model m\n"} = ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, ~s(echo "$@")), "m"})
  end

  test "a CLI that reads stdin still answers — stdin is closed, not a pipe left open", %{dir: dir} do
    cmd = cli(dir, "cat >/dev/null; echo answered")
    assert {:ok, "answered\n"} = ModelCli.prompt("hi", :test_cmd, :test_model, {cmd, "m"})
  end

  test "a CLI that never answers is cut off at :model_cli_timeout_s", %{dir: dir} do
    Application.put_env(:server, :model_cli_timeout_s, 1)
    on_exit(fn -> Application.delete_env(:server, :model_cli_timeout_s) end)

    assert {:error, {:model_cli_timeout, 1}} = ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, "sleep 5"), "m"})
  end

  test "a missing CLI and a failing one are told apart", %{dir: dir} do
    assert {:error, {:model_cli_missing, _}} = ModelCli.prompt("hi", :test_cmd, :test_model, {"/nonexistent/cli", "m"})

    assert {:error, {:model_cli_exit, 3, "boom\n"}} =
             ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, "echo boom; exit 3"), "m"})
  end
end
