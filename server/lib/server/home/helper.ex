defmodule Server.Home.Helper do
  @moduledoc """
  The two small things the home asks a model for when it organizes: the next step of a project once
  one is done, and a two-minute start for a to-do that has sat. Each is one call, answered in one
  line. They go where the reader's calls go (`Server.ModelCli.prompt` with `:home_reader_cmd` and
  `:home_reader_model`, Haiku on the operator's Claude login, no tools): what a person wrote for
  themselves stays with the provider they already use. `:home_helper` names another asker, a
  function from the prompt to `{:ok, reply}` or `{:error, why}`.
  """

  alias Server.Jot

  require Logger

  @doc """
  The next step of `project` after the steps `finished`, from the operator's `notes`: `{:ok, step}`,
  `:error` when the model gave none or says the project is finished.
  """
  @spec next_step(Jot.t(), [String.t()], [String.t()]) :: {:ok, String.t()} | :error
  def next_step(%Jot{text: text}, finished, notes) do
    text
    |> next_prompt(finished, notes)
    |> ask()
    |> case do
      {:ok, step} -> {:ok, step}
      _none_or_error -> :error
    end
  end

  @doc """
  A two-minute start on the to-do `jot`, from the operator's `notes`: `{:ok, start}`, `:none` when
  the model had no start for it (`DONE` or nothing), `:error` when it did not answer.
  """
  @spec start(Jot.t(), [String.t()]) :: {:ok, String.t()} | :none | :error
  def start(%Jot{text: text}, notes), do: text |> start_prompt(notes) |> ask()

  @doc "The one line a model's `reply` holds, bullets and quotes off: `{:ok, line}`, `:error` when it is empty or `DONE`."
  @spec line(String.t()) :: {:ok, String.t()} | :error
  def line(reply) do
    line =
      reply
      |> String.split("\n", trim: true)
      |> Enum.map(&(&1 |> String.trim() |> String.trim_leading("-") |> String.trim_leading("*") |> String.trim()))
      |> Enum.find("", &(&1 != ""))
      |> String.trim("\"")
      |> String.slice(0, 140)

    if String.upcase(line) in ["", "DONE"], do: :error, else: {:ok, line}
  end

  defp ask(prompt) do
    asker = Application.get_env(:server, :home_helper, &model/1)

    case asker.(prompt) do
      {:ok, reply} ->
        with :error <- line(reply), do: :none

      {:error, why} ->
        Logger.warning("home helper: no answer: #{inspect(why)}")
        :error
    end
  end

  defp model(prompt) do
    Server.ModelCli.prompt(prompt, :home_reader_cmd, :home_reader_model, {"claude", "haiku"},
      timeout_s: 60,
      tools: "",
      settings: "user"
    )
  end

  defp next_prompt(project, finished, notes) do
    """
    You help a person with a project, one small step at a time. Say the single next step to take on it.
    One short line, in their own words, starting with a verb: something they could start today.
    Answer only DONE when the steps already finished leave nothing more to do.

    PROJECT: #{project}
    STEPS ALREADY DONE:
    #{list(finished)}
    THEIR NOTES:
    #{list(notes)}
    """
  end

  defp start_prompt(todo, notes) do
    """
    A person has had this on their to-do list for a week without starting it. Suggest a two-minute
    start on it: the smallest first move, so small it is hard to say no to. One short line, starting
    with a verb, no preamble.

    TO DO: #{todo}
    THEIR NOTES:
    #{list(notes)}
    """
  end

  defp list([]), do: "(none)"
  defp list(items), do: Enum.map_join(items, "\n", &"- #{&1}")
end
