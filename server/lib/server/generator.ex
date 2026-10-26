defmodule Server.Generator do
  @moduledoc """
  The one door to the toy's cheap model calls (`Server.Persona`, `Server.ToyPool`): `run/1` asks
  `Server.ModelCli` (`config :server, generator_cmd:, generator_model:`, default Claude Code on
  the operator's `oneshot_model`) only while banter is on and fewer than
  `:generator_daily_cap` (default 50) calls were made today. Every call counts, a failed one too, and
  the count is the db's, so a restart does not reset it.
  """
  alias Server.Repo

  @cap 50

  @spec run(String.t()) :: {:ok, String.t()} | {:error, :off | :capped | term()}
  def run(prompt) do
    cond do
      not Server.OperatorConfig.banter?() ->
        {:error, :off}

      not take_slot() ->
        {:error, :capped}

      true ->
        Server.ModelCli.prompt(
          prompt,
          :generator_cmd,
          :generator_model,
          {"claude", Server.OperatorConfig.oneshot_model()}
        )
    end
  end

  # one atomic upsert: the row only moves while it is under the cap
  defp take_slot do
    cap = Application.get_env(:server, :generator_daily_cap, @cap)

    %{num_rows: n} =
      Repo.query!(
        """
        INSERT INTO generator_call (day, calls) SELECT $1, 1 WHERE $2 > 0
        ON CONFLICT (day) DO UPDATE SET calls = generator_call.calls + 1 WHERE generator_call.calls < $2
        """,
        [Date.utc_today(), cap]
      )

    n == 1
  end
end
