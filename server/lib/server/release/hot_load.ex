defmodule Server.Release.HotLoad do
  @moduledoc """
  Run a freshly built release without restarting: compare the modules the node has loaded with the
  beams the build left on disk, and swap the ones that differ with `:code.atomic_load/1`, all or
  none. No relups and no `code_change`, so anything that can't be swapped this simply says why and
  the caller restarts instead. When unsure, it restarts.

  It refuses when:

    * the commits touch what a swap can't carry: migrations and assets (`server/priv`), config,
      dependencies, the toolchain (`@needs_boot`);
    * a changed module is a long-lived process or part of the boot (`@process_behaviours`): its
      state may not fit the new code;
    * a module was removed, or a consolidated protocol changed;
    * a process still runs a changed module's previous version, which loading again would kill.

  A process running old code otherwise carries on and moves over at its next fully-qualified call.
  What this can't see: an anonymous function of an old version kept in ETS or `:persistent_term`
  raises `:badfun` when called once that version is purged, and a long-lived process may hold a
  struct from before the swap.
  """
  require Logger

  @needs_boot ~w(server/priv server/config server/rel server/mix.exs server/mix.lock mise.toml)

  @process_behaviours [
    GenServer,
    :gen_server,
    :gen_statem,
    :gen_event,
    Supervisor,
    :supervisor,
    DynamicSupervisor,
    Application,
    :application,
    Phoenix.Endpoint,
    Phoenix.LiveView,
    Ecto.Repo,
    Anubis.Server
  ]

  @doc """
  Bring the node onto the release built for `to`, coming from `from`. `{:ok, modules}` is what was
  swapped (possibly nothing); `{:restart, why}` left the node as it was. `opts`: `root:` the
  checkout, `ebin:` and `consolidated:` the built beams' directories.
  """
  @spec run(String.t() | nil, String.t() | nil, keyword()) :: {:ok, [module()]} | {:restart, String.t()}
  def run(from, to, opts \\ []) do
    ebin = Keyword.get_lazy(opts, :ebin, fn -> Path.join(:code.lib_dir(:server), "ebin") end)
    consolidated = Keyword.get_lazy(opts, :consolidated, fn -> Path.dirname(:code.which(Enumerable)) end)

    with :ok <- paths(opts[:root] || Server.Profiles.tlon_root(), from, to),
         :ok <- same_protocols(consolidated),
         :ok <- nothing_removed(ebin),
         changed = changed(ebin),
         :ok <- no_processes(changed),
         :ok <- purge(changed),
         :ok <- load(changed) do
      modules = Enum.map(changed, & &1.module)
      Logger.info("hot load: #{length(modules)} modules from #{inspect(from)} to #{inspect(to)}")
      {:ok, modules}
    end
  end

  defp paths(root, from, to) when is_binary(from) and is_binary(to) do
    case Server.Git.cmd(root, ["diff", "--name-only", from, to, "--" | @needs_boot]) do
      {"", 0} ->
        :ok

      {out, 0} ->
        {:restart, "needs a boot: #{out |> String.split("\n", trim: true) |> Enum.take(3) |> Enum.join(", ")}"}

      {_, _} ->
        {:restart, "can't read what changed from #{from} to #{to}"}
    end
  end

  defp paths(_root, from, to), do: {:restart, "no commits to compare (#{inspect(from)}..#{inspect(to)})"}

  defp same_protocols(dir) do
    case Enum.filter(beams(dir), &differs?/1) do
      [] -> :ok
      [b | _] -> {:restart, "a consolidated protocol changed: #{inspect(b.module)}"}
    end
  end

  defp nothing_removed(dir) do
    on_disk = MapSet.new(beams(dir), & &1.module)
    prefix = String.to_charlist(Path.expand(dir) <> "/")

    removed =
      for {module, file} <- :code.all_loaded(),
          is_list(file),
          List.starts_with?(file, prefix),
          module not in on_disk,
          do: module

    case removed do
      [] -> :ok
      [module | _] -> {:restart, "a module was removed: #{inspect(module)}"}
    end
  end

  defp changed(dir), do: Enum.filter(beams(dir), &differs?/1)

  defp no_processes(changed) do
    case Enum.find(changed, &process?/1) do
      nil -> :ok
      b -> {:restart, "a process module changed: #{inspect(b.module)}"}
    end
  end

  defp purge(changed) do
    case Enum.find(changed, &(not :code.soft_purge(&1.module))) do
      nil -> :ok
      b -> {:restart, "a process still runs the previous version of #{inspect(b.module)}"}
    end
  end

  defp load(changed) do
    case :code.atomic_load(Enum.map(changed, &{&1.module, String.to_charlist(&1.path), &1.binary})) do
      :ok -> :ok
      {:error, why} -> {:restart, "the load was refused: #{inspect(why)}"}
    end
  end

  defp beams(dir) do
    for path <- Path.wildcard(Path.join(dir, "*.beam")) do
      binary = File.read!(path)
      {:ok, {module, md5}} = :beam_lib.md5(binary)
      %{module: module, path: Path.rootname(path), binary: binary, md5: md5}
    end
  end

  defp differs?(%{module: module, md5: md5}) do
    :code.is_loaded(module) == false or module.module_info(:md5) != md5
  end

  defp process?(%{binary: binary}) do
    {:ok, {_, [attributes: attributes]}} = :beam_lib.chunks(binary, [:attributes])
    declared = Keyword.get_values(attributes, :behaviour) ++ Keyword.get_values(attributes, :behavior)
    Enum.any?(List.flatten(declared), &(&1 in @process_behaviours))
  end
end
