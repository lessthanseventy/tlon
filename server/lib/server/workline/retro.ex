defmodule Server.Workline.Retro do
  @moduledoc """
  A landed workline that was sent back to build on its way: what it learned, kept. Its bounce reasons
  (the merge queue's and the reviewers' send-backs) go to a small model, which writes at most two
  lessons a coworker building here should carry next time — concrete (a command, a file, a check),
  never generic advice — or none. Each is banked as a `learned`, `derived` fact on the thread, as the
  sheriff's postmortems are: every coworker's dossier reads it, the operator sees it in memory and can
  forget it. No card: a lesson is reversible, and the operator has enough to decide.
  """
  import Ecto.Query

  alias Server.Event
  alias Server.Message
  alias Server.Repo
  alias Server.Thread

  @lessons 2

  @doc """
  Bank `thread`'s lessons. `opts[:ask]`, a `fn prompt -> {:ok, text} | {:error, why} end`, swaps the
  model (tests). `{:ok, facts}`; `{:ok, []}` when it was never sent back or nothing generalized.
  """
  def run(%Thread{} = thread, opts \\ []) do
    ask = Keyword.get(opts, :ask, &ask/1)

    case material(thread) do
      [] ->
        {:ok, []}

      why ->
        with {:ok, text} <- ask.(prompt(thread, why)) do
          {:ok, text |> lessons() |> Enum.flat_map(&bank(thread, &1))}
        end
    end
  end

  @doc "Why `thread` went back to build: the merge queue's bounces and the send-backs, oldest first, at most five."
  def material(%Thread{id: id}) do
    bounced =
      Repo.all(
        from e in Event,
          where:
            e.thread_id == ^id and e.kind == "stage_advanced" and
              fragment("(?::jsonb ->> 'to') = 'build' and (?::jsonb ->> 'bounced') is not null", e.detail, e.detail),
          order_by: [asc: e.id],
          select: fragment("?::jsonb ->> 'bounced'", e.detail)
      )

    sent_back =
      Repo.all(
        from m in Message,
          where: m.thread_id == ^id and m.author == "tlon" and like(m.body, "↩ back to build — sent back by %"),
          order_by: [asc: m.id],
          select: m.body
      )

    (bounced ++ sent_back) |> Enum.map(&String.slice(&1, 0, 400)) |> Enum.take(5)
  end

  @doc "The lessons in a model's answer: its `- ` lines, at most #{@lessons}, none of them a placeholder."
  def lessons(text) do
    text
    |> String.split("\n")
    |> Enum.flat_map(&(Regex.run(~r/^\s*-\s+(.+?)\s*$/, &1, capture: :all_but_first) || []))
    |> Enum.filter(&(String.length(&1) in 20..300))
    |> Enum.take(@lessons)
  end

  defp prompt(thread, why) do
    """
    Workline ##{thread.id} ("#{thread.title}") landed, but was sent back to build on the way. Why:
    #{Enum.map_join(why, "\n", &("- " <> &1))}

    Write at most #{@lessons} lessons a coworker building in this repo should carry next time, each one
    line starting "- ": concrete (a command to run first, a file to check, a test to write), drawn from
    the reasons above, never generic advice. If nothing generalizes beyond this one change, write NONE.
    """
  end

  defp ask(prompt), do: Server.ModelCli.prompt(prompt, :generator_cmd, :generator_model, {"claude", "haiku"})

  defp bank(thread, lesson) do
    case Server.Dossier.bank_fact(%{
           thread_id: thread.id,
           kind: "learned",
           provenance: "derived",
           text: "retro of ##{thread.id}: #{lesson}"
         }) do
      {:ok, fact} -> [fact]
      {:error, _} -> []
    end
  end
end
