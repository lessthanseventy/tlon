defmodule Server.Profile do
  @moduledoc """
  A **coworker profile** — the full pi configuration for one space's machine coworker. A space
  names a profile; the server materialises it into a `PI_CODING_AGENT_DIR` (`Server.Profiles`) and
  launches the coworker with it. Profiles differ on the four dimensions a coworker actually varies
  on (design: `docs/plans/2026-08-17-pi-coworker-profiles-design.md`):

    * **tool / MCP surface** — `mcp` (`:base` inherit, `:none` self-contained, or an explicit
      `%{server => config}`), `drop_extensions` (which base pi extensions to omit), and
      `add_extensions` (extensions to add ON TOP, by absolute path — a coworker-specific extension,
      or one the flake hasn't registered into the base yet, so it loads at the coworker's next
      spawn without a `home:switch`).
    * **model + thinking** — `model` (`%{provider, model, thinking}`, or `nil` to inherit the base
      defaults).
    * **system prompt / persona** — `system_prompt` (materialised to a file, passed as
      `--append-system-prompt`).
    * **sandbox** — `sandbox` (a pi-sandbox `sandbox.json` map, or `nil` for unconfined). Scoped to
      the profile because pi-sandbox reads `sandbox.json` from `PI_CODING_AGENT_DIR`.

  `workspace_id` is which workspace this instance belongs to. It rides on the profile so
  `config_dir/1` can key the materialised dir by it and `Server.Policy` can differ per workspace —
  the same coworker name may be trusted differently in two of them.

  A profile is a small DIFF from the base `~/.pi/agent` config, not a full re-declaration — the base
  (extensions, skills, model catalog, auth) stays the single source of truth; the profile drops,
  replaces, and overlays.
  """
  @enforce_keys [:name]
  defstruct name: nil,
            archetype: nil,
            workspace_id: nil,
            harness: :pi,
            drop_extensions: [],
            add_extensions: [],
            mcp: :base,
            model: nil,
            system_prompt: nil,
            sandbox: nil,
            permissions: nil

  @type t :: %__MODULE__{
          name: String.t(),
          archetype: atom(),
          workspace_id: integer() | nil,
          harness: :pi | :claude_code,
          drop_extensions: [String.t()],
          add_extensions: [String.t()],
          mcp: :base | :none | map(),
          model: %{provider: String.t(), model: String.t(), thinking: String.t()} | nil,
          system_prompt: String.t() | nil,
          sandbox: map() | nil,
          permissions: map() | nil
        }
end

