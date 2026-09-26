defmodule Mix.Tasks.Console.Seed do
  @shortdoc "Seed the dev DB with workspaces, projects and threads shaped like the live machine"
  @moduledoc """
  Populate the dev db with the live machine's shape — workspaces holding projects holding threads,
  some waiting on you — so the cockpit can be built and screenshotted against a full rail. Idempotent:
  re-running won't duplicate a workspace, project, thread or a thread's messages. Writes only through
  the server's public API (never raw rows) — the same path agents and the human use.

  `working` is live presence (a coworker actually thinking), so no seed can fake it honestly; start a
  coworker to see it. For a clean picture: `mise run console:reset:db && mise run console:seed`.
  """
  use Mix.Task
  use Boundary, classify_to: Console

  alias Console.Server.Channel
  alias Console.Server.Projects
  alias Console.Server.Workspaces

  @requirements ["app.config"]

  @workspaces [
    %{
      name: "Machine",
      roster: [%{"archetype" => "surveyor", "name" => "tertius"}, %{"archetype" => "builder", "name" => "hronir"}],
      projects: [
        %{
          name: "Tlön",
          repos: ["~/projects/tlon", "~/projects/menard"],
          threads: [
            %{
              title: "Rail → project tabs",
              prompt: "Allow mix ecto.reset on tlon_dev?",
              chat: [
                "the rail is a tree nobody reads — make it a flat list",
                "on it; top bar gets the workspace switcher first"
              ]
            },
            %{
              title: "Title threads at creation",
              chat: [
                "imported pi threads are titled by their first line",
                "a model pass at close, or at the third message?"
              ]
            },
            %{title: "menard hex publish", chat: ["docs are green; hex.pm wants a description under 300 chars"]}
          ]
        },
        %{
          name: "ficciones",
          repos: ["~/projects/ficciones"],
          threads: [
            %{
              title: "Bluetooth mouse drops after suspend",
              prompt: "Restart bluetooth.service?",
              chat: ["the MX drops every resume since the 7.2 kernel"]
            },
            %{
              title: "Hyprland 0.57 update",
              chat: ["the lua dispatch names changed again", "patched in the flake; home:switch is green"]
            }
          ]
        }
      ]
    },
    %{
      name: "Accessibility",
      roster: [%{"archetype" => "builder", "name" => "hronir"}],
      projects: [
        %{
          name: "excessibility",
          repos: ["~/projects/excessibility"],
          threads: [
            %{
              title: "phoenix_storybook source",
              chat: ["Excessibility.Source is the seam — a storybook source renders each story"]
            },
            %{
              title: "axe-core 5 upgrade",
              prompt: "Bump the vendored axe.min.js?",
              chat: ["axe 5 renames two rule ids we assert on"]
            }
          ]
        },
        %{
          name: "a11y-with-phoenix-guide",
          repos: ["~/projects/a11y-with-phoenix-guide"],
          threads: [
            %{
              title: "Chapter 4: live regions",
              chat: ["draft is up; the phx-update example needs a screen-reader recording"]
            }
          ]
        }
      ]
    },
    %{
      name: "Riverside",
      roster: [],
      projects: [
        %{
          name: "ex_riverside",
          repos: ["~/projects/ex_riverside"],
          threads: [%{title: "Webhook retries", chat: ["retries double-post when the upstream 502s mid-body"]}]
        }
      ]
    }
  ]

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:console)

    counts =
      for ws <- @workspaces do
        workspace = ensure_workspace(ws)

        for p <- ws.projects, t <- p.threads, reduce: 0 do
          n ->
            project = ensure_project(workspace, p)
            ensure_thread(workspace, project, t)
            n + 1
        end
      end

    Mix.shell().info("console: seeded #{length(@workspaces)} workspaces and #{Enum.sum(counts)} threads.")
  end

  defp ensure_workspace(%{name: name, roster: roster, projects: projects}) do
    with nil <- Workspaces.by_name(name) do
      repos = Enum.flat_map(projects, & &1.repos)

      {:ok, workspace} =
        Workspaces.register(%{name: name, type: "code", scope: "project", repos: repos, roster: roster})

      workspace
    end
  end

  defp ensure_project(workspace, %{name: name, repos: repos}) do
    with nil <- Projects.by_name(workspace.id, name) do
      entries = Enum.map(repos, &%{"name" => Path.basename(&1), "path" => &1})
      {:ok, project} = Projects.register(%{workspace_id: workspace.id, name: name, repos: entries})
      project
    end
  end

  defp ensure_thread(workspace, project, %{title: title} = t) do
    existing = Enum.find(Channel.open_threads(), &(&1.title == title and &1.workspace_id == workspace.id))
    if is_nil(existing), do: open_seeded(workspace, project, t)
  end

  defp open_seeded(workspace, project, %{title: title} = t) do
    {:ok, thread} = Channel.open_thread(%{title: title, workspace_id: workspace.id, project_id: project.id})
    Enum.each(Enum.with_index(t.chat), fn {body, i} -> post(thread, speaker(i), body) end)
    if t[:prompt], do: prompt(thread, t.prompt)
  end

  # the seeded chat alternates: the operator, then the agent
  defp speaker(i) when rem(i, 2) == 0, do: "andrew"
  defp speaker(_i), do: "hronir"

  defp post(thread, author, body), do: Channel.post(%{thread_id: thread.id, author: author, body: body})

  # The shape Server.Attention writes when a coworker's pane stops on a dialog — the rail's `!`.
  defp prompt(thread, summary) do
    options = [%{"key" => "y", "label" => "Yes"}, %{"key" => "n", "label" => "No"}]

    Channel.post(%{
      thread_id: thread.id,
      author: "tlon",
      kind: "prompt",
      body: "⚑ waiting on you — #{summary}\n(y) Yes · (n) No",
      payload: %{"harness" => "claude", "summary" => summary, "options" => options}
    })
  end
end
