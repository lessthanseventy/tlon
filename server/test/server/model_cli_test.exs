defmodule Server.ModelCliTest do
  use ExUnit.Case, async: false

  alias Server.ModelCli

  setup do
    dir = Path.join(System.tmp_dir!(), "model-cli-#{System.pid()}-#{System.unique_integer([:positive])}")
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

  test "the prompt reaches the CLI on stdin, the model as --model", %{dir: dir} do
    assert {:ok, "-p --model m " <> rest} =
             ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, ~s{echo "$@ | $(cat)"}), "m"})

    assert rest =~ "| hi"
  end

  test "a prompt past exec's 128 KB argument limit (a grade's diff) reaches the CLI whole", %{dir: dir} do
    big = String.duplicate("x", 200_000)
    assert {:ok, "200000\n"} = ModelCli.prompt(big, :test_cmd, :test_model, {cli(dir, "wc -c | tr -d ' '"), "m"})
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

  test "a call on the Claude plan runs headless: no session saved, nothing to ask, no MCP servers or connectors, the operator's own login",
       %{dir: dir} do
    assert {:ok,
            ~s(anthropic -p --model haiku --no-session-persistence --permission-mode dontAsk --strict-mcp-config --mcp-config {"mcpServers":{}}\n)} =
             ModelCli.prompt(
               "hi",
               :test_cmd,
               :test_model,
               {cli(dir, ~s(echo "${ANTHROPIC_BASE_URL:-anthropic} $@")), "haiku"}
             )
  end

  test "a provider/model call goes to that provider's endpoint, bare — no tools, no project context — its effort kept",
       %{dir: dir} do
    key = System.get_env("OLLAMA_API_KEY")
    System.put_env("OLLAMA_API_KEY", "k")
    on_exit(fn -> if key, do: System.put_env("OLLAMA_API_KEY", key), else: System.delete_env("OLLAMA_API_KEY") end)

    assert {:ok, out} =
             ModelCli.prompt(
               "hi",
               :test_cmd,
               :test_model,
               {cli(dir, ~s(echo "$ANTHROPIC_BASE_URL $@")), "ollama-cloud/deepseek-v4-pro:high"}
             )

    assert out =~ "https://ollama.com -p --model deepseek-v4-pro "
    assert out =~ "--effort high"
    assert out =~ "--bare --tools  --system-prompt"
  end

  test "a model's own tag is not an effort", %{dir: dir} do
    assert {:ok, out} =
             ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, ~s(echo "$@")), "ollama/qwen3-coder:30b"})

    assert out =~ "--model qwen3-coder:30b"
    refute out =~ "--effort"
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

  test "a warning on stderr is not part of the answer, so a reply still parses", %{dir: dir} do
    warn = ~s(echo '"m" isn'"'"'t described by this version'"'"'s model catalog' >&2; echo ok)
    assert {:ok, "ok\n"} = ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, warn), "m"})
  end

  test "a failing CLI's stderr is what its error says", %{dir: dir} do
    assert {:error, {:model_cli_exit, 2, "nope\n"}} =
             ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, "echo nope >&2; exit 2"), "m"})
  end

  describe "a one-shot refused by its provider" do
    setup %{dir: dir} do
      Server.TestDB.clean!()
      {:ok, ws} = Server.Workspaces.register(%{name: "One-shot"})
      {:ok, seat} = Server.Workspaces.seat(ws.id, %{name: "glmer", archetype: "builder"})
      glm = %{"provider" => "ollama-cloud", "model" => "glm-5.2", "thinking" => "medium"}
      {:ok, _} = Server.Workspaces.set_policy(ws.id, seat.agent_id, %{model: glm})
      %{ws: ws, dir: dir}
    end

    @line "API Error: Request rejected (429) · you (x) have reached your session usage limit, upgrade for higher limits: https://ollama.com/upgrade"

    test "the usage-limit 429 on stderr raises the provider's quota item at once, in the workspaces seating it",
         %{dir: dir, ws: ws} do
      cli = cli(dir, "echo '#{@line}' >&2; exit 1")

      assert {:error, {:model_cli_exit, 1, _}} =
               ModelCli.prompt("hi", :test_cmd, :test_model, {cli, "ollama-cloud/glm-5.2"})

      assert [need] = Enum.filter(Server.Office.Needs.list(), &(&1.kind == "quota"))
      assert need.key == "quota:#{ws.id}:ollama-cloud" and need.text =~ @line
    end

    test "a catalog notice, another failure, or a Claude-plan call raises nothing", %{dir: dir} do
      notice = ~s(echo '"kimi-k3" isn'"'"'t described by this version'"'"'s model catalog' >&2; exit 1)
      assert {:error, _} = ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, notice), "ollama-cloud/kimi-k3"})

      assert {:error, _} =
               ModelCli.prompt(
                 "hi",
                 :test_cmd,
                 :test_model,
                 {cli(dir, "echo boom >&2; exit 1"), "ollama-cloud/glm-5.2"}
               )

      assert {:error, _} =
               ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, "echo '#{@line}' >&2; exit 1"), "haiku"})

      assert Enum.filter(Server.Office.Needs.list(), &(&1.kind == "quota")) == []
    end
  end

  test "a missing CLI and a failing one are told apart", %{dir: dir} do
    assert {:error, {:model_cli_missing, _}} = ModelCli.prompt("hi", :test_cmd, :test_model, {"/nonexistent/cli", "m"})

    assert {:error, {:model_cli_exit, 3, "boom\n"}} =
             ModelCli.prompt("hi", :test_cmd, :test_model, {cli(dir, "echo boom; exit 3"), "m"})
  end
end
