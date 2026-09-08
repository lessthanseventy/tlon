defmodule Console.Server.Facade do
  @moduledoc """
  `use Console.Server.Facade, target: Server.Channel` mirrors every public function of the
  target at compile time as `def f(args...), do: Console.Backend.call(target, :f, [args...])`.
  Mirroring rather than hand-listing keeps the facade honest as the server's contexts grow: a
  new context function is reachable the moment it exists, and a renamed one fails to compile
  at its call site. `local: [f: arity]` names pure helpers that never need the server (they
  are `defdelegate`d and stay in-node even under the remote backend).
  """

  defmacro __using__(opts) do
    target = Macro.expand(Keyword.fetch!(opts, :target), __CALLER__)
    local = Keyword.get(opts, :local, [])
    Code.ensure_compiled!(target)

    defs =
      for {f, a} <- target.__info__(:functions),
          not String.starts_with?(Atom.to_string(f), "__") do
        args = Macro.generate_arguments(a, __MODULE__)

        if {f, a} in local do
          quote do
            defdelegate unquote(f)(unquote_splicing(args)), to: unquote(target)
          end
        else
          quote do
            def unquote(f)(unquote_splicing(args)),
              do: Console.Backend.call(unquote(target), unquote(f), [unquote_splicing(args)])
          end
        end
      end

    quote do
      @moduledoc false
      @doc false
      def __target__, do: unquote(target)
      unquote(defs)
    end
  end
end
