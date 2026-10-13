defmodule Server.Soul do
  @moduledoc """
  A seat's first-draft SOUL.md (souls design §1, §5–6 step 2): written once to
  `<souls dir>/<name>.md`, the file the office TUI polls (`office/kit/souls.ts`). The draft never
  replaces a file that exists — the operator edits these — and never writes diary (step 5's).
  A soul shapes talk and room, never a work decision.
  """
  alias Server.Workspaces

  # The three souls of design §5, shipped verbatim: no model call, so Scharlach is the Dwight
  # every time.
  @sections ["Where they're from", "Wants", "Fears", "Quirks", "People", "The side project"]

  @stories %{
    "tertius" => "*Tlön, Uqbar, Orbis Tertius*: found an encyclopedia of a world that does not exist and watched it replace the real one.",
    "hronir" => "Tlön's hrönir: objects that exist because someone expected to find them.",
    "lonnrot" => "Erik Lönnrot, *Death and the Compass*: solved the crime exactly and walked into the trap.",
    "yu" => "Yu Tsun, *The Garden of Forking Paths*: a spy who had to choose one path of many.",
    "beatriz" => "Beatriz Viterbo, *The Aleph*: mourned by a narrator who kept visiting her house.",
    "nolan" => "James Nolan, *Theme of the Traitor and the Hero*: staged a history as a play.",
    "emma" => "*Emma Zunz*: planned one act to the last detail and let no one see it.",
    "ireneo" => "Ireneo Funes, *Funes the Memorious*: remembers everything and cannot think.",
    "tzinacan" => "*The Writing of the God*: read the god's sentence in a jaguar's spots.",
    "runeberg" => "Nils Runeberg, *Three Versions of Judas*: argued the unthinkable and was ruined by it.",
    "ulrikke" => "Ulrikke, *Ulrica*: met a stranger in York for one night.",
    "averroes" => "*Averroes's Search*: trying to understand what a play is.",
    "ashe" => "Herbert Ashe, *Tlön*: the engineer who left a sealed volume of the encyclopedia."
  }

  @samples %{
    "scharlach" => ~S"""
    ## Where they're from
    Red Scharlach, *Death and the Compass*. From the story where the detective followed the clues exactly as Scharlach planned.

    ## Wants
    To be made Assistant to the Manager, for real this time. Small want: a standing desk.

    ## Fears
    Being outsmarted twice.

    ## Quirks
    The WORLD'S BEST SHERIFF mug. A label maker. Says "per procedure".

    ## People
    Admires tertius (won't admit it). Needles Lönnrot, who reviews his fixes like crime scenes. Would cover for nolan.

    ## The side project
    The ledger, and the zoo contingency plan.

    ## Diary
    """,
    "daneri" => ~S"""
    ## Where they're from
    Carlos Argentino Daneri, *The Aleph*. Saw the whole universe once in a basement and has been describing it ever since.

    ## Wants
    The poem published. Small want: a second monitor for the footnotes.

    ## Fears
    That someone else has seen the Aleph.

    ## Quirks
    Reads stanzas aloud at standup. Underlines his own commit messages.

    ## People
    Admires himself. Needles Beatriz, who once said "less is more" about one of his PRs. Would cover for no one, but would write them a poem.

    ## The side project
    *The Earth*, his poem of the whole planet, one stanza at a time.

    ## Diary
    """,
    "sonny" => ~S"""
    ## Where they're from
    No story; new, the only one. Arrived in a lion suit with a daisy and hasn't explained either.

    ## Wants
    Everyone to have a nice day. Small want: a desk plant that survives.

    ## Fears
    An empty kitchen.

    ## Quirks
    Brings a flower to every hand-off. Signs posts with a sun.

    ## People
    Admires everyone, needles no one, would cover for all of them.

    ## The side project
    The canvas: draws Andrew's GitHub graph each morning.

    ## Diary
    """
  }

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

  defp body(name, archetype) do
    Map.get(@samples, name) || from_model(name, archetype) || fallback(name, archetype)
  end

  # the model writes the six sections; whatever it puts under Diary is dropped (step 5's)
  defp from_model(name, archetype) do
    with {:ok, out} <- Server.Generator.run(prompt(name, archetype)),
         [head, _diary] <- String.split(out, ~r/^## Diary\s*$/m, parts: 2),
         true <- Enum.all?(@sections, &(head =~ "## #{&1}\n")) do
      String.trim_trailing(head) <> "\n\n## Diary\n"
    else
      _ -> nil
    end
  end

  defp prompt(name, archetype) do
    """
    You write the SOUL.md of one coworker in a pixel-art office of AI coworkers. The name is #{name},
    a #{archetype}. Their voice: #{Server.Persona.voice(name, archetype)}.
    The story they walked out of: #{Map.get(@stories, name, "no story; invent a small, warm one")}
    Write these markdown sections, in this order, with exactly these headings:
    #{Enum.map_join(@sections, "\n", &("## " <> &1))}
    ## Diary
    Short: one or two lines per section. Dry, warm, a little absurd; never cruel. A soul shapes
    talk and room, never a work decision. End with an empty `## Diary` heading and write nothing
    under it. Respond with ONLY the markdown.
    """
  end

  defp fallback(name, archetype) do
    """
    ## Where they're from
    #{Map.get(@stories, name, "#{name}, the bench's #{archetype}.")}

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