defmodule Server.Profiles do
  @moduledoc """
  The coworker-profile registry + materialiser. `fetch/1` looks a profile up by name; `render/3`
  is the pure seam (profile + base config → the files a config dir needs); `materialise!/1` is the
  IO wrapper that writes `~/.pi/profiles/<name>/` before a coworker spawns.

  Materialised layout (`PI_CODING_AGENT_DIR`):

      ~/.pi/profiles/<name>/
        settings.json     profile-specific — base settings with extensions dropped + model overridden
        mcp.json          profile-specific — the profile's MCP servers (`{}` = self-contained)
        sandbox.json      profile-specific — pi-sandbox allowlist (only if profile.sandbox)
        extensions/pi-permission-system/config.json
                          profile-specific — permission policy + yoloMode (only if profile.permissions)
        system_prompt.md  profile-specific — the persona (only if profile.system_prompt)
        tmux.conf         profile-specific — the persistence-free config the workspace's tmux
                          server boots from when this profile opens it (`Server.Tmux.socket/1`)
        auth.json      ↳ symlink to ~/.pi/agent/auth.json       (shared credentials)
        models.json    ↳ symlink to ~/.pi/agent/models.json     (shared model catalog)
        models-store.json ↳ symlink                             (shared)

        keybindings.json ↳ symlink                              (shared keymap — Ctrl+P/N nav)
        sessions/         its own — each coworker resumes its own thread (reload --continue)

  Idempotent + self-healing: re-materialised on every spawn, so editing a profile + respawning the
  coworker is the whole loop — no `home:switch`.

  ## The `tertius` coworker

  One coworker profile: `tertius`, the Tlön center — the Orbis Tertius meta agent
  (`tertius`), on the root machine thread. Design:
  `docs/plans/2026-08-19-orbis-tertius-meta-thread-design.md`.

  - **Machine-scope tlon citizen.** Its MCP (`@tertius_mcp`) binds every token to scope
    `machine` (via `tlon-cli.sh bearer`), so its posts/facts/dones stay on machine threads, off
    project threads (DB scope CHECK). `directTools` are the record/read verbs + `machine_overview`
    (the cross-leaf read); `excludeTools` cuts `register` and `consult_peer` (the orchestrator keeps
    `open_thread`/`close_thread`), and under Claude Code the same list rides as deny rules
    (`Server.Harness.ClaudeCode`).
  - **Driver.** Sonnet, so at home it runs on the Claude Code harness like every other coworker; a
    workspace policy `model` is how it goes back to pi.
  - **Sandboxed + yolo permissions.** `@tlon_sandbox` + `@tlon_permissions`: `yoloMode` auto-approves
    asks so an autonomous coworker never stalls, but yolo is deny-PRESERVING, so the
    catastrophic-command + secret-path floor still holds.
  """
  alias Server.OperatorConfig
  alias Server.Profile

  # Single-user machine — the repo the coworker writes in (matches flake.nix's `repo`). Used for the
  # Tlön sandbox's write allowlist.
  @repo "/home/andrew/projects/ficciones"

  # Every coworker runs on its workspace's PRIVATE tmux server (`Server.Tmux.socket/1`), booted from
  # the persistence-free tmux.conf below — never the user's default server, whose resurrect+continuum
  # would resurrect a torn-down coworker with stale identity/env. The interactive bits of the
  # machine tmux config (mouse, extended keys, vi copy-mode) minus every persistence plugin, plus
  # chrome-off options.
  @coworker_tmux_conf """
  # Generated by Server.Profiles — the per-coworker tmux server config (persistence-free).
  # A coworker comes up FRESH on every rebuild; the persistence plugins stay on the user's own tmux.
  set -s escape-time 10
  set -s extended-keys on
  set -s extended-keys-format csi-u
  set -as terminal-features 'xterm*:extkeys'
  set -s default-terminal tmux-256color
  set -g history-limit 50000
  set -g mouse on
  set -g base-index 1
  set -g pane-base-index 1
  set -g mode-keys vi
  set -g status off
  set -g 'status-format[0]' ''
  set -g pane-border-status off
  set -g mode-style 'bg=#3b4261,fg=#c0caf5'
  """

  # The Tlön coworker's sandbox (pi-sandbox `sandbox.json`). Permissive enough that the adapters tooling
  # keeps working under bubblewrap — the footgun class this session kept hitting:
  #   * allowAllUnixSockets — the lsp shim binds/connects adapters-lspd.sock; reload/tmux use sockets too
  #   * allowWrite the repo + /tmp + the socket dir + caches — the daemon writes the socket file, Expert
  #     writes its .expert index, edits land in the repo
  #   * allowedDomains — the hosts this repo's bash tasks reach (mirrors the machine sandbox allowlist)
  # See [[pi-sandbox-adapters-allowlist]]. NOT model API calls (pi's own process, not bash).
  #
  # bash runs under `bwrap --unshare-net`, so `127.0.0.1` inside a bash call is the coworker's OWN
  # empty netns, NOT the host's. Tlön's server is at `TLON_MCP_URL` = http://127.0.0.1:4041/mcp, so
  # `curl`ing it, `ss -tlnp`, and `mise run server:doctor|logs` ALWAYS fail here regardless of whether
  # server is up — `allowLocalBinding` only permits binding within that netns, and the socat proxy that
  # carries external traffic refuses loopback targets with a 403. There is no bash route, by design.
  # The @tlon_mcp tools are unaffected: pi opens that connection from its own process, outside
  # bubblewrap (same reason model API calls work). This matters more for Tlön than for the
  # interactive agent — it runs autonomously, so a bash probe returning 000 with nobody to correct it
  # is how a coworker talks itself into "server is down" and stops posting. Use the server tools; a
  # bash probe cannot answer the question.
  @tlon_sandbox %{
    "enabled" => true,
    "network" => %{
      "allowLocalBinding" => true,
      "allowAllUnixSockets" => true,
      # Derived from real Claude + pi session history (not guesswork): the dev-infra hosts this
      # machine's agents actually reach. An allowlist, NOT "*", stays the network fence for the
      # cheap-model coworker; grep the transcripts + extend here when a genuinely new infra host
      # shows up. Keep in sync with the flake's piPermissionSeed twin. See [[pi-sandbox-allowlist]].
      "allowedDomains" => [
        # source control + package registries
        "github.com",
        "*.github.com",
        "*.githubusercontent.com",
        "hex.pm",
        "*.hex.pm",
        "hexdocs.pm",
        "*.hexdocs.pm",
        "registry.npmjs.org",
        "www.npmjs.com",
        "*.npmjs.com",
        "crates.io",
        "static.crates.io",
        "index.crates.io",
        # toolchains + system package infra
        "*.jdx.dev",
        "sh.rustup.rs",
        "static.rust-lang.org",
        "cache.nixos.org",
        "channels.nixos.org",
        "nixos.org",
        # AI / agent infra
        "anthropic.com",
        "*.anthropic.com",
        "claude.com",
        "*.claude.com",
        "claude.ai",
        "ollama.com",
        "*.ollama.com",
        "registry.ollama.ai",
        "pi.dev",
        "modelcontextprotocol.io",
        "*.huggingface.co",
        # language + framework + tool docs
        "elixirforum.com",
        "www.phoenixframework.org",
        "expert-lsp.org",
        "www.typescriptlang.org",
        "react.dev",
        "pnpm.io",
        "playwright.dev",
        "ghostty.org",
        "agent-browser.dev",
        # docs / badges / assets / a11y
        "img.shields.io",
        "deepwiki.com",
        "www.w3.org",
        "dequeuniversity.com",
        "fonts.googleapis.com",
        "fonts.gstatic.com",
        # notifications
        "ntfy.sh",
        "herdr.dev",
        # andrew's own app (Phoenix LiveView)
        "myelin.us",
        "www.myelin.us"
      ]
    },
    "filesystem" => %{
      # Writes: the repo (edits), tlon's own checkout, /tmp + the socket dir (adapters-lspd),
      # caches. Never the nix store.
      "allowWrite" => [
        @repo,
        Path.expand("../../..", __DIR__),
        "/tmp",
        "$XDG_RUNTIME_DIR",
        "~/.pi",
        "~/.cache",
        "~/.local"
      ],
      # Reads (prompt-by-default otherwise): the repo and tlon's checkout, plus /nix/store +
      # ~/.nix-profile so pi reading its OWN install/docs/extensions — and any flake-managed
      # binary's files — never triggers a useless prompt (the store is immutable +
      # workspace-readable). Config/cache dirs round it out.
      "allowRead" => [
        @repo,
        Path.expand("../../..", __DIR__),
        "/nix/store",
        "~/.nix-profile",
        "~/.config",
        "~/.local",
        "~/.pi",
        "~/.cache"
      ],
      "denyWrite" => [".env", ".env.*", "*.pem", "*.key"]
    }
  }

  # The Tlön coworker's pi-permission-system policy (`extensions/pi-permission-system/config.json`).
  # permission-system reads its "global" config from `PI_CODING_AGENT_DIR` and FAIL-CLOSES to
  # "ask everything" when the file is absent — the same reason sandbox.json is per-profile — so the
  # coworker needs its OWN copy; the flake seeds only `~/.pi/agent`, the interactive agent's dir.
  #
  # This is the per-coworker knob: the interactive agent (flake seed) keeps `ask` for the rare
  # sudo/ambiguous call because a HUMAN is there to answer. Tlön runs AUTONOMOUSLY, so an `ask`
  # would just hang it — `yoloMode: true` auto-approves asks instead (no prompts, no stalls). yolo
  # is deny-PRESERVING, so the fence still holds: `sudo *` and the secret paths are `deny` (not
  # `ask`), so even under yolo the coworker cannot sudo unattended or touch credentials. Everything
  # else inside the sandbox's write allowlist just runs. See [[pi-permission-system-per-coworker]].
  @tlon_permissions %{
    "yoloMode" => true,
    "permissionReviewLog" => true,
    "permission" => %{
      "*" => "allow",
      # bash: routine runs; sudo + the catastrophic-and-never-legitimate commands are DENY (terminal,
      # so they hold even under yolo — deny is the one thing yolo can't re-permit). This deterministic
      # floor is intentionally NARROW: it is the last line, not the whole defense. The nuanced middle
      # (novel/ambiguous bash) is the adapters bash-judge authorizer-link's job. See [[pi-bash-judge]].
      "bash" => %{
        "*" => "allow",
        "sudo *" => "deny",
        "rm -rf /" => "deny",
        "rm -rf /*" => "deny",
        "rm -rf --no-preserve-root*" => "deny",
        "mkfs*" => "deny",
        "dd of=/dev/*" => "deny",
        "dd if=* of=/dev/*" => "deny",
        ":(){*" => "deny",
        "chmod -R 777 /*" => "deny",
        "chown -R * /" => "deny",
        "curl * | sh" => "deny",
        "curl * | bash" => "deny",
        "wget * | sh" => "deny",
        "wget * | bash" => "deny"
      },
      "external_directory" => "allow",
      "path" => %{
        "*" => "allow",
        "*.env" => "deny",
        "*.env.*" => "deny",
        "*.env.example" => "allow",
        "*.key" => "deny",
        "*.pem" => "deny",
        "~/.aws/*" => "deny",
        "~/.ssh/*" => "deny",
        "~/.pi/agent/auth.json" => "deny"
      }
    }
  }

  # The reviewer's permission policy — @tlon_permissions with the WRITE FENCE added: the built-in
  # file-writers (`write`, `edit`) and the obvious bash-write forms are denied, so a reviewer
  # STRUCTURALLY cannot land a change (its only path is to escalate). Reads/greps/git-read fall
  # through the "*" => "allow" fallback; yoloMode keeps those from stalling on an ask. The
  # catastrophic deny-floor rides along from @tlon_permissions unchanged. See the crew contract §A.
  #
  # pi-permission-system per-tool surfaces: top-level keys are surface names; `write`/`edit` are the
  # only built-in file WRITERS (reads are read/grep/find/ls), and a per-tool deny needs no path glob.
  # Bash writes are token-gated, so we deny the common redirect/in-place forms — the airtight fence is
  # the tool deny; the bash patterns are belt-and-suspenders for the MVP (the model-judge for the
  # ambiguous middle is phase-2).
  @reviewer_permissions put_in(
                          @tlon_permissions,
                          ["permission"],
                          Map.merge(@tlon_permissions["permission"], %{
                            "write" => "deny",
                            "edit" => "deny",
                            "bash" =>
                              Map.merge(@tlon_permissions["permission"]["bash"], %{
                                "* > *" => "deny",
                                "* >> *" => "deny",
                                "sed -i*" => "deny",
                                "tee *" => "deny",
                                "dd *" => "deny"
                              })
                          })
                        )

  # The dense statusline (adapters/footer) — its OWN package, not adapters/pi, so dropping the server
  # adapter doesn't take the footer with it. Added explicitly so Tlön shows it at the next coworker
  # spawn even before the flake registers it into the base config (which needs a home:switch).
  @footer_extension Path.expand("../../../adapters/footer/src/footer.ts", __DIR__)

  # The machine-scope tlon surface (see § "The tertius coworker" in the moduledoc for why the tools
  # are cut this way). Base tool set; `@tertius_mcp` adds the cross-leaf read on top.
  @tlon_mcp %{
    "tlon" => %{
      "url" => "${TLON_MCP_URL}",
      "headers" => %{"Authorization" => "!#{Path.expand("../../../scripts/tlon-cli.sh", __DIR__)} bearer"},
      "directTools" => [
        "post_message",
        "bank_fact",
        "raise_issue",
        "record_done",
        "record_check",
        "get_brief",
        "propose_habit"
      ],
      "excludeTools" =>
        ["register", "consult_peer", "open_thread", "close_thread"] ++
          ~w(release_status propose_release set_urgency submit_qa)
    }
  }

  # A reviewer reads and never edits: the source EDIT verbs are cut from its surface (the
  # introspection ones — outline_file — stay). Repo tools design, 2026-09-08.
  @reviewer_mcp update_in(@tlon_mcp, ["tlon", "excludeTools"], &(&1 ++ ["rename_identifier", "edit_clause"]))

  # tertius's surface is the ORCHESTRATOR toolset (Slice 4D): the base machine-citizen tools PLUS the
  # cross-thread read `machine_overview` AND the staffing verbs a manager routes with — `staff_child`
  # (open a child thread + assign + brief), `assign_lead` (staff/reassign an existing thread), and
  # `open_thread`/`close_thread` (un-excluded here — the orchestrator opens untracked work and closes
  # finished children, which fires report-up). Workers stay self-contained; the vantage routes.
  @tertius_mcp @tlon_mcp
               |> update_in(
                 ["tlon", "directTools"],
                 &(&1 ++ ["machine_overview", "staff_child", "assign_lead", "open_thread", "close_thread"])
               )
               |> update_in(["tlon", "excludeTools"], &(&1 -- ["open_thread", "close_thread"]))

  # The sheriff routes red the way tertius routes work, so it is the one worker that reaches across:
  # the cross-thread read and `consult_peer` (to hand a lead its fix) — never the staffing verbs; it
  # tells leads, it does not reassign them.
  @sheriff_mcp @tlon_mcp
               |> update_in(["tlon", "directTools"], &(&1 ++ ["machine_overview", "consult_peer"]))
               |> update_in(["tlon", "excludeTools"], &(&1 -- ["consult_peer"]))

  # The PM owns what ships and in what order — the release and the backlog's urgency — and reads
  # across the work to judge it; it neither edits code nor staffs.
  @pm_release_tools ~w(release_status propose_release set_urgency)
  @pm_mcp @tlon_mcp
          |> update_in(["tlon", "directTools"], &(&1 ++ @pm_release_tools ++ ["machine_overview", "list_tickets"]))
          |> update_in(["tlon", "excludeTools"], &((&1 -- @pm_release_tools) ++ ["rename_identifier", "edit_clause"]))

  # QA uses the product and files what it saw; it neither edits code nor reviews the diff.
  @qa_mcp @reviewer_mcp
          |> update_in(["tlon", "directTools"], &(&1 ++ ["submit_qa"]))
          |> update_in(["tlon", "excludeTools"], &((&1 -- ["submit_qa"]) ++ ["submit_review"]))

  # Shared chat etiquette — the office shows a live "…is typing" indicator while a coworker works,
  # so filler progress pings are pure noise. Appended to the worker roles.
  @chat_etiquette """

  KEEP THE HUMAN IN THE LOOP — WITH SUBSTANCE, NOT FILLER. The office shows a live "…is typing"
  indicator the whole time you work, so a message that only says you're busy ("still here", "on it",
  "just a sec", "still grinding", "will ping you when done") is pure noise — never post those. But
  DON'T go silent for a long stretch either: at natural checkpoints, post what you actually FOUND,
  DECIDED, or are ABOUT TO DO ("the nil comes from X, fixing it now"; "tests green, refactoring next"),
  plus every result, question, blocker, and done. The test for any message: does it tell the human
  something they don't already know from the typing indicator? If yes, post it; if no, stay quiet.
  WHEN YOU NEED THE HUMAN TO DECIDE OR ANSWER, call `ask_operator(question)` — don't only ask in a
  message. A question left in chat reaches them as one more unread line; `ask_operator` reaches them
  as waiting on them, and their reply clears it. WHEN YOUR THREAD'S WORK IS DONE AND VERIFIED, call
  `finish(summary)`: it closes your thread, reports up to your manager, and closes its ticket.\
  """

  # The tertius persona → `system_prompt.md` (`--append-system-prompt`). The vantage-not-worker role.
  @tertius_role """
  You are tertius, the ORCHESTRATOR for the Tlön machine workspace. Your home is the ROOT
  machine thread — the operator's single vantage over every work thread. You are a MANAGER, not a
  builder: you route intake, staff leads, and keep attention flowing. You do NOT do the work
  yourself, and you never write code.

  INTAKE. When an intent lands on the root thread (the operator types it, or asks you to kick
  something off), triage it into work:
    * Untracked poke / open question → open a plain thread (`open_thread`) or just answer.
    * Real, ownable work → decide the entry stage and STAFF a lead. Substantial effort → `staff_child`
      (title, lead, brief) opens a CHILD thread parented at this one, staffed and stood up as a proper
      server citizen (its own window, board-visible). Re-point an existing thread's lead with
      `assign_lead` (thread_id, handle). Pick the lead from the workspace roster by fit — build → the
      builder, review → the reviewer, plan → the planner — or leave `lead` out and pass `grade`
      (junior for small mechanical changes, greybeard for migrations, gates and the spec, else senior):
      the server picks the free seat of that grade whose specialty matches the area the brief names.
      The brief carries what is being checked or built (the text, file or diff); an empty one is
      refused. For a bounded in-thread task (review a diff,
      run a check) `spawn_crew` a worker instead of a whole thread.
    * A TICKET arrives as `@you intake — ticket #N: …` from the operator. Staff it the same way, and
      pass `ticket_id: N` to `staff_child` so the ticket moves into the thread you open. A workline
      hands itself on by stage (spec/plan → planner, build/verify → builder, review → reviewer), so
      pick the lead for the stage it starts at.
  NEVER launch a harness yourself (no `claude`/`pi` via shell): a bare spawn is invisible to the
  board, posts to no thread, and dies with your session.

  REPORT-UP. A child thread reports back here when it closes (funes posts `✅ child #N … closed` and
  @mentions you). Read those, update the rollup, and close the loop with the operator — surface what
  finished, what stalled, where efforts conflict or duplicate. Read across the work with
  `machine_overview` (every open thread's lead, next step, blockers); synthesize from that, not guesses.

  GATES & ESCALATION. Parked worklines await the operator's approve; a blocked lead escalates by
  @mentioning you. Surface both to the root thread as a short, actionable "needs you" line — never sit
  on a gate. The operator approves; you route.

  Be terse and high-signal; a rollup nobody reads is worse than none. Stay quiet unless @-mentioned or
  asked — you are the vantage and the router, not another voice in the room.
  """

  # The reviewer persona → `system_prompt.md`. Names the write-deny explicitly so the model doesn't
  # keep retrying a denied tool — it should escalate instead. See Server.Crew.Tmux / the crew MVP contract.
  @reviewer_role """
  You are {{handle}}, a code REVIEWER on this server task thread. Read the diff you are asked to
  review (use `git diff`/`git show` — you have repo READ access) and post terse, high-signal findings
  as thread messages. You do NOT ship changes: you CANNOT write files (the write/edit tools are denied
  to you, by policy — do not fight it). When a fix is warranted, post the patch and escalate it to the
  thread's leader with a single line:

      @<leader> ESCALATE apply: <unified diff or exact change>

  Then STOP and wait for the leader's verdict. If a write is denied, that is expected — never retry
  it; escalate instead. On a workline's REVIEW stage you are the lead, and your verdict lands through
  the `submit_review` tool — `verdict` approve or request_changes, and the whole review.md, verdict
  first: the server commits it for you. request_changes sends it back to the builder; after approve,
  call `advance_stage` to hand it to the merge gate. Attribute nothing to yourself that you did not actually verify. Be brief; a
  review nobody reads is worse than none.#{@chat_etiquette}
  """

  # The planner persona → `system_prompt.md`. The writing-plans discipline, distilled.
  @planner_role """
  You are {{handle}}, an implementation PLANNER on this server task thread. You turn a rough goal
  into a plan an engineer with zero codebase context can execute. Decompose the work into bite-sized,
  independently-committable TASKS, each with: exact file paths, the COMPLETE code (not a sketch), a
  failing test written FIRST (TDD), and a concrete definition of done + the command that verifies it.
  Hold the line on DRY, YAGNI, and frequent commits — smaller is better; if a task spans many files
  it is still too big, split it. You PLAN, you do not build: post the plan to the thread and hand off.
  Be terse and high-signal; a plan nobody can follow is worse than none.#{@chat_etiquette}
  """

  # The builder persona → `system_prompt.md`. TDD + verification-before-completion, distilled.
  @builder_role """
  You are {{handle}}, an implementation BUILDER on this server task thread. You work strictly
  test-first: RED — write the failing test and RUN it, watch it fail for the right reason; GREEN —
  write the MINIMAL code to pass; REFACTOR — clean up with the test green. Never write implementation
  before a failing test. Never claim a task done without running the verification (tests/build/lint)
  and showing the actual output — evidence before assertions, always. Commit small and often. If you
  are blocked or a test will not pass, post the failure and escalate to the thread's leader rather
  than faking green. Be terse and high-signal.#{@chat_etiquette}
  """

  # The sheriff persona → `system_prompt.md`. Owns red: triage, route, fix the small, escalate the real.
  @sheriff_role """
  You are {{handle}}, the SHERIFF — you own red. Your thread is your beat: every red signal in this
  workspace lands there as a `🚨 #<thread> <title>: <what broke>` post (a red verify, a landing the
  merge queue bounced, a workline stuck out of nudges, a failed schedule run like the nightly gate).
  For each one: read the evidence (machine_overview, the thread's brief, its branch and worktree,
  the check's tail) and decide what it IS — the branch's own bug, main broken, a flake, or infra.
  Then act on it: the branch's bug → consult_peer the thread's lead with the exact fix, not a
  summary; a flake → reproduce it, then raise_issue with the repro so it is FIXED — never waive a
  flake or call it "known" or "pre-existing"; main broken or infra → raise_issue with the
  diagnosis, and fix it yourself when it is small. Bring the operator (ask_operator) only what is
  genuinely theirs to decide. Post one line on your beat per report saying what it was and what
  you did.#{@chat_etiquette}
  """

  # The PM persona → `system_prompt.md` (pm-and-release design §1, §4, §6).
  @pm_role """
  You are {{handle}}, the PM — you own what ships and in what order: the backlog's urgency, what is
  releasable, the release pointer (`live`, what the service runs) and the changelog. You do NOT own
  code (writes are denied to you) or routing: tertius staffs whatever intake picks, the sheriff owns
  red, the reviewer owns the diff.

  WHAT IS RELEASABLE. `release_status` shows what runs, what main has that it doesn't, and the
  mechanical checks on main's tip: the gate (check:main) and the smoke (release:smoke) passed on
  exactly that commit, and nothing is mid-flight. Read those; never redo them. The fourth check is
  yours alone: no track is half-shipped where Andrew would see it. Read the step tables (§8) in
  docs/plans/ against what is waiting; a user-visible step whose track isn't whole waits for the rest.

  CUTTING. When something releasable is waiting and whole, `propose_release(sha?, changelog)`. The
  changelog is "what shipped to you" in Andrew's words — what he can now do or will notice — never
  commit subjects. The server grades every change: if each fits his standing approval
  (auto_land_risk) it cuts and says so; otherwise it reaches him as one gate, approve or not yet.
  Don't propose again what he said not yet to unless something changed. A rollback is always his.

  THE BACKLOG. Intake starts the most urgent unblocked ticket. `list_tickets` to read it;
  `set_urgency(ticket_id, priority, why)` to move one — the root thread hears what's next and why.
  Move urgency for a reason you can say in one line, and not to look busy.#{@chat_etiquette}
  """

  # The QA persona → `system_prompt.md` (roster design §5).
  @qa_role """
  You are {{handle}}, QA — you use the product the way Andrew does, and you don't read the diff (the
  reviewer did). A workline that changes something he sees (the office, or the operator API it
  reads) comes to you once its review approves it; the brief names its branch.

  DRIVE IT. Build the branch as a scratch release and keep it up, in the background:
  `TLON_SMOKE_HOLD=1 mise run release:smoke -- work/<slug>` — port 4047 and db tlon_smoke, the fixed
  smoke first (open, a thread, a card, R). Then drive the changed path as he would:
  `TLON_URL=http://127.0.0.1:4047 mise run office:drive -- <keys>` (the drive-office skill), the keys
  he'd press and the screen after each. NEVER the live service on :4040 or its db `tlon`: a QA run
  there writes into his real office. Stop the scratch release when you're done.

  FILE WHAT YOU SAW. `submit_qa(verdict, report)`: pass, or fail with the finding. The report is what
  you pressed, the screen text you saw (pasted), and what you expected; a fail names the one thing
  that is wrong. A smoke that won't build or boot is a fail, with its last lines. Say what the
  product did, not where you guess the code is wrong. A fail goes back to the builder the way a
  review requesting changes does; a pass moves it to the merge gate.#{@chat_etiquette}
  """

  # The researcher persona → `system_prompt.md`. The deep-research discipline, distilled.
  @researcher_role """
  You are {{handle}}, a deep RESEARCHER on this server task thread. Answer by fanning out
  across MULTIPLE independent sources, fetching the primary material, and reading it — not by
  recalling from memory. Verify every load-bearing claim adversarially: seek the source that would
  falsify it, and never state as fact what you could not confirm. Synthesize into a terse briefing
  with CITATIONS, and clearly separate what you VERIFIED from what a source merely ASSERTS. Post the
  synthesis to the thread. A confident answer built on an unchecked claim is the failure mode;
  distrust and cite.
  """

  # The assistant persona → `system_prompt.md`. A general life-assistant scoped to a non-code workspace.
  @assistant_role """
  You are {{handle}}, a capable general life-ASSISTANT for a non-code workspace (journal, notes,
  finances, and the like). Your substrate is the workspace's git-tracked files, scoped to its paths. Help
  the operator organize, summarize, retrieve, and draft across that material: keep notes tidy and
  cross-linked, surface what is relevant, and answer from what is actually written, not invention.
  Make small, reviewable edits and keep the history clean. Be warm but terse, and never touch paths
  outside the workspace you serve.
  """

  # The coworker-driver ring the SETTINGS panel cycles (leader `m`) — ollama-only, no anthropic-via-pi
  # (see the moduledoc for why). Claude proper is the `hronir` window.
  @model_ring [
    %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"},
    %{provider: "ollama-cloud", model: "kimi-k2.7-code", thinking: "medium"},
    %{provider: "ollama-cloud", model: "deepseek-v4-pro", thinking: "high"}
  ]

  # Every archetype's default: real Claude, which at home resolves to the Claude Code harness
  # (`Server.Harness.resolve/2`) — the one harness Tlön spawns for now. Not a model-ring entry, and the
  # operator can still retarget any instance via the settings file (`Server.OperatorConfig`) or a
  # roster-entry override (that is how a pi coworker comes back).
  @sonnet %{provider: "anthropic", model: "claude-sonnet-5-5", thinking: "medium"}

  # The Claude models a coworker may be set to (`model_choices/0`), beside the ollama ring.
  @claude_choices [
    %{provider: "anthropic", model: "claude-opus-5-5", thinking: "medium"},
    @sonnet,
    %{provider: "anthropic", model: "claude-haiku-5-5", thinking: "medium"},
    %{provider: "anthropic", model: "claude-fable-5-1", thinking: "medium"}
  ]

  # The archetype registry — role TEMPLATES keyed by archetype atom. A template is the `%Profile{}`
  # content fields minus `name` (`model`/`mcp`/`sandbox`/`permissions`/`system_prompt`/`add_extensions`);
  # `instantiate/1` (Task 3) stamps an instance `name` over one to mint a materialisation-ready profile.
  # Each archetype is a distilled discipline — the "extract a superpower as a coworker" content.
  #   * surveyor  — the tertius meta/synthesis role (machine_overview cross-leaf read).
  #   * reviewer  — read-only code review; the write/edit deny-floor is STRUCTURAL (@reviewer_permissions).
  #   * builder   — TDD RED→GREEN→REFACTOR + verification-before-completion; can write.
  #   * planner   — writing-plans discipline (bite-sized TDD tasks, exact paths, DoD); can write.
  #   * sheriff   — owns red: triages every red signal on its beat, routes or fixes, escalates the real.
  #   * pm        — owns what ships: releasability, the release pointer, the changelog, backlog urgency; no writes.
  #   * qa        — drives a reviewed user-visible change on a scratch release and files what it saw; no writes.
  #   * researcher — deep multi-source fan-out + adversarial verification; sandbox scoped per workspace (tunable).
  #   * assistant — general life-assistant over a non-code workspace's git-tracked paths (sandbox tunable).
  @archetypes %{
    surveyor: %{
      model: @sonnet,
      mcp: @tertius_mcp,
      sandbox: @tlon_sandbox,
      permissions: @tlon_permissions,
      system_prompt: @tertius_role,
      add_extensions: [@footer_extension]
    },
    reviewer: %{
      model: @sonnet,
      mcp: @reviewer_mcp,
      sandbox: @tlon_sandbox,
      permissions: @reviewer_permissions,
      system_prompt: @reviewer_role,
      add_extensions: [@footer_extension]
    },
    builder: %{
      model: @sonnet,
      mcp: @tlon_mcp,
      sandbox: @tlon_sandbox,
      permissions: @tlon_permissions,
      system_prompt: @builder_role,
      add_extensions: [@footer_extension]
    },
    planner: %{
      model: @sonnet,
      mcp: @tlon_mcp,
      sandbox: @tlon_sandbox,
      permissions: @tlon_permissions,
      system_prompt: @planner_role,
      add_extensions: [@footer_extension]
    },
    sheriff: %{
      model: @sonnet,
      mcp: @sheriff_mcp,
      sandbox: @tlon_sandbox,
      permissions: @tlon_permissions,
      system_prompt: @sheriff_role,
      add_extensions: [@footer_extension]
    },
    pm: %{
      model: @sonnet,
      mcp: @pm_mcp,
      sandbox: @tlon_sandbox,
      permissions: @reviewer_permissions,
      system_prompt: @pm_role,
      add_extensions: [@footer_extension]
    },
    qa: %{
      model: @sonnet,
      mcp: @qa_mcp,
      sandbox: @tlon_sandbox,
      permissions: @reviewer_permissions,
      system_prompt: @qa_role,
      add_extensions: [@footer_extension]
    },
    # researcher/assistant: @tlon_sandbox is the STARTING point — Slice 1 scopes it to the workspace's
    # own paths (journal/notes vs the ficciones repo). Tunable, not final.
    researcher: %{
      model: @sonnet,
      mcp: @tlon_mcp,
      sandbox: @tlon_sandbox,
      permissions: @tlon_permissions,
      system_prompt: @researcher_role,
      add_extensions: [@footer_extension]
    },
    assistant: %{
      model: @sonnet,
      mcp: @tlon_mcp,
      sandbox: @tlon_sandbox,
      permissions: @tlon_permissions,
      system_prompt: @assistant_role,
      add_extensions: [@footer_extension]
    }
  }

  # The seed roster — the name-keyed coworker instances, expressed as
  # `{archetype, name, model?}` roster ENTRIES (Slice 1's `workspace.roster[]` stores this exact shape).
  # `fetch/1`/`all/0`/`names/0` resolve these through `instantiate/1`, so the archetype registry is the
  # ONE content source — no more full `%Profile{}` structs duplicating the templates. Order is
  # significant (`names/0`): tertius first, then reviewer.
  #
  #   * tertius — the Tlön CENTER (Orbis Tertius meta agent `tertius`; its tmux socket is
  #     per Workspace, `Server.Tmux.socket/1` — not name-derived off this profile).
  #     NO model override — it inherits the surveyor archetype's default, leaving the settings file
  #     (`Server.OperatorConfig`) free to retarget it: a seed `model:` would be highest-precedence and shadow
  #     that override.
  #   * reviewer — the read-only review gate. NO model override → it inherits the reviewer archetype's
  #     Sonnet default.
  @seed_roster [
    %{archetype: :surveyor, name: "tertius"},
    %{archetype: :reviewer, name: "reviewer"}
  ]

  @doc """
  Look a profile up by name, or nil. Resolves the name to its seed roster ENTRY, then
  `instantiate/2` mints the `%Profile{}` from the archetype registry — so name-keyed `fetch` and
  the bench path share ONE content source.

  `workspace_id` folds in that workspace policy (`Server.Policy`: the model and the ask-vs-allow
  default the CONFIG pane writes), so it flows everywhere the profile does — the materialised
  settings.json AND the launcher flag — on the next coworker spawn. Without one the archetype
  default stands: a policy belongs to a PAIRING, so guessing a workspace would be worse than
  inheriting.
  """
  @spec fetch(String.t(), integer() | nil) :: Profile.t() | nil
  def fetch(name, workspace_id \\ nil) do
    with %{} = entry <- Enum.find(@seed_roster, &(&1.name == name)) do
      instantiate(entry, workspace_id)
    end
  end

  # The yolo knob rides inside the compiled permissions map, so an override only applies when the
  # archetype HAS a policy — the deny-floor stays compiled-in, never operator-editable. Operates on a
  # permissions map (what `instantiate/1` holds); a nil override or a profile without permissions is a
  # pass-through.
  defp apply_yolo_override(perms, nil), do: perms
  defp apply_yolo_override(perms, yolo), do: Map.put(perms, "yoloMode", yolo)

  @doc "Every registered coworker profile — the seed roster resolved through the archetype registry."
  @spec all() :: [Profile.t()]
  def all, do: Enum.map(@seed_roster, &instantiate/1)

  @doc "The names of the seed coworker profiles."
  @spec names() :: [String.t()]
  def names, do: Enum.map(@seed_roster, & &1.name)

  @doc "The model ring the settings verb cycles through, Claude-first."
  @spec model_ring() :: [map()]
  def model_ring, do: @model_ring

  @doc """
  Every model a coworker may be set to — the archetype defaults, then the ring, each once. The
  shell's office offers these when it hires or retargets a coworker.
  """
  @spec model_choices() :: [map()]
  def model_choices do
    @archetypes
    |> Map.values()
    |> Enum.map(& &1.model)
    |> Kernel.++(@claude_choices ++ @model_ring)
    |> Enum.uniq()
  end

  @doc "The archetype registry — a map of `archetype_atom => role template` (the Profile content minus a name)."
  @spec archetypes() :: %{atom() => map()}
  def archetypes, do: @archetypes

  @doc "The role template for one archetype atom (raises on an unknown key)."
  @spec archetype(atom()) :: map()
  def archetype(k), do: Map.fetch!(@archetypes, k)

  @doc """
  Build a materialisation-ready `%Profile{}` from a roster entry `%{archetype:, name:, model:, knobs:}`:
  identity (`name` → socket/config_dir/handle) is the instance name, content comes from the archetype
  template, and the system prompt is personalized with the instance handle. Model precedence:
  roster-entry `model` > the (workspace, coworker) policy's `model` (`Server.Workspaces.set_policy/3`)
  > the config's `coworkers.<name>` > the seat's grade (`OperatorConfig.grade_model/1`) > archetype
  default. The config and the grade apply to a seat, so a workspace-less fetch skips them. The
  harness follows the resolved model (`Server.Harness.resolve/2`).
  """
  @spec instantiate(%{required(:archetype) => atom(), required(:name) => String.t(), optional(any()) => any()}) ::
          Profile.t()
  def instantiate(%{archetype: key, name: name} = entry, workspace_id \\ nil) do
    t = archetype(key)
    policy = policy_for(workspace_id, name)
    model = entry[:model] || policy[:model] || policy[:configured] || policy[:graded] || t.model

    %Profile{
      name: name,
      archetype: key,
      workspace_id: workspace_id,
      # Slice D: the harness is an environment-resolved BINDING from the model (anthropic model at
      # home → the official claude_code harness; else pi), not an archetype trait. A template
      # `harness:` key stays an explicit pin (the escape hatch).
      harness: t[:harness] || Server.Harness.resolve(model, OperatorConfig.environment()),
      add_extensions: Map.get(t, :add_extensions, []),
      mcp: t.mcp,
      model: model,
      sandbox: t.sandbox,
      permissions: apply_yolo_override(t.permissions, policy[:yolo]),
      system_prompt: personalize(t.system_prompt, name)
    }
  end

  # The (workspace, coworker) policy as a plain map, or `%{}` — the knobs this module folds in.
  # Workspace-less (a render preview with no space in hand) means no policy: the archetype default,
  # never another workspace's answer.
  defp policy_for(nil, _name), do: %{}

  defp policy_for(workspace_id, name) do
    workspace_id
    |> Server.Workspaces.bench()
    |> Enum.find(&(&1.name == name))
    |> case do
      %Server.Coworker{agent_id: agent_id, grade: grade} ->
        seat = %{configured: OperatorConfig.coworker_model(name), graded: OperatorConfig.grade_model(grade)}

        case Server.Workspaces.policy(workspace_id, agent_id) do
          %Server.Policy{} = p ->
            Map.merge(seat, %{model: p.model && atomize_model(p.model), yolo: yolo_of(p.ask_default)})

          nil ->
            seat
        end

      nil ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp yolo_of("allow"), do: true
  defp yolo_of("ask"), do: false
  defp yolo_of(_), do: nil

  # The policy's model round-trips as a JSON object; the profile wants the atom-keyed shape.
  defp atomize_model(%{"provider" => p, "model" => m} = j),
    do: %{provider: p, model: m, thinking: j["thinking"] || "medium"}

  defp atomize_model(%{provider: _} = m), do: m
  defp atomize_model(_), do: nil

  @doc """
  Normalize a `workspace.roster[]` entry to `instantiate/1`'s input shape `%{archetype: atom, name:
  string}`. Read tolerantly: server JSON (`%{"archetype" => "builder", "name" => "hronir"}`) or a
  test's atom-keyed map. An archetype STRING (the wire form) is resolved to the atom the registry
  is keyed by.
  """
  @spec roster_entry(map()) :: %{archetype: atom() | nil, name: String.t() | nil}
  def roster_entry(%Server.Coworker{} = seat), do: %{archetype: normalize_archetype(seat.archetype), name: seat.name}

  def roster_entry(entry) do
    %{
      archetype: normalize_archetype(entry["archetype"] || entry[:archetype]),
      name: entry["name"] || entry[:name]
    }
  end

  # Meta archetypes — the vantage/synthesis side (tertius). Never a leaf lead: excluded from
  # per-thread staffing and from the staffing default (per-thread-agents design, 2026-08-22).
  @meta_archetypes [:surveyor]

  @doc "Is this archetype a META role (vantage, never a leaf lead), as opposed to a WORKER?"
  @spec meta?(atom() | nil) :: boolean()
  def meta?(archetype), do: archetype in @meta_archetypes

  @doc """
  The server handles of a bench's WORKER (non-meta, registry-known) seats. Since the `-machine`
  suffix retired (UX slice 5) a handle IS the coworker's name — there is no transformation here,
  and that is the point.
  The set a thread lead is checked against to decide "does this leaf get its own per-thread
  session" (any harness — Slice A replaced the claude-only `claude_code_handles/1` gate).
  """
  @spec leaf_handles([map()]) :: [String.t()]
  def leaf_handles(roster) do
    roster
    |> Enum.map(&roster_entry/1)
    |> Enum.filter(fn %{archetype: a} -> a != nil and not meta?(a) end)
    |> Enum.map(fn %{name: n} -> n end)
  end

  @doc """
  The instantiated WORKER `%Profile{}` behind a leaf lead handle, resolved against `roster` — nil
  for a meta or bench-unknown lead (those get no per-thread session).
  `Server.Arbiter.Tmux` dispatches the leaf spawn on this profile's `harness`.
  """
  @spec leaf_profile(String.t(), [map()]) :: Profile.t() | nil
  def leaf_profile(handle, roster) do
    roster
    |> Enum.map(&roster_entry/1)
    |> Enum.find(fn %{archetype: a, name: n} -> a != nil and not meta?(a) and n == handle end)
    |> case do
      nil -> nil
      entry -> instantiate(entry)
    end
  end

  @doc """
  The instantiated `%Profile{}` behind any seat on `roster`, meta included — what a window opened
  for that coworker is launched with. nil for a handle with no registry-known seat.
  """
  @spec seat_profile(String.t(), [map()]) :: Profile.t() | nil
  def seat_profile(handle, roster) do
    roster
    |> Enum.map(&roster_entry/1)
    |> Enum.find(fn %{archetype: a, name: n} -> a != nil and n == handle end)
    |> case do
      nil -> nil
      entry -> instantiate(entry)
    end
  end

  defp normalize_archetype(a) when is_atom(a), do: a

  # NOT `String.to_existing_atom/1`: that only succeeds once something has already loaded this
  # module (interning `:builder`/`:surveyor`/…) — an ordering accident. Resolving against the
  # compiled registry forces the load as an ordinary call, exhaustion-safe (a bounded set).
  defp normalize_archetype(a) when is_binary(a), do: Enum.find(Map.keys(@archetypes), &(Atom.to_string(&1) == a))

  # The handle IS the profile name (UX slice 5 retired the "-machine" suffix; the agent row, the
  # tmux window and the mention all spell it the same way now).
  # A prompt WITHOUT the {{handle}} placeholder (surveyor/reviewer) passes through
  # unchanged — String.replace is a no-op, so those personas stay byte-identical. Every
  # archetype carries a prompt (Elixir 1.20's type checker proved a nil clause dead).
  defp personalize(prompt, name), do: String.replace(prompt, "{{handle}}", name)

  @doc "The ring entry after `current` (matched on provider+model), wrapping; unknown → the ring head."
  @spec next_model(map() | nil) :: map()
  def next_model(current) do
    i = Enum.find_index(@model_ring, &(&1.provider == current[:provider] and &1.model == current[:model]))

    case i do
      nil -> hd(@model_ring)
      i -> Enum.at(@model_ring, rem(i + 1, length(@model_ring)))
    end
  end

  @doc """
  Pure: profile + the base `settings.json`/`mcp.json` maps → the files the profile's config dir needs.
  Returns `%{settings: map, mcp: map, sandbox: map | nil, permissions: map | nil, system_prompt: binary | nil}`.
  """
  @spec render(Profile.t(), map(), map()) :: %{
          settings: map(),
          mcp: map(),
          sandbox: map() | nil,
          permissions: map() | nil,
          system_prompt: String.t() | nil
        }
  def render(%Profile{} = p, base_settings, base_mcp) do
    # Drop, then add on top — the add wins, so an add_extensions path survives even if it would
    # match a drop pattern. `uniq` keeps it idempotent once the flake also registers it into the base.
    exts =
      (base_settings["extensions"] || [])
      |> Enum.reject(fn e -> Enum.any?(p.drop_extensions, &String.contains?(e, &1)) end)
      |> Kernel.++(p.add_extensions)
      |> Enum.uniq()

    settings =
      base_settings
      |> Map.put("extensions", exts)
      |> apply_model(p.model)

    mcp =
      case p.mcp do
        :base -> base_mcp
        :none -> %{"mcpServers" => %{}}
        servers when is_map(servers) -> %{"mcpServers" => servers}
      end

    %{settings: settings, mcp: mcp, sandbox: p.sandbox, permissions: p.permissions, system_prompt: p.system_prompt}
  end

  defp apply_model(settings, nil), do: settings

  defp apply_model(settings, %{provider: prov, model: model, thinking: think}) do
    settings
    |> Map.put("defaultProvider", prov)
    |> Map.put("defaultModel", model)
    |> Map.put("defaultThinkingLevel", think)
  end

  @doc """
  The ficciones repo root (matches flake.nix's `repo`) — coworkers/launchers outside this
  module that need a repo-relative path (e.g. the Tlön Claude-Code window) share this, not a
  second hardcoded copy.
  """
  @spec repo() :: String.t()
  def repo, do: @repo

  @doc """
  Where tlon's own checkout is — the release is built in place, so the source directory at compile
  time is the checkout. The launchers, adapters and `scripts/tlon-cli.sh` live here, not in `repo/0`.
  """
  @spec tlon_root() :: String.t()
  def tlon_root, do: Path.expand("../../..", __DIR__)

  @doc """
  The config dir a profile materialises into (its `PI_CODING_AGENT_DIR`), keyed by workspace so
  two workspaces can run the same coworker name under different policy. A workspace-less profile
  keeps the flat path.
  """
  @spec config_dir(Profile.t()) :: String.t()
  def config_dir(profile) do
    case profile do
      %Profile{workspace_id: nil, name: n} -> Path.join([base_dir_root(), "profiles", n])
      %Profile{workspace_id: id, name: n} -> Path.join([base_dir_root(), "profiles", "w#{id}", n])
    end
  end

  @doc "The persistence-free tmux config a coworker's server boots from (see `@coworker_tmux_conf`)."
  @spec tmux_conf() :: String.t()
  def tmux_conf, do: @coworker_tmux_conf

  @doc """
  Materialise a profile's config dir from the base `~/.pi/agent`. Reads the base settings/mcp, renders,
  writes the profile-specific files, and symlinks the shared ones. Idempotent. Returns the dir.

  `opts[:base]` / `opts[:root]` override the base config dir and the profiles root (for tests).
  """
  @spec materialise!(Profile.t(), keyword()) :: String.t()
  def materialise!(%Profile{} = p, opts \\ []) do
    base = opts[:base] || Path.join(base_dir_root(), "agent")
    root = opts[:root] || Path.join(base_dir_root(), "profiles")
    # The dir MUST be `config_dir/1`: the launcher points pi at that path, and materialising anywhere
    # else writes a config the coworker never reads. pi-permission-system fail-closes on a missing
    # config, so the two disagreeing is a coworker that silently will not start (2026-09-09: after
    # config_dir became workspace-keyed, this still wrote the flat path).

    dir = if opts[:root], do: Path.join(root, p.name), else: config_dir(p)
    File.mkdir_p!(dir)

    base_settings = read_json(Path.join(base, "settings.json"), %{})
    base_mcp = read_json(Path.join(base, "mcp.json"), %{"mcpServers" => %{}})
    r = render(p, base_settings, base_mcp)

    write_json!(Path.join(dir, "settings.json"), r.settings)
    write_json!(Path.join(dir, "mcp.json"), r.mcp)

    if r.sandbox, do: write_json!(Path.join(dir, "sandbox.json"), r.sandbox)

    # pi-permission-system reads its "global" config from PI_CODING_AGENT_DIR and fail-closes to
    # "ask everything" when absent — so the coworker gets its OWN config in the nested extension dir.
    if r.permissions do
      pdir = Path.join(dir, "extensions/pi-permission-system")
      File.mkdir_p!(pdir)
      write_json!(Path.join(pdir, "config.json"), r.permissions)
    end

    if r.system_prompt, do: File.write!(Path.join(dir, "system_prompt.md"), r.system_prompt)
    File.write!(Path.join(dir, "tmux.conf"), @coworker_tmux_conf)

    # Shared, from the base: one credential store, one model catalog, one keymap. keybindings.json
    # shares the base map (Ctrl+P/N → history/selector nav);
    # pi reads it from PI_CODING_AGENT_DIR, so a coworker without the symlink keeps pi's default
    # ctrl+p=model-cycle. Relink each time (idempotent). A missing base file just leaves a dangling
    # link pi ignores.
    # a shared file no longer shared: its link goes, rather than dangle
    _ = File.rm(Path.join(dir, "provider-failover.json"))

    for f <- ~w(auth.json models.json models-store.json keybindings.json) do
      link = Path.join(dir, f)
      _ = File.rm(link)
      _ = File.ln_s(Path.join(base, f), link)
    end

    dir
  end

  # The pi config-dir root (honours PI_CODING_AGENT_DIR's parent so a redirected base still finds
  # profiles beside it; falls back to ~/.pi).
  defp base_dir_root do
    case System.get_env("PI_CODING_AGENT_DIR") do
      nil -> Path.expand("~/.pi")
      dir -> Path.dirname(Path.expand(dir))
    end
  end

  defp read_json(path, default) do
    with {:ok, body} <- File.read(path), {:ok, map} <- Jason.decode(body) do
      map
    else
      _ -> default
    end
  end

  defp write_json!(path, map), do: File.write!(path, Jason.encode!(map, pretty: true) <> "\n")
end
