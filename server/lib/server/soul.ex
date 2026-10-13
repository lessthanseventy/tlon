defmodule Server.Soul do
  @moduledoc """
  A seat's first-draft SOUL.md (souls design §1, §5–6 step 2): written once to
  `<souls dir>/<name>.md`, the file the office TUI polls (`office/kit/souls.ts`). The draft never
  replaces a file that exists — the operator edits these — and never writes diary (step 5's).
  A soul shapes talk and room, never a work decision.
  """
  alias Server.Workspaces

  @doc "The souls dir: `config :server, :souls_dir`, else `TLON_SOULS` (as the TUI), else `~/.config/tlon/souls`."
  @spec dir() :: String.t()
  def dir do
    Application.get_env(:server, :souls_dir) || System.get_env("TLON_SOULS") ||
      Path.join(System.get_env("XDG_CONFIG_HOME") || Path.expand("~/.config"), "tlon/souls")
  end

  @doc "Write the seat's soul if it has none; an existing file is left alone, edited or not."
  @spec draft(integer(), String.t()) :: {:ok, :written | :exists} | {:error, :no_seat | :bad_name}
  def draft(workspace_id, name) do
    with :ok <- check_name(name),
         %{archetype: archetype} <- Enum.find(Workspaces.bench_all(workspace_id), &(&1.name == name)) || {:error, :no_seat} do
      path = Path.join(dir(), name <> ".md")

      if File.exists?(path) do
        {:ok, :exists}
      else
        File.mkdir_p!(dir())

        case File.write(path, body(name, archetype), [:exclusive]) do
          :ok -> {:ok, :written}
          {:error, :eexist} -> {:ok, :exists}
        end
      end
    end
  end

  defp check_name(name), do: if(name =~ ~r/\A[a-z0-9][a-z0-9_-]*\z/, do: :ok, else: {:error, :bad_name})

  defp body(name, archetype), do: fallback(name, archetype)

  defp fallback(name, archetype) do
    """
    ## Where they're from
    #{name}, the bench's #{archetype}.

    ## Wants
    To do the work well. A quiet desk.

    ## Fears
    A task nobody explained.

    ## Quirks
    A chipped mug. Says "Right then."

    ## People
    Admires whoever reviews them kindly.

    ## The side project
    A notebook of things noticed.

    ## Diary
    """
  end
end
