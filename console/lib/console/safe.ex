defmodule Console.Safe do
  @moduledoc """
  The cockpit is an unsupervised TTY GenServer: a raise or exit in any callback kills the frame,
  silently, under the alt-screen. Every reach into server, tmux or the Sessions registry that can
  fail degrades through here instead.

    * `logged/3` / `read/3` — log to the crash log and yield a fallback. The per-frame render reads
      use this: a bug still surfaces in the log while the rest of the frame paints.
    * `call/1` — `{:ok, value}` or `{:error, reason}`, for a verb whose failure the operator should
      see (a footer flash, `describe/1`).
    * `value/2` — the quiet fallback, for a lookup where a miss is already an answer.

  All three trap a raise AND an exit/throw (a downed server GenServer reaches the cockpit as an
  exit, not an exception).
  """

  @type reason :: Exception.t() | {:exit | :throw, term()}

  @doc "Run `fun`; a raise/exit/throw becomes `{:error, reason}`."
  @spec call((-> term())) :: {:ok, term()} | {:error, reason()}
  def call(fun) do
    {:ok, fun.()}
  rescue
    e -> {:error, e}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  @doc "Run `fun`; a raise/exit/throw yields `fallback`, quietly."
  @spec value((-> term()), term()) :: term()
  def value(fun, fallback) do
    fun.()
  rescue
    _ -> fallback
  catch
    _, _ -> fallback
  end

  @doc "Run `fun`; a raise/exit/throw is appended to the crash log under `title` and yields `fallback`."
  @spec logged(String.t(), term(), (-> term())) :: term()
  def logged(title, fallback, fun) do
    fun.()
  rescue
    e ->
      Console.CrashLog.append(title, Exception.format(:error, e, __STACKTRACE__))
      fallback
  catch
    kind, reason ->
      Console.CrashLog.append(title, Exception.format(kind, reason, __STACKTRACE__))
      fallback
  end

  @doc """
  Guard a cockpit READ (the per-frame server/tmux assembly): a raise OR an exit degrades that one
  read to `fallback` with a `read error: <label>` crash-log entry, so one bad read renders as its
  panel's quiet state instead of taking the whole cockpit down.
  """
  @spec read(atom(), term(), (-> term())) :: term()
  def read(label, fallback, fun), do: logged("read error: #{label}", fallback, fun)

  @doc """
  Run a verb that yields the next cockpit state; a raise/exit becomes a `<label> failed: …` footer
  flash on the state it was handed — a server hiccup never kills the cockpit.
  """
  @spec flash_on_error(map(), String.t(), (-> map())) :: map()
  def flash_on_error(state, label, fun) do
    case call(fun) do
      {:ok, next} -> next
      {:error, reason} -> flash_failed(state, label, reason)
    end
  end

  @doc "The state with a `<label> failed: <reason>` flash."
  @spec flash_failed(map(), String.t(), reason()) :: map()
  def flash_failed(state, label, reason), do: %{state | flash: "#{label} failed: #{describe(reason)}"}

  @doc "The operator-facing text of a `call/1` failure: the exception's message, or the exit/throw reason."
  @spec describe(reason()) :: String.t()
  def describe({kind, reason}) when kind in [:exit, :throw], do: inspect(reason)
  def describe(e) when is_exception(e), do: Exception.message(e)
  def describe(other), do: inspect(other)
end
