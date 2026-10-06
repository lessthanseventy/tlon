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

  test "a service with no OLLAMA_API_KEY in its env hands the CLI the machine's agenix key", %{dir: dir} do
    File.mkdir_p!(Path.join(dir, "agenix"))
    File.write!(Path.join([dir, "agenix", "ollama-api-key"]), "k3y\n")
    {runtime, key} = {System.get_env("XDG_RUNTIME_DIR"), System.get_env("OLLAMA_API_KEY")}
    System.put_env("XDG_RUNTIME_DIR", dir)
    System.delete_env("OLLAMA_API_KEY")

    on_exit(fn ->
      if runtime, do: System.put_env("XDG_RUNTIME_DIR", runtime)
      if key, do: System.put_env("OLLAMA_API_KEY", key)
    end)

    assert {:ok, "k3y\n"} = ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, ~s(echo "$OLLAMA_API_KEY")), "m"})
    System.put_env("OLLAMA_API_KEY", "from-env")

    assert {:ok, "from-env\n"} =
             ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, ~s(echo "$OLLAMA_API_KEY")), "m"})
  end

  test "pi and claude run headless: no session saved, no extensions or trust to settle, nothing to ask",
       %{dir: dir} do
    for name <- ["pi", "claude"] do
      File.mkdir_p!(Path.join(dir, name))
      path = Path.join([dir, name, name])
      File.write!(path, ~s(#!/bin/sh\necho "$@"\n))
      File.chmod!(path, 0o755)
    end

    assert {:ok, "-p hi --model m --no-session --no-extensions --no-approve\n"} =
             ModelCli.prompt("hi", :test_cmd, :test_model, {Path.join([dir, "pi", "pi"]), "m"})

    assert {:ok, "-p hi --model m --no-session-persistence --permission-mode dontAsk\n"} =
             ModelCli.prompt("hi", :test_cmd, :test_model, {Path.join([dir, "claude", "claude"]), "m"})
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
