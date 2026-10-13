# Souls step 2 — first drafts from their Borges stories — plan

Spec: `docs/plans/2026-10-08-souls-design.md` §1, §5, §6 step 2. Ticket #61, thread #256.
Prereqs verified on main: step 1 (`office/kit/souls.ts`, the `## ` headings, the TUI poll of
`TLON_SOULS` / `~/.config/tlon/souls`) and #59 (`Server.Persona`, `Server.Generator`).

**Check (design §6):** every seat has a soul; Scharlach's is the Dwight. Plus the law from the
ticket: **a draft never overwrites a soul that exists** (Andrew edits).

## Shape

One new server module, `Server.Soul`. The TUI is the only reader of the souls dir (`kit/souls.ts`),
so nothing in `office/` changes except one AGENTS.md line. The server writes
`<souls dir>/<name>.md` once per seat:

- **The three §5 samples** (scharlach, daneri, sonny) are shipped verbatim — no model call. That is
  what makes Scharlach the Dwight deterministically.
- **Every other seat**: `Server.Generator` writes it from the seat's story, archetype and voice
  line (`Server.Persona`'s §2 table). Model off / capped / reply malformed → a handwritten
  template from the same story line, so *every seat has a soul* with the model off.
- **Never overwrites**: `File.write(path, body, [:exclusive])`. An existing file — edited or not,
  whatever its content — is left alone and costs no model call. To redo a draft, delete the file.
- Written with an empty `## Diary` heading (step 5 appends to it; the draft never writes diary).
- No reroll, no `--force` (YAGNI, and the way to clobber an edit).

Triggers: `tlon-cli soul <ws> [name]` (backfill the bench) and the `hire` command (like persona).

Not in scope: voice/room/diary consumption (steps 3–5, #62–#64). `kit/souls.ts` is untouched.

## Conventions for every task

- Elixir edits via menard (`~/projects/menard/bin/menard …`); tests via
  `~/projects/menard/bin/menard run test --in server <file>`; gate `mise run check` (unsandboxed).
- TDD: write the test, see it red, then the code. One commit per task, trailer per AGENTS.md.
- Test seams: `Application.put_env(:server, :souls_dir, tmp)` and the stand-in model CLI pattern of
  `server/test/server/persona_test.exs` (`:generator_cmd` → script; `$2` is the prompt).

---

## Task 1 — `Server.Soul.draft/2`: path, exclusive write, never overwrites

**Files:** create `server/lib/server/soul.ex`, `server/test/server/soul_test.exs`; edit
`server/config/test.exs`.

1. `server/config/test.exs`, beside `operator_config_path`:
   ```elixir
   config :server, souls_dir: Path.join(System.tmp_dir!(), "tlon-test-souls-unset")
   ```
   (tests override per case; this just keeps a stray call off the real `~/.config`).
2. Test (`soul_test.exs`):
   ```elixir
   defmodule Server.SoulTest do
     use ExUnit.Case, async: false
     alias Server.Soul

     setup do
       Server.TestDB.clean!()
       {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
       {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "lonnrot", archetype: "reviewer"})
       dir = Path.join(System.tmp_dir!(), "souls-#{System.unique_integer([:positive])}")
       Application.put_env(:server, :souls_dir, dir)
       on_exit(fn ->
         Application.put_env(:server, :souls_dir, Path.join(System.tmp_dir!(), "tlon-test-souls-unset"))
         File.rm_rf!(dir)
       end)
       %{ws: ws, dir: dir}
     end

     test "a seat with no soul gets a file with every section heading and an empty Diary", %{ws: ws, dir: dir} do
       assert {:ok, :written} = Soul.draft(ws.id, "lonnrot")
       body = File.read!(Path.join(dir, "lonnrot.md"))
       for h <- ["Where they're from", "Wants", "Fears", "Quirks", "People", "The side project", "Diary"],
           do: assert(body =~ "## #{h}\n")
       assert String.ends_with?(body, "## Diary\n")
     end

     test "an existing soul is never overwritten, edited or not", %{ws: ws, dir: dir} do
       File.mkdir_p!(dir)
       File.write!(Path.join(dir, "lonnrot.md"), "## Wants\nmine\n")
       assert {:ok, :exists} = Soul.draft(ws.id, "lonnrot")
       assert File.read!(Path.join(dir, "lonnrot.md")) == "## Wants\nmine\n"
     end

     test "a name that is not a seat, or not a safe file name, is refused", %{ws: ws} do
       assert {:error, :no_seat} = Soul.draft(ws.id, "nobody")
       assert {:error, :bad_name} = Soul.draft(ws.id, "../etc/passwd")
     end
   end
   ```
3. Code (`soul.ex`) — first cut, fallback body only (model comes in Task 3):
   ```elixir
   defmodule Server.Soul do
     @moduledoc """
     A seat's first-draft SOUL.md (souls design §1, §5–6 step 2): written once to
     `<souls dir>/<name>.md`, the file the office TUI polls (`office/kit/souls.ts`). The draft never
     replaces a file that exists — the operator edits these — and never writes diary (step 5's).
     A soul shapes talk and room, never a work decision.
     """
     alias Server.Workspaces

     @doc "The souls dir: `config :server, :souls_dir`, else `TLON_SOULS` (as the TUI), else `~/.config/tlon/souls`."
     def dir do
       Application.get_env(:server, :souls_dir) || System.get_env("TLON_SOULS") ||
         Path.join(System.get_env("XDG_CONFIG_HOME") || Path.expand("~/.config"), "tlon/souls")
     end

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

     defp body(name, archetype), do: fallback(name, archetype)

     defp fallback(name, archetype) do
       """
       ## Where they're from
       #{name}, the bench's #{archetype}.

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
   ```
   (The `with` returning `{:error, :no_seat}` from the `||` falls through unchanged — `with` returns
   the non-matching value.)
4. Done when: `menard run test --in server server/test/server/soul_test.exs` green (3 tests).
   Commit: `soul: a seat's first draft is written once and never over an existing file`.

## Task 2 — the three §5 samples verbatim

**Files:** edit `server/lib/server/soul.ex`, `server/test/server/soul_test.exs`.

1. Test:
   ```elixir
   test "the §5 samples are written verbatim with no model call; Scharlach is the Dwight", %{dir: dir} do
     {:ok, ws} = Server.Workspaces.register(%{name: "Other"})
     for n <- ~w(scharlach daneri sonny), do: {:ok, _} = Server.Workspaces.seat(ws.id, %{name: n, archetype: "builder"})
     for n <- ~w(scharlach daneri sonny), do: assert({:ok, :written} = Soul.draft(ws.id, n))
     s = File.read!(Path.join(dir, "scharlach.md"))
     assert s =~ "Assistant to the Manager" and s =~ "WORLD'S BEST SHERIFF" and s =~ "per procedure"
     assert File.read!(Path.join(dir, "daneri.md")) =~ "The Earth"
     assert File.read!(Path.join(dir, "sonny.md")) =~ "daisy"
   end
   ```
   (generator is `/nonexistent/…` in test: proves no model call is needed.)
2. Code: a `@samples %{"scharlach" => ~S"""…""", "daneri" => …, "sonny" => …}` module attribute,
   each a full soul in the §1 headings, text lifted from design §5 (Scharlach: story, wants =
   "Assistant to the Manager, for real this time; a standing desk", fears "being outsmarted twice",
   quirks mug/label maker/"per procedure", people tertius/Lönnrot/nolan, side project "the ledger,
   and the zoo contingency plan"; Daneri: wants poem published + second monitor, fears someone else
   has seen the Aleph, reads stanzas aloud at standup, side project *The Earth*; Sonny: wants
   everyone to have a nice day + a desk plant that survives, fears an empty kitchen, flower per
   hand-off, signs posts with a sun, side project the canvas). Each ends with `\n## Diary\n`.
   `body/2` becomes `Map.get(@samples, name) || fallback(name, archetype)`.
3. Done when: soul_test green (4 tests). Commit: `soul: the three §5 samples ship verbatim`.

## Task 3 — the model drafts the other seats from story, role and voice

**Files:** edit `server/lib/server/persona.ex` (one word: `defp voice` → `def voice`, add
`@doc false`), `server/lib/server/soul.ex`, `server/test/server/soul_test.exs`.

1. Tests (stand-in CLI as in `persona_test.exs`; script echoes a complete soul and logs `$2` to a
   file so the prompt can be asserted):
   ```elixir
   test "a seat outside the samples is drafted by the model from its story and voice", ctx do
     cli = stub_model(ctx, "## Where they're from\nFrom the story.\n\n## Wants\nw\n\n## Fears\nf\n\n## Quirks\nq\n\n## People\np\n\n## The side project\ns\n\n## Diary\nINVENTED ENTRY\n")
     assert {:ok, :written} = Soul.draft(ctx.ws.id, "lonnrot")
     body = File.read!(Path.join(ctx.dir, "lonnrot.md"))
     assert body =~ "From the story."
     refute body =~ "INVENTED ENTRY"            # the model never writes the diary
     assert String.ends_with?(body, "## Diary\n")
     prompt = File.read!(cli <> ".prompt")
     assert prompt =~ "Death and the Compass" and prompt =~ "detective"   # story + voice line
   end

   test "a malformed or missing model reply falls back to the template", ctx do
     stub_model(ctx, "sorry, no")
     assert {:ok, :written} = Soul.draft(ctx.ws.id, "lonnrot")
     assert File.read!(Path.join(ctx.dir, "lonnrot.md")) =~ "## Fears\n"
   end
   ```
   with a `stub_model/2` helper in the test file (write script, `chmod 0o755`,
   `Application.put_env(:server, :generator_cmd, path)`, restore in `on_exit`).
2. Code: `@stories` map (name → one line of the Borges story, written in Task text below), and
   ```elixir
   defp body(name, archetype) do
     Map.get(@samples, name) || from_model(name, archetype) || fallback(name, archetype)
   end

   defp from_model(name, archetype) do
     with {:ok, out} <- Server.Generator.run(prompt(name, archetype)),
          [head, _diary] <- String.split(out, ~r/^## Diary\s*$/m, parts: 2),
          true <- Enum.all?(@sections, &(head =~ "## #{&1}\n")) do
       String.trim_trailing(head) <> "\n\n## Diary\n"
     else
       _ -> nil
     end
   end
   ```
   `@sections` = the six non-Diary headings. `prompt/2` states: the coworker's name, archetype
   (`role`), `Server.Persona.voice(name, archetype)`, the story line (`Map.get(@stories, name,
   "no story; invent a small, warm one")`), the §1 headings verbatim, "short, one or two lines per
   section, dry, warm, a little absurd, never cruel; a soul shapes talk and room, never a work
   decision; end with an empty `## Diary` heading and write nothing under it; respond with ONLY the
   markdown". `@stories` lines (one sentence each, Borges): tertius — *Tlön, Uqbar, Orbis Tertius*,
   found an encyclopedia of a world that does not exist and watched it replace the real one;
   hronir — Tlön's hrönir, objects that exist because someone expected to find them; lonnrot —
   Erik Lönnrot, *Death and the Compass*, solved the crime exactly and walked into the trap; yu —
   Yu Tsun, *The Garden of Forking Paths*, a spy who had to choose one path of many; beatriz —
   Beatriz Viterbo, *The Aleph*, mourned by a narrator who kept visiting her house; nolan — James
   Nolan, *Theme of the Traitor and the Hero*, who staged a history as a play; emma — *Emma Zunz*,
   planned one act to the last detail and let no one see it; ireneo — Ireneo Funes, *Funes the
   Memorious*, remembers everything and cannot think; tzinacan — *The Writing of the God*, read
   the god's sentence in a jaguar's spots; runeberg — Nils Runeberg, *Three Versions of Judas*,
   argued the unthinkable and was ruined by it; ulrikke — Ulrikke, *Ulrica*, met a stranger in
   York for one night; averroes — *Averroes's Search*, trying to understand what a play is;
   ashe — Herbert Ashe, *Tlön*, the engineer who left a sealed volume of the encyclopedia.
   The fallback for a seat with a story uses it as `## Where they're from`.
3. Done when: soul_test green (6 tests). Commit: `soul: the model drafts a seat from its story, role and voice`.

## Task 4 — backfill the bench, and a hire gets one

**Files:** edit `server/lib/server/soul.ex`, `server/test/server/soul_test.exs`,
`scripts/tlon-cli.sh`.

1. Test:
   ```elixir
   test "draft_all drafts every seat that has none and reports each", %{ws: ws, dir: dir} do
     {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "yu", archetype: "planner"})
     File.mkdir_p!(dir)
     File.write!(Path.join(dir, "yu.md"), "mine")
     assert %{"lonnrot" => {:ok, :written}, "yu" => {:ok, :exists}} = Soul.draft_all(ws.id)
     assert File.read!(Path.join(dir, "yu.md")) == "mine"
   end
   ```
2. Code: `def draft_all(ws), do: Map.new(Workspaces.bench_all(ws), &{&1.name, draft(ws, &1.name)})`.
3. `scripts/tlon-cli.sh`: add a `soul)` case beside `persona)` —
   `soul <workspace-id> [name]`; with a name it calls `Server.Soul.draft/2`, without it
   `draft_all/1`, printing one `name: written|exists` line per seat; `raise("refused")` on error
   (rpc rule: raise to fail, never halt). Add `soul` to the usage list and the header comment.
   In `hire)`, append `{:ok, _} = Server.Soul.draft($ws, c.name);` after the persona call.
4. Done when: soul_test green (7 tests) and `mise run check:names` green (`Server.Soul` and the
   cli reference resolve). Commit: `soul: tlon-cli soul backfills the bench; hire drafts one`.

## Task 5 — docs and the gate

**Files:** `office/AGENTS.md` (line 22, the souls clause), `server/AGENTS.md` if it lists modules
(add `Server.Soul` beside `Server.Persona`).

1. Edit the clause "nothing else consumes it yet" → says the server writes first drafts
   (`Server.Soul`, `tlon-cli soul`, never over an existing file); the office still only reads.
2. Run `mise run check` (unsandboxed, through the queue). Record with `record_check`.
3. Done when: gate exit 0. Commit: `souls: AGENTS notes the server writes first drafts`.

## Verifying the whole step (QA, by hand, after landing and a release cut)

`tlon-cli soul <ws>` → one line per seat; `ls ~/.config/tlon/souls` has a file per seat;
`cat scharlach.md` is the Dwight; the TUI card shows it within a poll; edit a file, rerun the
command → the edit is untouched.

## Open / flagged

- A fallback written while the model was off is indistinguishable from an edited soul, so a later
  model run will not replace it (the cost of "never overwrite"). To redo: delete the file, rerun.
- Exclusive write is not atomic to a polling reader; a half-written file parses forgivingly and the
  next poll (mtime) corrects it.
- Seat names with no story and no sample get an invented one from the model, or the template.
