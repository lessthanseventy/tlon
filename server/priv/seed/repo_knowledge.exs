# Base self-knowledge + baseline projects for Tlön (the ficciones monorepo).
#
# This is the reset-safe SEED: `Server.Seed` banks these facts and ensures these projects on boot
# (via `Server.Bootstrap`) and on demand (`mix server.seed`), idempotently — each fact is keyed by
# its stable `intent`, each project by (workspace, name), so re-running never duplicates. Edit this
# file to change what a freshly-reset funes already knows about itself.
#
# A fact is a durable claim: `kind` + `provenance` (stated = the owner said it; derived = we produced
# it). `constraint`/`stated` facts are the ALWAYS-LOADED pinned set — every thread sees them — which
# is why the repo's self-knowledge lives there.

%{
  facts: [
    %{
      intent: "seed:tlon-what",
      kind: "constraint",
      provenance: "stated",
      text:
        "Tlön (the name is from Borges) is this system: an agent-orchestration cockpit backed by a " <>
          "knowledge substrate. The monorepo is 'ficciones', at ~/projects/ficciones."
    },
    %{
      intent: "seed:module-layout",
      kind: "constraint",
      provenance: "stated",
      text:
        "Module layout: modules/server is funes — the knowledge + coordination brain (Elixir, code " <>
          "namespace Server.*, directory funes/); modules/console is aleph — the terminal cockpit (namespace " <>
          "Console.*, directory aleph/); modules/adapters holds the pi/manos harness adapters. Naming layers: " <>
          "the PRODUCT is Tlön, the OTP apps are server/console/adapters, and funes/aleph survive only as legacy " <>
          "directory names and prose."
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
        "Container hierarchy is Workspace ▸ Project ▸ Thread. A Workspace is a context (work/home/client) " <>
          "and IS a tmux session; a Project is a named effort spanning 1+ repos, grouped within the session; a " <>
          "Thread is a unit of work with a lead. A Ticket is a first-class, lightweight, workspace-scoped tracker " <>
          "(no ceremony) that PROMOTES into a thread when work starts; a Note is funes-native freeform scratch."
    },
    %{
      intent: "seed:substrate",
      kind: "constraint",
      provenance: "stated",
      text:
        "Substrate: tmux = the runtime (where live terminals run), funes = knowledge — orthogonal. A " <>
          "workspace IS a tmux session (console-workspace-<id>), so coworkers survive the cockpit restarting. " <>
          "God-view is a funes query across ALL workspaces, never a tmux attach."
    },
    %{
      intent: "seed:runtime-services",
      kind: "constraint",
      provenance: "stated",
      text:
        "Runtime: the server runs as a systemd --user service (tlon.service) on port 4040; the console " <>
          "cockpit runs on 4041. `mise run console:run` launches the cockpit; `mise run console:reload` hot-reloads " <>
          "render/keymap/panel edits into the running cockpit without a restart."
    },
    %{
      intent: "seed:persistence",
      kind: "constraint",
      provenance: "stated",
      text:
        "Persistence is SQLite via Server.Repo; the path comes from the TLON_DB env var (else " <>
          "~/.local/share/funes/wb.db). The dev scratch DB the cockpit reads is modules/server/.dev/tlon.db."
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
        "Toolchain: run Elixir through mise (OTP 28, not bare OTP 27). The machine is configured by a Nix " <>
          "flake + home-manager — `mise run home:switch` is the machine gate. Use pacman's nix, NOT Determinate " <>
          "(it segfaults on this box)."
    },
    %{
      intent: "seed:verification-gates",
      kind: "constraint",
      provenance: "stated",
      text:
        "Verification: module unit suites are NOT 'every gate' — run flake:check / home:switch before " <>
          "claiming ficciones work is green, or flag it unverified. Precommit compiles with " <>
          "--warnings-as-errors; the console may only call EXPORTED Server modules (the :boundary compiler " <>
          "enforces this — use the Server facade, never Server.Repo/Server.MCP.Tool from console)."
    },
    # --- 2026-09-01 direction (Andrew). These supersede the two-brain framing in seed:runtime-services
    #     and seed:persistence as the TARGET; keep those as the current state until WS3 lands. ---
    %{
      intent: "seed:one-brain-direction",
      kind: "decision",
      provenance: "stated",
      text:
        "Architecture target (2026-09-01): converge on ONE always-up server as the single source of truth " <>
          "— it owns the DB, MCP, and the future web UI (Phoenix) + Oban jobs. The cockpit becomes an RPC " <>
          "client of it (distributed-Erlang :erpc into the server node), NOT an embedder — retiring today's " <>
          "two brains (embedded :4041 on .dev/tlon.db vs systemd :4040 on wb.db). .dev DBs become test-only. " <>
          "SQLite → Postgres is likely once Oban/web-UI land; build the client boundary first, migrate the store later."
    },
    %{
      intent: "seed:coworker-lifecycle",
      kind: "decision",
      provenance: "stated",
      text:
        "Coworker lifecycle (2026-09-01): a coworker comes online ON-DEMAND when the operator posts to its " <>
          "thread — never an eager spawn of the whole roster. A WARM lead (a live session inside the ~1h warmth " <>
          "window) is woken (cheap resume, cache hot). A COLD or offline lead gets a FRESH session seeded from " <>
          "Board.brief (dossier catch-up), NEVER a /resume of a huge transcript — re-ingesting a stale context " <>
          "burns a 5-hour window. Switchboard.has_live_session? must treat a cold session as absent, or it strands."
    },
    %{
      intent: "seed:bootstrap-knowledge-loop",
      kind: "constraint",
      provenance: "stated",
      text:
        "This seed file (priv/seed/repo_knowledge.exs) IS Tlön's wipe-proof brain: Server.Seed re-applies it " <>
          "idempotently on every boot, so a DB wipe restores all of it. The intent is to bootstrap a fresh world " <>
          "with as much accumulated knowledge as possible — so genuinely useful learnings should be PROMOTED from " <>
          "session-banked facts into this file (keyed by a stable seed:* intent) rather than left to die on the next wipe."
    },
    %{
      intent: "seed:fix-or-file",
      kind: "constraint",
      provenance: "stated",
      text:
        "Never just note a problem. Every fault you hit gets one fate in the same session: fixed now (reproduced " <>
          "first by a test that goes red, then its own small commit), or filed — a Tlön ticket when it is small and " <>
          "later, a new Tlön thread on its project when it needs a conversation. A workaround is not a fix: when the " <>
          "code fights you, fix the code. Leave everywhere better than you found it. A report says what was fixed and " <>
          "which ticket or thread each deferred thing went to."
    }
  ],
  # Projects live in the store, not here: they are the operator's organisation of his repos (one
  # workspace; a project spans repos; the workspace names its default), edited as data.
  projects: []
}
