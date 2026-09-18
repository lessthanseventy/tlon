defmodule Server.MCP.Tool.RunPlaybook do
  @moduledoc """
  Run a named playbook: its steps and success criteria come back as your procedure, and the
  thread records that you started it. FACTS are what is true; a playbook is HOW — follow the
  steps, prove the success criteria with record_check.
  """
  use Server.MCP.Tool

  alias Server.Channel
  alias Server.MCP
  alias Server.Playbooks

  schema do
    field :name, :string, required: true, description: "The playbook's name (list_playbooks)"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    case Playbooks.get_by_name(params[:name]) do
      nil ->
        fail(frame, "no playbook named #{inspect(params[:name])} — list_playbooks shows what exists")

      playbook ->
        Channel.post(%{
          thread_id: identity.thread_id,
          author: identity.agent,
          body: "▶ playbook #{playbook.name} — #{playbook.summary}"
        })

        ok(frame, MCP.Brief.playbook(playbook))
    end
  end
end

defmodule Server.MCP.Tool.ListPlaybooks do
  @moduledoc "Every playbook by name, with its one-line summary."
  use Server.MCP.Tool

  alias Server.MCP
  alias Server.Playbooks

  schema do
  end

  @impl true
  def execute(_params, frame) do
    ok(frame, Enum.map(Playbooks.list(), &Map.take(MCP.Brief.playbook(&1), ["name", "summary", "source_thread_id"])))
  end
end

defmodule Server.MCP.Tool.PromotePlaybook do
  @moduledoc """
  Turn THIS thread's solved work into a playbook other coworkers inherit (a compound skill):
  by default the steps are the thread's DONE todos in order and the success criteria its passed
  CHECKS; pass `steps`/`success` to write them yourself. Name it as a slug.
  """
  use Server.MCP.Tool

  alias Server.MCP
  alias Server.Playbooks
  alias Server.Repo
  alias Server.Thread

  schema do
    field :name, :string, required: true, description: "a-z 0-9 dashes, up to 60"
    field :summary, :string, description: "One line: when to reach for this"
    field :steps, :string, description: "Markdown steps; default = this thread's done todos"
    field :success, :string, description: "What done looks like; default = this thread's passed checks"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    thread = Repo.get!(Thread, identity.thread_id)

    thread
    |> Playbooks.promote(Map.put(Map.new(params), :author, identity.agent))
    |> case do
      {:error, :nothing_to_promote} -> fail(frame, "nothing to promote: no done todos on this thread and no steps given")
      other -> reply(frame, other, &MCP.Brief.playbook/1)
    end
  end
end
