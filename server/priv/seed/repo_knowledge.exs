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
    }
  ],
  # No seeded projects: ficciones is the monorepo (nix/home-manager + the Tlön app), and every
  # workspace gets a `general` project from bootstrap. The side efforts that used to live here as
  # ficciones projects — excessibility, ex_riverside, ex_cortex — are SEPARATE client WORKSPACES
  # (2026-08-31, Andrew), not projects under ficciones.
  projects: []
}
