defmodule Console.ProfilesTest do
  @moduledoc "The coworker-profile registry, the pure render seam, and the materialiser (into a tmp dir)."
  use ExUnit.Case, async: true

  alias Console.Profile
  alias Console.Profiles

  @base_settings %{
    "extensions" => [
      "/repo/modules/adapters/pi/src/extension.ts",
      "/repo/modules/adapters/consult/src/extension.ts",
      "/repo/modules/adapters/lsp/src/extension.ts",
      "/repo/modules/adapters/reload/src/extension.ts"
    ],
    "defaultProvider" => "ollama-cloud",
    "defaultModel" => "deepseek-v4-flash",
    "skills" => ["/repo/modules/adapters/skills/*"]
  }
  @base_mcp %{"mcpServers" => %{"tlon" => %{"url" => "http://x/mcp"}}}

  describe "render/3 — a profile is a diff over the base config" do
    test "drops the named extensions, keeps the rest" do
      r = Profiles.render(%Profile{name: "t", drop_extensions: ["/adapters/pi/"]}, @base_settings, @base_mcp)
      refute Enum.any?(r.settings["extensions"], &String.contains?(&1, "/adapters/pi/"))
      assert Enum.any?(r.settings["extensions"], &String.contains?(&1, "/adapters/lsp/"))
      assert Enum.any?(r.settings["extensions"], &String.contains?(&1, "/adapters/consult/"))
    end

    test "mcp :none → empty mcpServers (self-contained); :base → inherits the base" do
      assert Profiles.render(%Profile{name: "t", mcp: :none}, @base_settings, @base_mcp).mcp ==
               %{"mcpServers" => %{}}

      assert Profiles.render(%Profile{name: "t", mcp: :base}, @base_settings, @base_mcp).mcp == @base_mcp
    end

    test "model override replaces the base defaults; nil inherits them" do
      r =
        Profiles.render(
          %Profile{name: "t", model: %{provider: "ollama-cloud", model: "deepseek-v4-pro", thinking: "high"}},
          @base_settings,
          @base_mcp
        )

      assert r.settings["defaultModel"] == "deepseek-v4-pro"
      assert r.settings["defaultThinkingLevel"] == "high"

      assert Profiles.render(%Profile{name: "t"}, @base_settings, @base_mcp).settings["defaultModel"] ==
               "deepseek-v4-flash"
    end

    test "sandbox passes through untouched" do
      assert Profiles.render(%Profile{name: "t", sandbox: %{"enabled" => true}}, @base_settings, @base_mcp).sandbox ==
               %{"enabled" => true}
    end

    test "permissions pass through untouched" do
      assert Profiles.render(
               %Profile{name: "t", permissions: %{"yoloMode" => true}},
               @base_settings,
               @base_mcp
             ).permissions ==
               %{"yoloMode" => true}
    end

    test "add_extensions appends on top of the base (a coworker-specific / not-yet-flake-registered extension)" do
      r =
        Profiles.render(
          %Profile{name: "t", add_extensions: ["/repo/modules/adapters/footer/src/footer.ts"]},
          @base_settings,
          @base_mcp
        )

      assert "/repo/modules/adapters/footer/src/footer.ts" in r.settings["extensions"]
      # the base ones are still there
      assert Enum.any?(r.settings["extensions"], &String.contains?(&1, "/adapters/lsp/"))
    end

    test "add wins over drop, and a doubly-present extension appears once" do
      # add_extensions survives a drop pattern it would otherwise match...
      r =
        Profiles.render(
          %Profile{
            name: "t",
            drop_extensions: ["/adapters/pi/"],
            add_extensions: ["/repo/modules/adapters/pi/src/extension.ts"]
          },
          @base_settings,
          @base_mcp
        )

      assert "/repo/modules/adapters/pi/src/extension.ts" in r.settings["extensions"]

      # ...and once the base already lists an add, it isn't duplicated (idempotent post-home:switch).
      base_with_footer =
        Map.update!(@base_settings, "extensions", &(&1 ++ ["/repo/modules/adapters/footer/src/footer.ts"]))

      r2 =
        Profiles.render(
          %Profile{name: "t", add_extensions: ["/repo/modules/adapters/footer/src/footer.ts"]},
          base_with_footer,
          @base_mcp
        )

      assert Enum.count(r2.settings["extensions"], &(&1 == "/repo/modules/adapters/footer/src/footer.ts")) == 1
    end
  end

  describe "the tertius (center) profile — machine-scope funes citizen + sandboxed" do
    test "wires funes on the machine scope, keeps the adapters/pi adapter, sockets allowed in the sandbox" do
      p = Profiles.fetch("tertius")
      # Not severed: a funes server whose token binds to the machine thread (via the env
      # tlon-cli.sh mints from), so Tlön gets its OWN dossier/logbook without a project bleed.
      assert %{"tlon" => tlon} = p.mcp
      assert tlon["url"] == "${TLON_MCP_URL}"
      assert tlon["headers"]["Authorization"] =~ "tlon-cli.sh bearer"
      # The adapters/pi funes adapter (brief + auto-capture) is KEPT now that it points at the machine thread.
      assert p.drop_extensions == []
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
          do: assert(kept in tlon["directTools"])
    end

    test "adds the generic footer back (its own package, not swept up by the adapters/pi drop)" do
      p = Profiles.fetch("tertius")
      assert Enum.any?(p.add_extensions, &String.ends_with?(&1, "/modules/adapters/footer/src/footer.ts"))
      # and the footer path does NOT match the funes-adapter drop, so it isn't a fight
      refute Enum.any?(p.add_extensions, &String.contains?(&1, "/adapters/pi/"))
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
      assert perms["permission"]["path"]["~/.pi/agent/auth.json"] == "deny"
      # the point of all this: normal work just runs
      assert perms["permission"]["*"] == "allow"
    end

    test "drives ollama-first (glm-5.2) — no pi-multi-account Claude impersonation by default" do
      assert Profiles.fetch("tertius").model == %{
               provider: "ollama-cloud",
               model: "glm-5.2",
               thinking: "medium"
             }
    end

    test "unknown profile → nil" do
      assert Profiles.fetch("nope") == nil
    end

    test "repo/0 is the ficciones root — the single path the Tlön claude-code window shares, not a second copy" do
      assert Profiles.repo() =~ ~r{ficciones$}
    end

    test "an operator override (Console.Config) is merged over the compiled model" do
      dir = Path.join(System.tmp_dir!(), "aleph-prof-cfg-#{System.unique_integer([:positive])}")
      path = Path.join(dir, "config.json")

      Console.Config.put_coworker_model(
        "tertius",
        %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"},
        path
      )

      previous = Application.get_env(:console, :config_path)
      Application.put_env(:console, :config_path, path)

      on_exit(fn ->
        Application.put_env(:console, :config_path, previous)
        File.rm_rf!(dir)
      end)

      assert Profiles.fetch("tertius").model == %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}
    end

    test "a workspace-less fetch inherits the archetype default — a policy belongs to a pairing" do
      # The seed entry must NOT pin a model, or entry[:model] shadows the SETTINGS override the `m`
      # verb writes. Use a NON-glm tuple so this fails if the override is ignored (glm == default).
      previous = Application.get_env(:console, :config_path)
      Application.put_env(:console, :config_path, nil)
      on_exit(fn -> Application.put_env(:console, :config_path, previous) end)

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
    end

    test "render carries the persona through to the materialised files" do
      assert Profiles.render(Profiles.fetch("tertius"), @base_settings, @base_mcp).system_prompt =~ "tertius"
    end

    test "gets the cross-leaf machine_overview read (slice 4) so it can see the leaves" do
      assert "machine_overview" in Profiles.fetch("tertius").mcp["tlon"]["directTools"]
    end
  end

  describe "the model ring — what the settings `m` verb cycles" do
    test "ollama-only — the anthropic-via-pi impersonation path isn't a ring entry" do
      assert [%{provider: "ollama-cloud", model: "glm-5.2"} | _] = Profiles.model_ring()
      assert Enum.all?(Profiles.model_ring(), &(&1.provider == "ollama-cloud"))
    end

    test "next_model advances and wraps; unknown or nil restarts at the head" do
      [first, second | _] = Profiles.model_ring()
      assert Profiles.next_model(first) == second
      assert Profiles.next_model(List.last(Profiles.model_ring())) == first
      assert Profiles.next_model(nil) == first
      assert Profiles.next_model(%{provider: "x", model: "y"}) == first
    end
  end

  describe "materialise!/2 — writes the config dir from a base" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "aleph-prof-#{System.unique_integer([:positive])}")
      base = Path.join(tmp, "agent")
      File.mkdir_p!(base)
      File.write!(Path.join(base, "settings.json"), Jason.encode!(@base_settings))
      File.write!(Path.join(base, "mcp.json"), Jason.encode!(@base_mcp))

      for f <- ~w(auth.json models.json models-store.json provider-failover.json),
          do: File.write!(Path.join(base, f), "{}")

      on_exit(fn -> File.rm_rf!(tmp) end)
      %{base: base, root: Path.join(tmp, "profiles")}
    end

    test "writes settings/mcp/sandbox and symlinks the shared files", %{base: base, root: root} do
      dir = Profiles.materialise!(Profiles.fetch("tertius"), base: base, root: root)
      assert dir == Path.join(root, "tertius")

      settings = Jason.decode!(File.read!(Path.join(dir, "settings.json")))
      # the adapters/pi funes adapter is KEPT now (brief + auto-capture pointed at the machine thread)
      assert Enum.any?(settings["extensions"], &String.contains?(&1, "/adapters/pi/"))
      mcp = Jason.decode!(File.read!(Path.join(dir, "mcp.json")))
      assert mcp["mcpServers"]["tlon"]["url"] == "${TLON_MCP_URL}"
      assert "consult_peer" in mcp["mcpServers"]["tlon"]["excludeTools"]
      assert Jason.decode!(File.read!(Path.join(dir, "sandbox.json")))["enabled"] == true
      # permission-system fail-closes to "ask" without a config in PI_CODING_AGENT_DIR, so the
      # coworker gets its own config in the nested extension dir
      perms = Jason.decode!(File.read!(Path.join(dir, "extensions/pi-permission-system/config.json")))
      assert perms["yoloMode"] == true
      assert perms["permission"]["bash"]["sudo *"] == "deny"
      # the shared files are symlinks back to the base — one credential store, one model catalog,
      # one failover policy (so pi-multi-account fails this coworker's Claude over to ollama.com glm)
      assert File.read_link!(Path.join(dir, "auth.json")) == Path.join(base, "auth.json")

      assert File.read_link!(Path.join(dir, "provider-failover.json")) ==
               Path.join(base, "provider-failover.json")
    end

    test "a profile with a persona writes system_prompt.md (the tertius meta agent)", %{base: base, root: root} do
      dir = Profiles.materialise!(Profiles.fetch("tertius"), base: base, root: root)
      assert File.read!(Path.join(dir, "system_prompt.md")) =~ "tertius"
    end

    test "writes the coworker's persistence-free tmux.conf — fresh on rebuild, never resurrected",
         %{base: base, root: root} do
      dir = Profiles.materialise!(Profiles.fetch("tertius"), base: base, root: root)
      conf = File.read!(Path.join(dir, "tmux.conf"))
      # the interactive bits travel with the coworker...
      assert conf =~ "set -g mouse on"
      assert conf =~ "set -s extended-keys on"
      assert conf =~ "set -g mode-style"
      # ...the persistence plugins deliberately do NOT
      refute conf =~ "resurrect"
      refute conf =~ "continuum"
    end

    test "idempotent — a second materialise re-links without error", %{base: base, root: root} do
      Profiles.materialise!(Profiles.fetch("tertius"), base: base, root: root)
      assert Profiles.materialise!(Profiles.fetch("tertius"), base: base, root: root) == Path.join(root, "tertius")
    end
  end

  describe "the reviewer profile — the write-deny gate" do
    test "reviewer is a fetchable profile on claude-sonnet-5 (its archetype default)" do
      p = Profiles.fetch("reviewer")
      assert %Profile{name: "reviewer"} = p
      assert p.model.model == "claude-sonnet-5"
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

    test "materialise! writes the write-deny into the pi-permission-system config" do
      root = Path.join(System.tmp_dir!(), "crew-mat-#{System.unique_integer([:positive])}")
      base = Path.join(root, "agent")
      File.mkdir_p!(base)
      File.write!(Path.join(base, "settings.json"), ~s({"extensions":[]}))
      File.write!(Path.join(base, "mcp.json"), ~s({"mcpServers":{}}))

      dir = Profiles.materialise!(Profiles.fetch("reviewer"), base: base, root: Path.join(root, "profiles"))
      cfg = dir |> Path.join("extensions/pi-permission-system/config.json") |> File.read!() |> Jason.decode!()
      assert cfg["permission"]["write"] == "deny"
      assert cfg["permission"]["edit"] == "deny"
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
      assert keys == ~w(assistant builder planner researcher reviewer surveyor)a
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

    test "builder instantiates as a claude_code harness; surveyor as pi" do
      assert Profiles.instantiate(%{archetype: :builder, name: "hronir"}).harness == :claude_code
      assert Profiles.instantiate(%{archetype: :surveyor, name: "tertius"}).harness == :pi
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
    # REGRESSION LOCK: tertius is the only live-spawned profile (Slice-0 Tlön center). Its rendered
    # output MUST stay byte-identical across the archetype refactor. Golden values captured from the
    # pre-refactor render (mix run --no-start): glm-5.2 / ollama-cloud / medium, machine_overview
    # present, system_prompt == @tertius_role.
    test "fetch('tertius') materialises byte-identically to pre-refactor (the live Tlön spawn)" do
      r = Profiles.render(Profiles.fetch("tertius"), %{}, %{})
      assert r.system_prompt == Profiles.archetype(:surveyor).system_prompt
      assert r.system_prompt =~ "tertius"
      assert r.settings["defaultModel"] == "glm-5.2"
      assert r.settings["defaultProvider"] == "ollama-cloud"
      assert r.settings["defaultThinkingLevel"] == "medium"
      assert "machine_overview" in r.mcp["mcpServers"]["tlon"]["directTools"]
    end

    test "fetch('reviewer') INTENTIONALLY flips glm-5.2 → claude-sonnet-5 (A2: reviewer is not live-spawned)" do
      # Pins the design-correct flip so it can't silently regress back to the legacy incidental glm.
      assert Profiles.fetch("reviewer").model == %{
               provider: "anthropic",
               model: "claude-sonnet-5",
               thinking: "medium"
             }
    end

    test "the archetype model defaults are pinned both ways (surveyor→glm, the other five→sonnet)" do
      # Guards the Task 1-2 review's "sonnet-vs-glm untested" gap.
      assert Profiles.archetype(:surveyor).model.model == "glm-5.2"

      for k <- ~w(reviewer planner builder researcher assistant)a do
        assert Profiles.archetype(k).model.model == "claude-sonnet-5",
               "archetype #{k} should default to claude-sonnet-5"
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
      assert reviewer.model.model == "claude-sonnet-5"
    end
  end
end
