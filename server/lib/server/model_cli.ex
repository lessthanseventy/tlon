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
  # a one-off call is headless: nothing saved, nothing discovered, nothing to trust or approve —
  # a CLI that stopped to ask would only sit there until the timeout
  @headless %{
    "pi" => ~w(--no-session --no-extensions --no-approve),
    "claude" => ~w(--no-session-persistence --permission-mode dontAsk)
  }

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

  @doc "`prompt/5` with the command and model named outright, for a caller that picks them itself."
  def run(prompt, cmd, model, opts \\ []) do
    timeout = opts[:timeout_s] || Application.get_env(:server, :model_cli_timeout_s, 120)

    # System.cmd leaves stdin an open pipe, and `pi -p` reads it as the rest of the prompt — it
    # waits forever. The CLI gets /dev/null, and `timeout` bounds a call that hangs regardless.
    args =
      ["-c", ~s(exec timeout "$0" "$@" </dev/null), to_string(timeout), cmd, "-p", prompt, "--model", model] ++
        Map.get(@headless, Path.basename(cmd), [])

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
