defmodule Server.ModelCli do
  @moduledoc """
  One headless model-CLI invocation shape for every adapter (eval judge, memory extractor,
  whatever's next): command + model come from config keys (vendor is never design — server
  AGENTS.md), errors normalize to typed tuples, and a fix to the invocation (timeouts,
  flags) lands once.

  A key the CLI needs comes from the env or, where the env has none (the always-up service's
  unit carries no secrets), the machine's agenix file `$XDG_RUNTIME_DIR/agenix/<name>` — read at
  call time, handed to the CLI alone, never stored.
  """

  @keys %{"OLLAMA_API_KEY" => "ollama-api-key"}
  # a one-off call is headless: nothing saved, nothing to trust or approve — a CLI that stopped to
  # ask would only sit there until the timeout
  @headless ~w(--no-session-persistence --permission-mode dontAsk)
  @efforts ~w(low medium high xhigh max)
  # Off the Claude plan a one-off is a bare completion: no tools, no project context, the system
  # prompt alone — 79 tokens in, where Claude Code's own prompt is ~20k. `--bare` skips the Claude
  # login, so a call on the plan keeps it.
  @bare ["--bare", "--tools", "", "--system-prompt", "Answer the request exactly as asked."]

  @doc """
  Run `prompt` through the configured CLI with stdin closed, cut off after `opts[:timeout_s]`, else
  `:model_cli_timeout_s` (120). `{:ok, stdout}`, or `{:error, {:model_cli_timeout, s} |
  {:model_cli_missing, msg} | {:model_cli_exit, code, msg}}`.
  """
  def prompt(prompt, cmd_key, model_key, {default_cmd, default_model} \\ {"claude", "haiku"}, opts \\ []) do
    run(
      prompt,
      Application.get_env(:server, cmd_key, default_cmd),
      Application.get_env(:server, model_key, default_model),
      opts
    )
  end

  @doc """
  `prompt/5` with the command and model named outright, for a caller that picks them itself. A
  `provider/model` model (`ollama-cloud/deepseek-v4.1-flash`) runs through `gateway.sh` on that
  provider's endpoint; a bare one (`haiku`) on the operator's own Claude login.
  """
  def run(prompt, cmd, model, opts \\ []) do
    timeout = opts[:timeout_s] || Application.get_env(:server, :model_cli_timeout_s, 120)

    {provider, model} =
      case String.split(model, "/", parts: 2) do
        [p, m] -> {p, m}
        [m] -> {"anthropic", m}
      end

    # `model:high` is a thinking level; any other suffix is the model's own tag (`qwen3-coder:30b`)
    {model, effort} =
      case String.split(model, ":") do
        [m, e] when e in @efforts -> {m, ["--effort", e]}
        _ -> {model, []}
      end

    flags = if provider == "anthropic", do: @headless ++ effort, else: @headless ++ effort ++ @bare

    # System.cmd leaves stdin an open pipe, and a CLI may read it as the rest of the prompt — it
    # waits forever. The CLI gets /dev/null, and `timeout` bounds a call that hangs regardless.
    args =
      ["-c", ~s(exec timeout "$0" "$@" </dev/null), to_string(timeout), Server.Harness.ClaudeCode.gateway(), provider] ++
        [cmd, "-p", prompt, "--model", model] ++ flags

    case System.cmd("sh", args, stderr_to_stdout: true, env: keys()) do
      {out, 0} -> {:ok, out}
      {_out, 124} -> {:error, {:model_cli_timeout, timeout}}
      {out, code} when code in [126, 127] -> {:error, {:model_cli_missing, String.slice(out, 0, 200)}}
      {out, code} -> {:error, {:model_cli_exit, code, String.slice(out, 0, 200)}}
    end
  rescue
    e in ErlangError -> {:error, {:model_cli_missing, Exception.message(e)}}
  end

  # each key the env lacks, from its agenix file when that is there
  defp keys do
    dir = System.get_env("XDG_RUNTIME_DIR")

    for {var, name} <- @keys,
        System.get_env(var) in [nil, ""],
        dir,
        {:ok, v} <- [File.read(Path.join([dir, "agenix", name]))],
        v = String.trim(v),
        v != "",
        do: {var, v}
  end
end
