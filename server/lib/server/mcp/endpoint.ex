defmodule Server.MCP.Endpoint do
  @moduledoc """
  The sovereign channel (pi doc §2a): the server's MCP server. Every tool and resource
  is a thin caller of the contexts — never a second writer to the DB (§10) — and
  identity rides the CONNECTION: the bearer token (a stateless HMAC over its
  claims, `Server.MCP.Tokens`) resolves to a (thread, agent, session) binding on
  every request, so no tool takes a thread parameter. The protocol lifecycle —
  JSON-RPC, sessions, version negotiation, auth — is anubis', a library that
  tracks the MCP spec so this seam cannot drift from it under our hands.

  Served loopback-only by Bandit (`Server.Application`, opt-in via `:start_mcp`);
  being MCP, it serves ANY agent — pi today, another tomorrow.
  """
  use Anubis.Server,
    name: "tlon",
    version: "0.1.0",
    capabilities: [:tools, :resources],
    authorization: [
      authorization_servers: ["http://127.0.0.1"],
      resource: "http://127.0.0.1/tlon",
      validator: {Server.MCP.TokenValidator, []}
    ]

  alias Server.MCP.Tool.GetBrief

  component(Server.MCP.Tool.Register, name: "register")
  component(Server.MCP.Tool.PostMessage, name: "post_message")
  component(Server.MCP.Tool.BankFact, name: "bank_fact")
  component(Server.MCP.Tool.RaiseIssue, name: "raise_issue")
  component(Server.MCP.Tool.RecordDone, name: "record_done")
  component(Server.MCP.Tool.AddTodo, name: "add_todo")
  component(Server.MCP.Tool.CompleteTodo, name: "complete_todo")
  component(Server.MCP.Tool.RaiseQuestion, name: "raise_question")
  component(Server.MCP.Tool.ResolveQuestion, name: "resolve_question")
  component(Server.MCP.Tool.RecordCheck, name: "record_check")
  component(Server.MCP.Tool.RecheckFact, name: "recheck_fact")
  component(Server.MCP.Tool.TrackThread, name: "track_thread")
  component(Server.MCP.Tool.OpenThread, name: "open_thread")
  component(Server.MCP.Tool.CloseThread, name: "close_thread")
  component(Server.MCP.Tool.AssignLead, name: "assign_lead")
  component(Server.MCP.Tool.AdvanceStage, name: "advance_stage")
  component(Server.MCP.Tool.SubmitReview, name: "submit_review")
  component(Server.MCP.Tool.SwitchThread, name: "switch_thread")
  component(Server.MCP.Tool.ConsultPeer, name: "consult_peer")
  component(Server.MCP.Tool.StaffChild, name: "staff_child")
  component(Server.MCP.Tool.SpawnCrew, name: "spawn_crew")
  component(Server.MCP.Tool.KillCrew, name: "kill_crew")
  component(Server.MCP.Tool.PresenceThinking, name: "presence_thinking")
  component(Server.MCP.Tool.PresenceIdle, name: "presence_idle")
  component(Server.MCP.Tool.ProposeHabit, name: "propose_habit")
  # `get_dossier` is the canonical name (the pi adapter, the flake's directTools and the CLI call
  # it); `get_brief` is the name the console's harness catch-up prompt and profile allowlists use.
  component(GetBrief, name: "get_dossier")
  component(GetBrief, name: "get_brief")
  component(Server.MCP.Tool.GetFacts, name: "get_facts")
  component(Server.MCP.Tool.GetMessages, name: "get_messages")
  component(Server.MCP.Tool.SearchHistory, name: "search_history")
  component(Server.MCP.Tool.SearchFacts, name: "search_facts")
  component(Server.MCP.Tool.MachineOverview, name: "machine_overview")
  # The source verbs (docs/plans/2026-09-08-elixir-repo-tools-design.md): edits and introspection
  # over the thread's own worktree. A reviewer's profile excludes the edit verbs.
  component(Server.MCP.Tool.RenameIdentifier, name: "rename_identifier")
  component(Server.MCP.Tool.OutlineFile, name: "outline_file")
  component(Server.MCP.Tool.EditClause, name: "edit_clause")
  component(Server.MCP.Tool.RunVerb, name: "run_verb")
  component(Server.MCP.Tool.RegisterWorkspace, name: "register_workspace")
  component(Server.MCP.Tool.ListWorkspaces, name: "list_workspaces")
  component(Server.MCP.Tool.EditWorkspace, name: "edit_workspace")
  component(Server.MCP.Tool.RemoveWorkspace, name: "remove_workspace")
  # Container tier: projects, the lightweight ticket tracker, and notes.
  component(Server.MCP.Tool.RegisterProject, name: "register_project")
  component(Server.MCP.Tool.FileTicket, name: "file_ticket")
  component(Server.MCP.Tool.ListTickets, name: "list_tickets")
  component(Server.MCP.Tool.UpdateTicket, name: "update_ticket")
  component(Server.MCP.Tool.WriteNote, name: "write_note")
  component(Server.MCP.Tool.GetNotes, name: "get_notes")
  component(Server.MCP.Resource.Brief, name: "brief")
  component(Server.MCP.Resource.Constraints, name: "constraints")
  component(Server.MCP.Resource.Habits, name: "habits")
end
