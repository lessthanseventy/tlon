defmodule Console.MixProject do
  use Mix.Project

  # aleph — the cockpit TUI over funes (design: ../../docs/plans/2026-08-15-aleph-tui-design.md).
  # One raxol_core app: sidebars are panels/components over funes' read models; the middle
  # column will later embed a ghostty_ex view of a tmux client. aleph depends on funes and
  # boots its OTP app to subscribe to the Bus; funes never depends on aleph (§8 boundary), and
  # aleph's TUI deps stay quarantined here so funes' dep list stays pristine.
  def project do
    [
      app: :console,
      version: "0.1.0",
      elixir: "~> 1.19",
      # Boundary enforcement (lib/aleph.ex): aleph may call only what Server exports.
      compilers: [:boundary] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Console.Application, []}
    ]
  end

  # Run the whole precommit gate (incl. `test`) in the test environment.
  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Mirror funes' one gate: format, warnings-as-errors, and the suite.
  defp aliases do
    [
      # Self-heal the termbox2 NIF after every compile (see ensure_termbox_nif/1), and the
      # raxol input-parser Kitty CSI-u + termbox2_nif tb_resize/0 stub patches before it (so the
      # `compile` that follows rebuilds the patched dep modules — see ensure_raxol_kitty_parser/1
      # and ensure_termbox_resize_stub/1).
      compile: [
        &ensure_raxol_kitty_parser/1,
        &ensure_raxol_paste_parser/1,
        &ensure_termbox_resize_stub/1,
        "compile",
        &ensure_termbox_nif/1
      ],
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test --warnings-as-errors"
      ]
    ]
  end

  # raxol_terminal 2.6.1 ships a termbox2 NIF with three defects this alias repairs after every
  # compile (all idempotent, pinned by test/aleph/termbox_nif_test.exs). deps/ is gitignored,
  # so the fix can't live in the dep's Makefile — it must re-apply on each build.
  #
  #   1. TRUECOLOR. `termbox_impl.c` defines TB_LIB_OPTS (→ 64-bit `uintattr_t`), but the wrapper
  #      `termbox2_nif.c` does not, so it compiles against the default 16-bit width and truncates
  #      every 24-bit colour handed to `tb_set_cell` — the red byte is dropped, so amber renders
  #      green and pink renders blue. We recompile with `-DTB_OPT_ATTR_W=64` so both translation
  #      units agree on the colour type. Re-runs only when needed (no marker, or the dep rebuilt
  #      the .so newer than our marker).
  #   2. INSTALL. The Makefile copies the .so into build-output priv only inside its link recipe,
  #      which `make` skips when the .so already exists; the loader reads
  #      `:code.priv_dir(:raxol_terminal)`, so a missing copy is a runtime `:nif_not_loaded`.
  #   3. NO RESIZE ENTRY. termbox2 only re-learns terminal size inside its poll path, which aleph
  #      never calls (Raxol.Terminal.Driver owns input) — so tb_width()/tb_height() stay frozen at
  #      tb_init size. We patch in a public tb_resize/0 (see patch_termbox_resize/1 +
  #      ensure_termbox_resize_stub/1) the cockpit calls each tick; it gates the (screen-clearing)
  #      resize_cellbufs on an actual size change, since update_term_size alone is a cheap ioctl.
  @termbox_cflags "-O2 -Wall -Wextra -Wno-unused-parameter -std=c99 -fPIC -Itermbox2 -DTB_OPT_ATTR_W=64"

  defp ensure_termbox_nif(_args) do
    c_src =
      Path.join([Mix.Project.deps_path(), "raxol_terminal", "lib", "termbox2_nif", "c_src"])

    # The tb_resize/0 NIF (defect #3, see @termbox_resize_impl) is patched into the C source here;
    # a fresh patch forces a .so rebuild regardless of the truecolor marker.
    patched? = File.dir?(c_src) and patch_termbox_resize(c_src)
    rebuilt? = File.dir?(c_src) and rebuild_termbox_truecolor(c_src, patched?)
    install_termbox_nif(rebuilt?)
    :ok
  end

  # raxol_terminal 2.6.1's InputParser has no Kitty keyboard CSI-u decode, so shifted keys
  # (shift+enter) arrive as \e[13;2u and are silently consumed (no event) — the modifier is
  # lost before aleph sees it. deps/ is gitignored, so this self-heals the patch onto the dep
  # source before compile (idempotent — a `defp csi_u_event` marker). When the patch is (re)applied
  # the source mtime advances past the dep's beam, so the `compile` step that follows rebuilds
  # raxol_terminal with the patch. The host-side Kitty disambiguate mode that PRODUCES these
  # sequences is enabled in Console.Cockpit itself (no dep patch) — this only teaches the parser
  # to decode them.
  @kitty_parser Path.join([
                  Mix.Project.deps_path(),
                  "raxol_terminal",
                  "lib",
                  "raxol",
                  "terminal",
                  "ansi",
                  "input_parser.ex"
                ])

  # The CSI-u clauses inserted at the head of parse_csi_tilde_one/1's `case`.
  @kitty_csi_u_clauses """
      # Modified cursor/arrow keys via CSI params: ESC [ 1 ; <mods> <A|B|C|D|F|H|P|Q|R|S>. The
      # dedicated parse_one clause only matches a SINGLE-BYTE modifier, so a MULTI-DIGIT mods field
      # falls through to here — and a lock modifier produces exactly that: with Num Lock on, ghostty
      # (under \\e[>1u Kitty) tags every key with num_lock (128), so a plain Up arrives as \\e[1;129A,
      # not \\e[A, and was silently dropped (arrows did nothing whenever Num Lock/Caps Lock was on).
      # decode_modifier keys off bits 1/2/4 only, so lock bits (num_lock=128, caps_lock=64) read as
      # "no modifier" — a plain Up stays a plain Up, ctrl+Up (\\e[1;133A = 4+128) stays ctrl+Up.
      {[1, mods], final, rest} when final in [65, 66, 67, 68, 70, 72, 80, 81, 82, 83] ->
        {shift, alt, ctrl} = decode_modifier(mods)
        {key_event(csi_letter_to_key(final), shift: shift, alt: alt, ctrl: ctrl), rest}

      # Kitty keyboard protocol CSI-u: ESC [ <codepoint> [ ; <mods> [ ; <event> ] ] u.
      # Enabled by Console.Cockpit writing \\e[>1u (disambiguate) on the host tty. Modified keys
      # with no legacy form — shift+enter (\\e[13;2u), ctrl+enter (\\e[13;5u), shift+tab
      # (\\e[9;2u) — arrive here. Plain keys keep their legacy form (enter stays \\r), so this
      # only fires for the modified/disambiguated ones. `mods` is 1 + bitmask (shift=1, alt=2,
      # ctrl=4, meta=8).
      {[cp], ?u, rest} ->
        {csi_u_event(cp, []), rest}

      {[cp, mods], ?u, rest} ->
        {csi_u_event(cp, mods_to_opts(mods)), rest}

      {[cp, mods, _event_type], ?u, rest} ->
        {csi_u_event(cp, mods_to_opts(mods)), rest}

  """

  # The helpers inserted after decode_modifier/1.
  @kitty_csi_u_helpers """
    # Build the opts keyword list for `key_event/2` from a Kitty CSI-u mods field (1 + bitmask).
    # Reuses `decode_modifier/1` (same shift=1/alt=2/ctrl=4 encoding); the meta bit (8) is ignored
    # for now — no binding reads it.
    defp mods_to_opts(mod) when is_integer(mod) do
      {shift, alt, ctrl} = decode_modifier(mod)
      [{:shift, shift}, {:alt, alt}, {:ctrl, ctrl}]
      |> Enum.filter(fn {_, on?} -> on? end)
      |> Enum.map(fn {k, _} -> {k, true} end)
    end

    # A Kitty CSI-u event: map the codepoint to a key atom (special keys) or a :char (printable),
    # then attach the modifier opts. Plain keys with a legacy form (enter=\\r, tab=\\t, ctrl+v=\\x16)
    # never arrive here — only modified or disambiguated ones — so the mapping covers the keys
    # that actually surface as CSI-u under disambiguate mode.
    defp csi_u_event(cp, opts) do
      case kitty_codepoint_to_key(cp) do
        {:key, k} -> key_event(k, opts)
        {:char, c} -> key_event(:char, Keyword.merge(opts, char: c))
      end
    end

    defp kitty_codepoint_to_key(13), do: {:key, :enter}
    defp kitty_codepoint_to_key(9), do: {:key, :tab}
    defp kitty_codepoint_to_key(127), do: {:key, :backspace}
    defp kitty_codepoint_to_key(27), do: {:key, :escape}
    defp kitty_codepoint_to_key(32), do: {:key, :space}
    defp kitty_codepoint_to_key(cp) when cp >= 32 and cp <= 0x10ffff, do: {:char, <<cp::utf8>>}
    defp kitty_codepoint_to_key(_), do: {:key, :unknown}

  """

  defp ensure_raxol_kitty_parser(_args) do
    path = @kitty_parser

    case File.read(path) do
      {:ok, src} ->
        if String.contains?(src, "defp csi_u_event") do
          :ok
        else
          # Each anchor is checked individually and a miss RAISES: a soft warning here would let
          # a raxol bump ship a green build with an unpatched (or half-patched) parser, silently
          # regressing shift+enter. Nothing is written unless both replacements landed.
          patched =
            src
            |> replace_anchor!(
              "parse_csi_tilde_one",
              "  defp parse_csi_tilde_one(data) do\n    case parse_csi_params(data) do\n      {[n], ?~, rest} ->",
              "  defp parse_csi_tilde_one(data) do\n    case parse_csi_params(data) do\n" <>
                @kitty_csi_u_clauses <> "      {[n], ?~, rest} ->"
            )
            |> replace_anchor!(
              "decode_modifier",
              "  defp decode_modifier(mod) when is_integer(mod) do\n    bits = mod - 1\n    shift = (bits &&& 1) != 0\n    alt = (bits &&& 2) != 0\n    ctrl = (bits &&& 4) != 0\n    {shift, alt, ctrl}\n  end\n",
              "  defp decode_modifier(mod) when is_integer(mod) do\n    bits = mod - 1\n    shift = (bits &&& 1) != 0\n    alt = (bits &&& 2) != 0\n    ctrl = (bits &&& 4) != 0\n    {shift, alt, ctrl}\n  end\n" <>
                @kitty_csi_u_helpers
            )

          File.write!(path, patched)
          Mix.shell().info("[aleph] patched raxol InputParser with Kitty CSI-u decode")
        end

      _ ->
        :ok
    end
  end

  # raxol_terminal 2.6.1's InputParser ships a LEGACY bracketed-paste handler in parse_one/1 that
  # collapses a whole \e[200~…\e[201~ paste into ONE :paste event via :binary.split — fragile when
  # the input buffer flushes mid-paste (a partial paste then decodes as individual keystrokes, the
  # exact bug this patch fixes). aleph wants paste-start/paste-end as SEPARATE events so its paste
  # buffer can collect the content between them and forward it as one block. deps/ is gitignored, so
  # this self-heals the patch onto the dep source before compile (idempotent — a
  # "Bracketed-paste markers" comment marker). It removes the legacy parse_one clause (which would
  # otherwise shadow the new clauses) and inserts 200/201 clauses at the head of
  # parse_csi_tilde_one/1's case — the SAME function the kitty CSI-u patch extends. The host-side
  # bracketed-paste mode that PRODUCES these sequences is enabled in Console.Cockpit itself
  # (\e[?2004h — no dep patch); this only teaches the parser to decode the markers.
  @paste_parser Path.join([
                  Mix.Project.deps_path(),
                  "raxol_terminal",
                  "lib",
                  "raxol",
                  "terminal",
                  "ansi",
                  "input_parser.ex"
                ])

  # The bracketed-paste clauses inserted at the head of parse_csi_tilde_one/1's `case`. CSI-tilde
  # n=200/201 (terminator ~) — the markers ghostty wraps a paste in once aleph enables \e[?2004h on
  # the host tty. Surfaced as distinct paste-start/paste-end events (data.phase) so the cockpit's
  # paste buffer collects the content between them and forwards it as one block.
  @paste_csi_tilde_clauses """
      # Bracketed-paste markers (CSI-tilde n=200/201): aleph enables \\e[?2004h on the host tty, so
      # ghostty wraps a paste in \\e[200~…\\e[201~. Surfaced as distinct paste-start/paste-end events
      # so the cockpit's paste buffer collects the content between them and forwards it as one block.
      {[200], ?~, rest} ->
        {%Event{type: :paste, data: %{phase: :start}}, rest}

      {[201], ?~, rest} ->
        {%Event{type: :paste, data: %{phase: :end}}, rest}

  """

  # The legacy parse_one/1 bracketed-paste clause this patch removes (it would shadow the new
  # clauses — \e[200~ is matched in parse_one before it ever reaches parse_csi_tilde_one). Replaced
  # with the empty string; the trailing blank line is consumed so no double blank is left behind.
  @legacy_paste_clause """
    # Bracketed paste: ESC [ 200 ~
    defp parse_one(<<27, 91, 50, 48, 48, 126, rest::binary>>) do
      case :binary.split(rest, <<27, 91, 50, 48, 49, 126>>) do
        [pasted, remaining] ->
          {%Event{type: :paste, data: %{text: pasted}}, remaining}

        [_no_end] ->
          {%Event{type: :paste, data: %{text: rest}}, <<>>}
      end
    end

  """

  defp ensure_raxol_paste_parser(_args) do
    path = @paste_parser

    case File.read(path) do
      {:ok, src} ->
        if String.contains?(src, "Bracketed-paste markers") do
          :ok
        else
          # Each anchor is checked individually and a miss RAISES: a soft warning here would let a
          # raxol bump ship a green build with an unpatched (or half-patched) parser, silently
          # regressing bracketed paste back to per-keystroke decoding. Nothing is written unless both
          # replacements landed.
          patched =
            src
            |> replace_anchor!(
              "legacy bracketed-paste parse_one clause",
              @legacy_paste_clause,
              ""
            )
            |> replace_anchor!(
              "parse_csi_tilde_one case head",
              "  defp parse_csi_tilde_one(data) do\n    case parse_csi_params(data) do\n",
              "  defp parse_csi_tilde_one(data) do\n    case parse_csi_params(data) do\n" <>
                @paste_csi_tilde_clauses
            )

          File.write!(path, patched)
          Mix.shell().info("[aleph] patched raxol InputParser with bracketed-paste markers")

          # `mix compile` won't recompile an already-built hex dep, so without this the parser
          # would keep the stale beam (the legacy single-:paste handler) while the source carries
          # the new clauses. Force recompile now; runs once (idempotent), not every build.
          Mix.Task.rerun("deps.compile", ["raxol_terminal", "--force"])
        end

      _ ->
        :ok
    end
  end

  defp replace_anchor!(src, name, anchor, replacement) do
    patched = String.replace(src, anchor, replacement)

    if patched == src do
      Mix.raise(
        "[aleph] dep source patch: the #{name} anchor no longer matches — raxol_terminal " <>
          "restructured it (version bump?). Update the anchor in mix.exs before building, or the " <>
          "patch silently regresses (Kitty shift+enter, or the tb_resize/0 size refresh)."
      )
    end

    patched
  end

  # --- Defect #3: tb_resize/0 (see the @termbox_cflags comment). Two source patches, both
  # idempotent and anchor-checked. The C side (below) is applied post-compile in
  # ensure_termbox_nif/1; the .ex stub is applied pre-compile in ensure_termbox_resize_stub/1.

  # Appended to termbox_impl.c (the TB_IMPL translation unit, so the static refreshers `global`,
  # `update_term_size`, `resize_cellbufs` are in scope). Non-static, so termbox2_nif.c can link it.
  @termbox_resize_impl """

  // aleph patch (defect #3): public size-refresh entry point (termbox2 only re-learns size in its
  // poll path, which aleph never calls). Only reallocates via resize_cellbufs (screen-clearing)
  // when the size actually changed. Returns TB_OK / a TB_ERR_* code.
  int tb_resize(void) {
      int old_w = global.width, old_h = global.height;
      int rv = update_term_size();
      if (rv != TB_OK) return rv;
      if (global.width == old_w && global.height == old_h) return TB_OK;
      return resize_cellbufs();
  }
  """

  # Inserted before the nif_funcs[] table in termbox2_nif.c (the wrapper TU — it sees only the
  # public termbox2.h, so tb_resize is forward-declared here).
  @termbox_resize_wrapper """
  // aleph patch (defect #3): tb_resize/0 — re-sync termbox's cached terminal size (impl in
  // termbox_impl.c). Forward-declared: this TU includes termbox2.h without TB_IMPL.
  int tb_resize(void);
  static ERL_NIF_TERM nif_tb_resize(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
  {
    int result = tb_resize();
    return enif_make_int(env, result);
  }

  """

  # Appended after the tb_height/0 stub in termbox2_nif.ex (the atom-named `:termbox2_nif` module).
  @termbox_resize_stub """

    @doc \"\"\"
    Re-sync termbox's cached terminal size after a window resize (aleph patch — see mix.exs
    defect #3). Returns TB_OK (0) or a TB_ERR_* code. Safe only after tb_init/0.
    \"\"\"
    def tb_resize, do: :erlang.nif_error(:nif_not_loaded)
  """

  @termbox_nif_ex Path.join([
                    Mix.Project.deps_path(),
                    "raxol_terminal",
                    "lib",
                    "termbox2_nif",
                    "lib",
                    "termbox2_nif.ex"
                  ])

  # Patch the C source with tb_resize (impl + NIF wrapper + funcs-table entry). Returns true iff it
  # just applied the patch (so ensure_termbox_nif/1 forces a .so rebuild). Idempotent: a second run
  # sees `nif_tb_resize` already present and no-ops.
  defp patch_termbox_resize(c_src) do
    impl = Path.join(c_src, "termbox_impl.c")
    nif = Path.join(c_src, "termbox2_nif.c")

    cond do
      not (File.exists?(impl) and File.exists?(nif)) ->
        false

      String.contains?(File.read!(nif), "nif_tb_resize") ->
        false

      true ->
        File.write!(impl, File.read!(impl) <> @termbox_resize_impl)

        nif_src =
          nif
          |> File.read!()
          |> replace_anchor!(
            "nif_funcs table",
            "static ErlNifFunc nif_funcs[] = {",
            @termbox_resize_wrapper <> "static ErlNifFunc nif_funcs[] = {"
          )
          |> replace_anchor!(
            "nif_funcs tb_set_position entry",
            "{\"tb_set_position\", 2, tb_set_position, 0}};",
            ~s({"tb_set_position", 2, tb_set_position, 0},\n    {"tb_resize", 0, nif_tb_resize, 0}};)
          )

        File.write!(nif, nif_src)
        Mix.shell().info("[aleph] patched termbox2 NIF with tb_resize/0")
        true
    end
  end

  # Patch the Elixir stub into termbox2_nif.ex before `compile`, so the recompiled dep module
  # exports tb_resize/0 (the NIF binds to it once the rebuilt .so loads). Idempotent + anchored.
  defp ensure_termbox_resize_stub(_args) do
    case File.read(@termbox_nif_ex) do
      {:ok, src} ->
        if String.contains?(src, "def tb_resize") do
          :ok
        else
          patched =
            replace_anchor!(
              src,
              "tb_height/0 stub",
              "  def tb_height, do: :erlang.nif_error(:nif_not_loaded)",
              "  def tb_height, do: :erlang.nif_error(:nif_not_loaded)\n" <> @termbox_resize_stub
            )

          File.write!(@termbox_nif_ex, patched)
          Mix.shell().info("[aleph] patched termbox2_nif.ex with tb_resize/0 stub")

          # `mix compile` won't recompile an already-built hex dep, so without this the module
          # would lack the stub while the rebuilt .so declares the NIF — load_nif then bad_libs
          # the WHOLE NIF. Force recompile now; runs once (idempotent), not every build.
          Mix.Task.rerun("deps.compile", ["raxol_terminal", "--force"])
        end

      _ ->
        :ok
    end
  end

  # Recompile the NIF so both translation units carry a 64-bit colour type. `make CFLAGS=...` on
  # the command line overrides the Makefile's `CFLAGS ?=`. Returns true iff a rebuild happened.
  defp rebuild_termbox_truecolor(c_src, force?) do
    marker = Path.join(c_src, ".aleph_truecolor")
    so = Path.join(c_src, "termbox2_nif.so")

    if not force? and truecolor_current?(marker, so) do
      false
    else
      Mix.shell().info("[aleph] rebuilding termbox2_nif.so with 24-bit truecolor…")
      System.cmd("make", ["clean"], cd: c_src, stderr_to_stdout: true)

      {out, status} =
        System.cmd("make", ["CFLAGS=#{@termbox_cflags}"], cd: c_src, stderr_to_stdout: true)

      if status == 0 do
        File.write!(marker, "TB_OPT_ATTR_W=64 — full 24-bit colour reaches tb_set_cell\n")
        true
      else
        Mix.shell().error("[aleph] termbox2 truecolor rebuild failed:\n#{out}")
        false
      end
    end
  end

  # Fresh when our marker is at least as new as the built .so; a dep rebuild bumps the .so past it.
  defp truecolor_current?(marker, so) do
    with {:ok, %{mtime: marker_at}} <- File.stat(marker, time: :posix),
         {:ok, %{mtime: so_at}} <- File.stat(so, time: :posix) do
      marker_at >= so_at
    else
      _ -> false
    end
  end

  defp install_termbox_nif(force?) do
    dest_dir = Path.join([Mix.Project.build_path(), "lib", "raxol_terminal", "priv"])
    dest = Path.join(dest_dir, "termbox2_nif.so")

    if force? or not File.exists?(dest) do
      src =
        [
          ["lib", "termbox2_nif", "priv", "termbox2_nif.so"],
          ["lib", "termbox2_nif", "c_src", "termbox2_nif.so"]
        ]
        |> Enum.map(&Path.join([Mix.Project.deps_path(), "raxol_terminal" | &1]))
        |> Enum.find(&File.exists?/1)

      case src do
        nil ->
          Mix.shell().error(
            "[aleph] termbox2_nif.so not found in deps — run " <>
              "`mise exec -- mix deps.compile raxol_terminal --force`"
          )

        src ->
          File.mkdir_p!(dest_dir)
          File.cp!(src, dest)
          Mix.shell().info("[aleph] installed termbox2_nif.so -> #{Path.relative_to_cwd(dest)}")
      end
    end
  end

  defp deps do
    [
      # A live runtime dep: aleph boots funes' OTP app (PubSub + Repo) and subscribes to
      # the Bus (§6). funes never depends on aleph — the boundary is one-directional. Because
      # a dependency's own `config/*.exs` is NOT evaluated when aleph is the root app, aleph
      # supplies funes' Repo config itself (config/config.exs + config/runtime.exs).
      {:server, path: "../server"},
      # Compile-time module-boundary checks (lib/aleph.ex). runtime: false — pure tooling.
      {:boundary, "~> 0.10", runtime: false},
      # The disciplined subset of the Raxol family, NOT the full `raxol` umbrella (which
      # drags in payments/earn/mcp/sensor). `raxol_terminal` = screen buffers + ANSI +
      # input + the termbox2 driver; `raxol_core` = the infra behaviours it sits on (§3).
      {:raxol_terminal, "~> 2.6"},
      {:raxol_core, "~> 2.6"},
      # The embedded REAL terminal for the center column (design §4): Ghostty's own VT engine
      # (libghostty-vt) + a PTY, as precompiled NIFs (x86_64/aarch64 Linux, aarch64 macOS — no Zig
      # toolchain). Spawn a session in a PTY, feed its bytes to the emulator, read the cell grid
      # back — a native terminal widget, NOT a captured-and-repainted view (which felt laggy).
      {:ghostty, "~> 0.4"},
      # One styling authority on mix format, same as funes.
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
