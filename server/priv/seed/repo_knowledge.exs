# Base self-knowledge for Tlön — what any box running it should already know about the product.
#
# This is the reset-safe SEED: `Server.Seed` banks these facts on boot (via `Server.Bootstrap`) and on
# demand (`mix server.seed`), idempotently — each fact is keyed by its stable `intent`, so re-running
# never duplicates. A box's own workspaces and facts about its operator belong in the MACHINE seed
# (`~/.config/tlon/seed.exs`), never here: this repo is public and machine-agnostic.
#
# A fact is a durable claim: `kind` + `provenance` (stated = the owner said it; derived = we produced
# it). `constraint`/`stated` facts are the ALWAYS-LOADED pinned set — every thread sees them.

%{
  facts: [
    %{
      intent: "seed:tlon-what",
      kind: "constraint",
      provenance: "stated",
      text:
        "Tlön (the name is from Borges) is an agent-orchestration product: an always-up server (threads, " <>
          "facts, worklines, staffing), a terminal cockpit over it, and adapters that make pi and Claude Code " <>
          "citizens of it. Its repo is tlon; the machine that runs it wires it in from outside."
    },
    %{
      intent: "seed:module-layout",
      kind: "constraint",
      provenance: "stated",
      text:
        "The tlon repo: server/ (OTP app :server, Server.* — the store, MCP, switchboard, staffing, web UI), " <>
          "console/ (Console.* — the TTY cockpit; it calls only what Server exports, enforced by :boundary) and " <>
          "adapters/ (TypeScript: the pi extension, the Claude Code adapter, lsp, consult). funes and aleph are " <>
          "legacy names that survive only in prose and in the node name funes@."
    },
    %{
      intent: "seed:coordination-model",
      kind: "decision",
      provenance: "stated",
      text:
        "Coordination model: you always talk to a MANAGER, never a doer. Three tiers — Orchestrator " <>
          "(tertius, one, board-level, a command line that shows receipts) → Lead (a per-thread manager who " <>
          "delegates, never builds) → doers (crew on a thread, surfacing only on escalation). Automatic in the " <>
          "middle; the human is at the ends (approve-before-build, approve-merge) and on escalations."
    },
    %{
      intent: "seed:container-hierarchy",
      kind: "constraint",
      provenance: "stated",
      text:
        "Container hierarchy is Workspace ▸ Project ▸ Thread. A Workspace is a context with its own bench of " <>
          "coworkers and its own tmux server; a Project is a named effort over one or more repos; a Thread is a " <>
          "unit of work with a lead, in a project. Each workspace has one standing thread, its lobby, where the " <>
          "centre coworker sits. A Ticket is a lightweight workspace tracker that promotes into a thread; a Note " <>
          "is freeform scratch."
    },
    %{
      intent: "seed:substrate",
      kind: "constraint",
      provenance: "stated",
      text:
        "Substrate: tmux is the runtime (where live terminals run), the server is the knowledge — orthogonal. " <>
          "Coworkers run on their workspace's tmux server (socket console-workspace-<id>, session w<id>), so they " <>
          "survive the cockpit restarting. God-view is a server query across all workspaces, never a tmux attach."
    },
    %{
      intent: "seed:runtime-services",
      kind: "constraint",
      provenance: "stated",
      text:
        "Runtime: the server runs as a systemd --user service (tlon.service, node funes@127.0.0.1) — MCP on " <>
          "127.0.0.1:4040, the web UI on :4042, Oban for scheduled work. The cockpit (`mise run console:run`) is " <>
          "an :erpc client of that node, one brain; `console:run:local` embeds a server on the dev db instead. " <>
          "`mise run server:restart` rebuilds the release and restarts the service."
    },
    %{
      intent: "seed:persistence",
      kind: "constraint",
      provenance: "stated",
      text:
        "The store is Postgres over the local socket: `tlon` (the service), `tlon_dev` (dev shells and " <>
          "console:run:local), `tlon_test` (the suite). TLON_DATABASE or TLON_DATABASE_URL override."
    },
    %{
      intent: "seed:knowledge-model",
      kind: "constraint",
      provenance: "stated",
      text:
        "Knowledge model: a Fact is a durable claim with a kind and a provenance (stated = the owner said " <>
          "it verbatim; derived = we produced it). Recall is a forget-at-recall engine — semantic (embeddings) " <>
          "blended with keyword, bounded by a token budget, dropping low-signal/old facts from CONTEXT but never " <>
          "off disk. constraint/stated facts are always-loaded (pinned); the rest are thread-scoped and forgettable."
    },
    %{
      intent: "seed:toolchain",
      kind: "constraint",
      provenance: "stated",
      text:
        "Toolchain: run Elixir through mise (OTP 28). Every command in the loop is a mise task (tasks/*.toml, " <>
          "`mise tasks` lists them) — the human and every agent drive the same ones."
    },
    %{
      intent: "seed:verification-gates",
      kind: "constraint",
      provenance: "stated",
      text:
        "Verification: `mise run check` is the gate — the names check, the server, console and adapter checks, " <>
          "and the task manual. Precommit compiles with --warnings-as-errors, and the console may call only " <>
          "exported Server modules (the :boundary compiler enforces it)."
    },
    %{
      intent: "seed:coworker-lifecycle",
      kind: "decision",
      provenance: "stated",
      text:
        "Coworker lifecycle: the service's staffing pass (each minute) keeps every benched workspace's centre " <>
          "and tail seats running; a thread's lead comes online when the operator posts to it. A WARM lead (a live " <>
          "session inside the ~1h warmth window) is woken; a COLD one gets a FRESH session seeded from the " <>
          "thread's brief, never a /resume of a huge transcript."
    },
    %{
      intent: "seed:bootstrap-knowledge-loop",
      kind: "constraint",
      provenance: "stated",
      text:
        "Wipe-proof knowledge: this seed file holds the product's, the machine seed (~/.config/tlon/seed.exs, " <>
          "written by the machine) holds the box's workspaces and its operator's facts, and Server.Seed applies " <>
          "both on every boot. A genuinely useful session learning is PROMOTED (`mix server.promote_fact`) rather " <>
          "than left to die on the next wipe."
    }
  ],
  # Projects live in the machine seed and the store, not here.
  projects: []
}
