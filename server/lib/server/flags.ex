defmodule Server.Flags do
  @moduledoc """
  The server's feature flags (`fun_with_flags`): a step that lands dark ships behind one, off, and
  is turned on when its track ships. Toggles live in `fun_with_flags_toggles` on the store's
  Postgres; a flip busts every node's cache over `Server.PubSub`, so nothing restarts.

  Only the flags named here exist: a name outside them is refused, so a typo never makes a flag
  nobody reads. Every one is in the office snapshot (`office/0`), the only place the office reads
  them.
  """

  # :build_mode — the office TUI's `B` (floor step 3), off until the life room ships
  @known [:build_mode]

  @spec enabled?(atom()) :: boolean()
  def enabled?(flag) when flag in @known, do: FunWithFlags.enabled?(flag)

  @doc "Every flag by name, on or off — the office snapshot's `flags`."
  @spec office() :: %{atom() => boolean()}
  def office, do: Map.new(@known, &{&1, enabled?(&1)})

  @doc "Turn the flag named `name` on or off for everyone."
  @spec set(String.t(), boolean()) :: {:ok, %{name: atom(), enabled: boolean()}} | {:error, String.t()}
  def set(name, on?) when is_binary(name) and is_boolean(on?) do
    case Enum.find(@known, &(Atom.to_string(&1) == name)) do
      nil ->
        {:error, "no flag named #{name} (known: #{Enum.join(@known, ", ")})"}

      flag ->
        {:ok, enabled} = if on?, do: FunWithFlags.enable(flag), else: FunWithFlags.disable(flag)
        {:ok, %{name: flag, enabled: enabled}}
    end
  end
end
