defmodule Server.ProfilesTest do
  @moduledoc "The coworker-profile registry, the pure render seam, and the materialiser (into a tmp dir)."
  use ExUnit.Case, async: true

  alias Server.Profile
  alias Server.Profiles

  describe "render/1 — the files a profile's dir needs" do
    test "the sandbox and the persona pass through untouched" do
      r = Profiles.render(%Profile{name: "t", sandbox: %{"enabled" => true}, system_prompt: "you are t"})
      assert r == %{sandbox: %{"enabled" => true}, system_prompt: "you are t"}
    end
  end

  describe "the tertius (center) profile — machine-scope funes citizen + sandboxed" do
    test "its tools are cut, not listed, and its sandbox allows sockets" do
      p = Profiles.fetch("tertius")
      assert %{"tlon" => %{"excludeTools" => cuts}} = p.mcp
      assert "register" in cuts
      assert p.sandbox["network"]["allowAllUnixSockets"] == true
    end

    test "carries the ORCHESTRATOR toolset (Slice 4D): staffing + cross-thread verbs, minus register/consult" do
      tlon = Profiles.fetch("tertius").mcp["tlon"]
      # register (session-claim) + consult_peer (model-to-model) are still cut; the orchestrator does
      # NOT self-contain on open/close — it opens untracked work and closes finished children.
      for cut <- ["register", "consult_peer"], do: assert(cut in tlon["excludeTools"])
      refute "open_thread" in tlon["excludeTools"]
      # The manager's routing verbs + its own machine-work loop.
      for kept <- [
            "post_message",
            "bank_fact",
            "record_done",
            "get_brief",
            "machine_overview",
            "staff_child",
            "assign_lead",
            "open_thread",
            "close_thread"
          ],
          do: refute(kept in tlon["excludeTools"])
    end

    test "carries a per-coworker permission policy — yolo (autonomous), but sudo + secrets stay denied" do
      perms = Profiles.fetch("tertius").permissions
      # autonomous coworker: asks auto-approve so an unattended agent never stalls...
      assert perms["yoloMode"] == true
      # ...but yolo is deny-preserving, so the fence holds: no unattended sudo, no credential reads,
      # and the catastrophic-command floor (deny is the one verdict yolo cannot re-permit)
      assert perms["permission"]["bash"]["sudo *"] == "deny"
      assert perms["permission"]["bash"]["rm -rf /*"] == "deny"
      assert perms["permission"]["bash"]["mkfs*"] == "deny"
      assert perms["permission"]["path"]["*.env"] == "deny"
      assert perms["permission"]["path"]["~/.ssh/*"] == "deny"
      # the point of all this: normal work just runs
      assert perms["permission"]["*"] == "allow"
    end

    test "drives Sonnet, on the Claude Code harness" do
      assert Profiles.fetch("tertius").model == %{
               provider: "anthropic",
               model: "claude-sonnet-5-5",
               thinking: "medium"
             }

      assert Profiles.fetch("tertius").harness == :claude_code
    end

    test "unknown profile → nil" do
      assert Profiles.fetch("nope") == nil
    end

    test "repo/0 is the ficciones root — the single path the Tlön claude-code window shares, not a second copy" do
      assert Profiles.repo() =~ ~r{ficciones$}
    end

    test "a workspace-less fetch inherits the archetype default — a policy belongs to a pairing" do
      # The seed entry must NOT pin a model, or entry[:model] shadows the SETTINGS override the `m`
      # verb writes. Use a NON-glm tuple so this fails if the override is ignored (glm == default).
      previous = Application.get_env(:server, :operator_config_path)
      Application.put_env(:server, :operator_config_path, nil)
      on_exit(fn -> Application.put_env(:server, :operator_config_path, previous) end)

      # No workspace, no policy: a policy belongs to a PAIRING, so a workspace-less fetch inherits the
      # archetype default rather than guessing which workspace was meant (UX slice 5).
      assert Profiles.fetch("tertius").model == Profiles.archetype(:surveyor).model
    end

    test "the deny-floor is compiled in — no policy layer can re-permit sudo or the secret paths" do
      perms = Profiles.fetch("tertius").permissions

      # yolo is the ask-vs-allow default, a workspace_policy row now; without one the archetype
      # stands...
      assert perms["yoloMode"] == true
      # ...and the deny-floor is compiled-in, never operator-editable at any layer
      assert perms["permission"]["bash"]["sudo *"] == "deny"
      assert perms["permission"]["path"]["~/.ssh/*"] == "deny"
    end

    test "no yolo override keeps the compiled default (yolo on for the autonomous coworker)" do
      assert Profiles.fetch("tertius").permissions["yoloMode"] == true
    end
  end

  describe "the tertius profile — the Orbis Tertius meta agent (the center)" do
    test "carries the ORCHESTRATOR persona as its system_prompt (intake · staff · surface, Slice 4D)" do
      p = Profiles.fetch("tertius")
      assert p.system_prompt =~ "tertius"
      assert p.system_prompt =~ "ORCHESTRATOR"
      assert p.system_prompt =~ "root"
      # The delegation toolset the mandate names — staffing, not building.
      assert p.system_prompt =~ "staff_child"
      assert p.system_prompt =~ "assign_lead"
      assert p.system_prompt =~ "changes code gets a workline"
    end

    test "render carries the persona through to the materialised files" do
      assert Profiles.render(Profiles.fetch("tertius")).system_prompt =~ "tertius"
    end

    test "the sheriff reaches across to route red — machine_overview and consult_peer — but never staffs" do
      tlon = Profiles.archetype(:sheriff).mcp["tlon"]
      refute "machine_overview" in tlon["excludeTools"] or "consult_peer" in tlon["excludeTools"]
      for staffing <- ["staff_child", "assign_lead"], do: assert(staffing in tlon["excludeTools"])
    end

    test "the PM holds the release and backlog tools, writes no code, and no other archetype has them" do
      pm = Profiles.archetype(:pm)
      tools = ~w(release_status check_candidate propose_release set_urgency)
      for t <- tools, do: refute(t in pm.mcp["tlon"]["excludeTools"])
      assert get_in(pm.permissions, ["permission", "write"]) == "deny"
      for staffing <- ["staff_child", "assign_lead"], do: assert(staffing in pm.mcp["tlon"]["excludeTools"])

      for {k, t} <- Profiles.archetypes(),
          k != :pm,
          tool <- tools,
          do: assert(tool in t.mcp["tlon"]["excludeTools"], "#{k} reaches #{tool}")
    end

    test "QA files its verdict with submit_qa, writes no code, and no other archetype has it" do
      qa = Profiles.archetype(:qa)
      for cut <- ~w(submit_qa), do: refute(cut in qa.mcp["tlon"]["excludeTools"])
      for cut <- ~w(submit_review edit_clause rename_identifier), do: assert(cut in qa.mcp["tlon"]["excludeTools"])
      assert get_in(qa.permissions, ["permission", "write"]) == "deny"
      assert qa.system_prompt =~ "release:smoke"
      assert qa.system_prompt =~ "4040"

      for {k, t} <- Profiles.archetypes(), k != :qa, do: assert("submit_qa" in t.mcp["tlon"]["excludeTools"], "#{k}")
    end

    test "the librarian curates the office's memory with its own tools, writes no code, and no other archetype has them" do
      lib = Profiles.instantiate(%{archetype: :librarian, name: "quain"})
      tools = ~w(supersede_fact forget_fact review_proposals decide_proposal landed_facts knowledge_report)
      tlon = lib.mcp["tlon"]

      for t <- tools ++ ~w(search_facts get_facts), do: refute(t in tlon["excludeTools"], t)
      for cut <- ~w(edit_clause rename_identifier staff_child assign_lead), do: assert(cut in tlon["excludeTools"])
      assert get_in(lib.permissions, ["permission", "write"]) == "deny"

      for duty <- ["supersede_proposed", "ask_operator", "never", "STATED", "lobby", "quain", "landed_facts", "keep"],
          do: assert(lib.system_prompt =~ duty, duty)

      for {k, t} <- Profiles.archetypes(),
          k != :librarian,
          tool <- tools,
          do: assert(tool in t.mcp["tlon"]["excludeTools"], "#{k} reaches #{tool}")
    end

    test "gets the cross-leaf machine_overview read (slice 4) so it can see the leaves" do
      cuts = Profiles.fetch("tertius").mcp["tlon"]["excludeTools"]
      refute "machine_overview" in cuts or "operator_inbox" in cuts

      for {k, t} <- Profiles.archetypes(),
          k != :surveyor,
          do: assert("operator_inbox" in t.mcp["tlon"]["excludeTools"], "#{k}")
    end
  end

  describe "the model ring — what the settings `m` verb cycles" do
    test "ollama-only — the anthropic-via-pi impersonation path isn't a ring entry" do
      assert [%{provider: "ollama-cloud", model: "glm-5.2"} | _] = Profiles.model_ring()
      assert Enum.all?(Profiles.model_ring(), &(&1.provider == "ollama-cloud"))
    end

    test "the plan's cheap workhorse is on it; the per-token kimi-k3 never is" do
      models = Enum.map(Profiles.model_ring(), & &1.model)
      assert "deepseek-v4.1-flash" in models
      refute "kimi-k3" in models
    end

    test "next_model advances and wraps; unknown or nil restarts at the head" do
      [first, second | _] = Profiles.model_ring()
      assert Profiles.next_model(first) == second
      assert Profiles.next_model(List.last(Profiles.model_ring())) == first
      assert Profiles.next_model(nil) == first
      assert Profiles.next_model(%{provider: "x", model: "y"}) == first
    end

    test "model_choices: every archetype default, then the ring, each once" do
      choices = Profiles.model_choices()
      defaults = Profiles.archetypes() |> Map.values() |> Enum.map(& &1.model)

      assert Enum.all?(defaults ++ Profiles.model_ring(), &(&1 in choices))
      assert choices == Enum.uniq(choices)
      assert hd(choices) in defaults

      for m <- ~w(claude-opus-5-5 claude-sonnet-5-5 claude-haiku-5-5 claude-fable-5-1),
          do: assert(Enum.any?(choices, &(&1.provider == "anthropic" and &1.model == m)))
    end
  end

  describe "materialise!/2 — writes the config dir" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "aleph-prof-#{System.pid()}-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(tmp) end)
      %{root: Path.join(tmp, "profiles")}
    end

    test "writes the persona, the sandbox and the tmux config — nothing else", %{root: root} do
      dir = Profiles.materialise!(Profiles.fetch("tertius"), root: root)
      assert dir == Path.join(root, "tertius")
      assert File.read!(Path.join(dir, "system_prompt.md")) =~ "tertius"
      assert Jason.decode!(File.read!(Path.join(dir, "sandbox.json")))["enabled"] == true
      assert dir |> File.ls!() |> Enum.sort() == ~w(sandbox.json system_prompt.md tmux.conf)
    end

    test "writes the coworker's persistence-free tmux.conf — fresh on rebuild, never resurrected", %{root: root} do
      dir = Profiles.materialise!(Profiles.fetch("tertius"), root: root)
      conf = File.read!(Path.join(dir, "tmux.conf"))
      # the interactive bits travel with the coworker...
      assert conf =~ "set -g mouse on"
      assert conf =~ "set -s extended-keys on"
      assert conf =~ "set -g mode-style"
      # ...the persistence plugins deliberately do NOT
      refute conf =~ "resurrect"
      refute conf =~ "continuum"
    end

    test "idempotent — a second materialise rewrites without error", %{root: root} do
      Profiles.materialise!(Profiles.fetch("tertius"), root: root)
      assert Profiles.materialise!(Profiles.fetch("tertius"), root: root) == Path.join(root, "tertius")
    end
  end

  describe "the reviewer profile — the write-deny gate" do
    test "reviewer is a fetchable profile on claude-sonnet-5-5 (its archetype default)" do
      p = Profiles.fetch("reviewer")
      assert %Profile{name: "reviewer"} = p
      assert p.model.model == "claude-sonnet-5-5"
    end

    test "its permission policy DENIES the write and edit tools but ALLOWS reads" do
      perms = Profiles.fetch("reviewer").permissions
      assert perms["permission"]["write"] == "deny"
      assert perms["permission"]["edit"] == "deny"
      # reads fall through the "*" => "allow" fallback (no read/grep/find/ls deny)
      assert perms["permission"]["*"] == "allow"
      refute Map.has_key?(perms["permission"], "read")
    end

    test "the obvious bash-write patterns are denied" do
      bash = Profiles.fetch("reviewer").permissions["permission"]["bash"]
      for pat <- ["* > *", "* >> *", "sed -i*", "tee *", "dd *"], do: assert(bash[pat] == "deny")
    end

    test "the catastrophic deny-floor is preserved from @tlon_permissions" do
      # tertius carries @tlon_permissions verbatim, so its bash map IS the floor. Assert EVERY
      # floor rule survives the reviewer's merge unchanged — a refactor that silently drops one
      # (e.g. `curl * | sh`) must fail here, not just the two spot-checks below.
      floor = Profiles.fetch("tertius").permissions["permission"]["bash"]
      reviewer = Profiles.fetch("reviewer").permissions["permission"]["bash"]

      for {pattern, action} <- floor do
        assert reviewer[pattern] == action, "deny-floor entry #{inspect(pattern)} not preserved"
      end

      assert reviewer["rm -rf /*"] == "deny"
      assert reviewer["sudo *"] == "deny"
    end

    test "yoloMode is on so allowed reads never stall on an ask" do
      assert Profiles.fetch("reviewer").permissions["yoloMode"] == true
    end

    test "the write-deny lands as Claude Code deny rules for the file-writing tools" do
      assert Server.Harness.ClaudeCode.launch_command(Profiles.fetch("reviewer")) =~ "Write,Edit,NotebookEdit"
    end
  end

  describe "archetype — each profile is an instance of a role template" do
    test "every registered profile declares an archetype atom" do
      for p <- Profiles.all() do
        assert is_atom(p.archetype) and not is_nil(p.archetype)
      end
    end

    test "tertius is the surveyor archetype, reviewer is the reviewer archetype" do
      assert Profiles.fetch("tertius").archetype == :surveyor
      assert Profiles.fetch("reviewer").archetype == :reviewer
    end
  end

  describe "the archetype registry — role templates keyed by archetype atom" do
    test "the seed archetype set is present with sane defaults" do
      keys = Profiles.archetypes() |> Map.keys() |> Enum.sort()
      assert keys == ~w(assistant builder librarian planner pm qa researcher reviewer sheriff surveyor)a
    end

    test "reviewer archetype cannot write (deny floor), builder can" do
      assert get_in(Profiles.archetype(:reviewer).permissions, ["permission", "write"]) == "deny"
      assert get_in(Profiles.archetype(:builder).permissions, ["permission", "write"]) != "deny"
    end

    test "each archetype has a non-empty system prompt and a default model" do
      for {_k, t} <- Profiles.archetypes() do
        assert is_binary(t.system_prompt) and t.system_prompt != ""
        assert match?(%{model: _}, t) and not is_nil(t.model)
      end
    end

    test "archetype/1 fetches one template by its atom key" do
      assert Profiles.archetype(:surveyor).system_prompt =~ "tertius"
      # the four new prompts carry the {{handle}} placeholder (personalized at instantiate time),
      # not a hardcoded `<role>-machine` self-identity.
      assert Profiles.archetype(:builder).system_prompt =~ "{{handle}}"
    end
  end

  describe "instantiate/1 — a named coworker from an archetype roster entry" do
    test "builds a named Profile from an archetype, content from the template" do
      p = Profiles.instantiate(%{archetype: :builder, name: "atlas"})
      # identity = the instance name
      assert p.name == "atlas"
      assert p.archetype == :builder
      # content (sandbox/mcp) from the builder template
      assert p.sandbox == Profiles.archetype(:builder).sandbox
      assert p.mcp == Profiles.archetype(:builder).mcp
    end

    test "seat_profile reads the seat's own policy on its workspace: an ollama model spawns on it, through Claude Code's gateway, not Sonnet" do
      Server.TestDB.clean!()
      {:ok, ws} = Server.Workspaces.register(%{name: "Night"})
      {:ok, c} = Server.Workspaces.seat(ws.id, %{name: "dahlmann", archetype: "builder"})
      {:ok, _} = Server.Workspaces.retarget(ws.id, c.agent_id, %{model: "ollama-cloud/kimi-k2.7-code"})

      p = Profiles.seat_profile("dahlmann", Server.Workspaces.bench_all(ws.id), ws.id)
      assert %{provider: "ollama-cloud", model: "kimi-k2.7-code"} = p.model
      assert p.harness == :claude_code
      launch = Server.Harness.ClaudeCode.launch_command(p)
      assert launch =~ "TLON_PROVIDER=ollama-cloud"
      assert launch =~ "--model kimi-k2.7-code"
    end

    test "model_label names the model a seat is launched on, from its policy; no seat, no label" do
      Server.TestDB.clean!()
      {:ok, ws} = Server.Workspaces.register(%{name: "Labels"})
      {:ok, c} = Server.Workspaces.seat(ws.id, %{name: "otalora", archetype: "builder"})
      {:ok, _} = Server.Workspaces.retarget(ws.id, c.agent_id, %{model: "ollama-cloud/kimi-k2.7-code"})

      assert Profiles.model_label(ws.id, "otalora") == "ollama-cloud/kimi-k2.7-code (claude_code)"
      assert Profiles.model_label(ws.id, "nobody") == nil
      assert Profiles.model_label(nil, "otalora") == nil
    end

    test "builder and surveyor both instantiate on the claude_code harness" do
      assert Profiles.instantiate(%{archetype: :builder, name: "hronir"}).harness == :claude_code
      assert Profiles.instantiate(%{archetype: :surveyor, name: "tertius"}).harness == :claude_code
    end

    test "roster_entry normalizes string- and atom-keyed entries; a string archetype → its atom" do
      assert Profiles.roster_entry(%Server.Coworker{archetype: "builder", name: "hronir"}) == %{
               archetype: :builder,
               name: "hronir"
             }

      assert Profiles.roster_entry(%{archetype: :surveyor, name: "tertius"}) == %{archetype: :surveyor, name: "tertius"}
    end

    test "leaf_handles returns <name>-machine for WORKER entries only — never the meta surveyor" do
      roster = [
        %Server.Coworker{archetype: "surveyor", name: "tertius"},
        %Server.Coworker{archetype: "builder", name: "hronir"},
        %Server.Coworker{archetype: "planner", name: "borges"},
        %Server.Coworker{archetype: "nonesuch", name: "ghost"}
      ]

      assert Profiles.leaf_handles(roster) == ["hronir", "borges"]
      assert Profiles.leaf_handles([]) == []
    end

    test "leaf_profile resolves a worker lead handle to its instantiated profile; meta/unknown → nil" do
      roster = [
        %Server.Coworker{archetype: "surveyor", name: "tertius"},
        %Server.Coworker{archetype: "planner", name: "borges"}
      ]

      assert %Profile{archetype: :planner} = Profiles.leaf_profile("borges", roster)
      assert Profiles.leaf_profile("tertius", roster) == nil
      assert Profiles.leaf_profile("stranger", roster) == nil
    end

    test "roster-entry model overrides the archetype default" do
      entry = %{archetype: :reviewer, name: "vera", model: %{provider: "anthropic", model: "sonnet", thinking: "low"}}
      assert Profiles.instantiate(entry).model.model == "sonnet"
    end

    test "two instances of one archetype get distinct identities" do
      a = Profiles.instantiate(%{archetype: :builder, name: "atlas"})
      b = Profiles.instantiate(%{archetype: :builder, name: "borges"})
      assert a.name != b.name and a.archetype == b.archetype
    end

    test "personalizes the prompt with the instance handle — no placeholder or role leak" do
      prompt = Profiles.instantiate(%{archetype: :builder, name: "atlas"}).system_prompt
      assert prompt =~ "atlas"
      refute prompt =~ "{{handle}}"
      refute prompt =~ "builder"
    end

    test "instancing the reviewer archetype under another name states its own handle, not reviewer" do
      prompt = Profiles.instantiate(%{archetype: :reviewer, name: "vera"}).system_prompt
      assert prompt =~ "vera"
      refute prompt =~ "reviewer"
      refute prompt =~ "{{handle}}"
    end

    test "a non-personalized prompt (surveyor/tertius) is byte-identical to the template" do
      # tertius's prompt has NO placeholder — personalize must leave it untouched so Task 4 keeps
      # fetch(\"tertius\") byte-identical.
      p = Profiles.instantiate(%{archetype: :surveyor, name: "tertius"})
      assert p.system_prompt == Profiles.archetype(:surveyor).system_prompt
    end
  end

  describe "fetch/1 resolves through the archetype registry (back-compat)" do
    # tertius is the live Tlön centre: its render carries the surveyor's model, role and tools.
    test "fetch('tertius') materialises the surveyor archetype (the live Tlön spawn)" do
      p = Profiles.fetch("tertius")
      assert Profiles.render(p).system_prompt == Profiles.archetype(:surveyor).system_prompt
      assert p.model == %{provider: "anthropic", model: "claude-sonnet-5-5", thinking: "medium"}
      refute "machine_overview" in p.mcp["tlon"]["excludeTools"]
    end

    test "fetch('reviewer') INTENTIONALLY flips glm-5.2 → claude-sonnet-5-5 (A2: reviewer is not live-spawned)" do
      # Pins the design-correct flip so it can't silently regress back to the legacy incidental glm.
      assert Profiles.fetch("reviewer").model == %{
               provider: "anthropic",
               model: "claude-sonnet-5-5",
               thinking: "medium"
             }
    end

    test "every archetype defaults to claude-sonnet-5-5 — Claude Code is the one harness Tlön spawns" do
      for k <- ~w(surveyor reviewer planner builder researcher assistant)a do
        assert Profiles.archetype(k).model.model == "claude-sonnet-5-5",
               "archetype #{k} should default to claude-sonnet-5-5"
      end
    end

    test "an unknown name is still nil (no archetype fallback for a non-roster handle)" do
      assert Profiles.fetch("nope") == nil
    end

    test "all/0 and names/0 stay in roster order [tertius, reviewer], one content source" do
      assert Profiles.names() == ["tertius", "reviewer"]
      assert Enum.map(Profiles.all(), & &1.name) == ["tertius", "reviewer"]
      # all/0 flows through the same archetype path, so reviewer here is sonnet too (not the legacy glm).
      reviewer = Enum.find(Profiles.all(), &(&1.name == "reviewer"))
      assert reviewer.model.model == "claude-sonnet-5-5"
    end
  end

  describe "the config dir is keyed by workspace (UX slice 5)" do
    test "materialises into config_dir — the path the launcher reads the persona from" do
      profile = %Profile{name: "amy", archetype: :builder, workspace_id: 7}

      assert Profiles.config_dir(profile) =~ "/profiles/w7/amy"
    end

    test "a workspace-less profile keeps the flat dir" do
      profile = %Profile{name: "amy", archetype: :builder}

      refute Profiles.config_dir(profile) =~ "/w"
      assert Profiles.config_dir(profile) =~ "/profiles/amy"
    end

    test "materialise! writes WHERE config_dir says — the two cannot disagree" do
      state = Path.join(System.tmp_dir!(), "mat_#{System.pid()}_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(state) end)

      previous = System.get_env("XDG_STATE_HOME")
      System.put_env("XDG_STATE_HOME", state)

      on_exit(fn ->
        if previous, do: System.put_env("XDG_STATE_HOME", previous), else: System.delete_env("XDG_STATE_HOME")
      end)

      profile = %Profile{name: "amy", archetype: :builder, workspace_id: 7}
      dir = Profiles.materialise!(profile)

      assert dir == Profiles.config_dir(profile)
      assert dir == Path.join([state, "tlon", "profiles", "w7", "amy"])
      assert File.exists?(Path.join(dir, "tmux.conf"))
    end
  end
end
