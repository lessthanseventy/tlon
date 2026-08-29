defmodule Server.ModelCli do
  @moduledoc """
  One headless model-CLI invocation shape for every adapter (eval judge, memory extractor,
  whatever's next): command + model come from config keys (vendor is never design — funes
  AGENTS.md), errors normalize to typed tuples, and a fix to the invocation (timeouts,
  flags) lands once.
  """

  @doc "Run `prompt` through the configured CLI. `{:ok, stdout}` or `{:error, typed}`."
  def prompt(prompt, cmd_key, model_key, {default_cmd, default_model} \\ {"claude", "haiku"}) do
    cmd = Application.get_env(:server, cmd_key, default_cmd)
    model = Application.get_env(:server, model_key, default_model)

    case System.cmd(cmd, ["-p", prompt, "--model", model], stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, {:model_cli_exit, code, String.slice(out, 0, 200)}}
    end
  rescue
    e in ErlangError -> {:error, {:model_cli_missing, Exception.message(e)}}
  end
end
