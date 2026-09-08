defmodule Server.MCP.Spawn do
  @moduledoc """
  Handing a harness its server identity (pi doc §2d). A launcher — `server:spawn`,
  `server:claude`, the `pi:*` model tasks — opens a fresh thread or JOINS an existing
  one, staffs an agent, and lets the harness authenticate to the sovereign channel.

  A token is a stateless HMAC under the world's secret (`Server.MCP.Secret`, the file
  beside the db), so it must be minted on the SAME world that validates it — a token
  minted against another db's secret 401s. So the launchers reach this through
  `bin/server rpc` into the LIVE service node, OR through the loopback `POST /mint`
  endpoint (`Server.MCP.Gateway`) that any adapter on the same box hits per connect.

  Three doors onto the same core (`ensure/3`, which mints nothing):

    * `env/3` / `join/3` — ensure + mint + build the `export TLON_*` block (identity only:
      `TLON_MCP_URL`, `TLON_THREAD`, `TLON_AUTHOR`). NO `TLON_TOKEN` is frozen into the
      block — a frozen token strands a pane the moment the token model changes or the world
      secret regenerates. The adapter mints a fresh token per connect against the URL's
      origin (`POST /mint`), so identity is stable and format-agnostic. The `:token` in the
      return is kept for callers/tests that want a one-shot token, but it is not frozen into
      any pane's env.
    * `mint_for/2` — a FRESH token for an already-ensured (thread, agent), minted on
      demand. This is what `POST /mint` calls and what Claude Code's `headersHelper` calls
      directly — so the token stays current across a server restart, a model change, or
      a secret regeneration.

  The launchers call `ensure` once (identity), and the adapter mints per connect.
  """
  alias Server.Channel
  alias Server.MCP.Tokens
  alias Server.Repo
  alias Server.Staff
  alias Server.Thread

  @typedoc "Open a fresh thread, or join an existing one by id."
  @type thread_ref :: {:open, String.t()} | {:join, integer() | String.t()}

  @doc """
  The spawn-or-join core — mints NOTHING. Resolves `thread_ref` (open a fresh thread
  titled `title`, or join an existing thread by id), ensures the named agent (register
  if new), staffs the thread with it, and returns `{:ok, %{thread: t, agent: a}}`.

  `{:join, id}` on a missing thread returns `{:error, {:no_thread, id}}` — it never
  silently opens a new one, so a typo'd id fails loud instead of forking work.

  Options for a freshly-registered agent: `:mandate` (default "general"), `:engine`
  (default "local"). An existing agent keeps its own — server has no vendor in the
  design (§8), so `engine` is just a capability handle resolved elsewhere.

  `:assign` (default `true`) staffs the thread with `agent_name` (`Staff.assign/2`
  is single-slot — "a thread has 0..1 agent; assigning again replaces the previous
  agent"). Pass `assign: false` to ensure/mint identity for a NON-staffing rider on
  an already-led thread (e.g. a crew role like a reviewer) without evicting the
  thread's actual lead.
  """
  @spec ensure(thread_ref(), String.t(), keyword()) ::
          {:ok, %{thread: Thread.t(), agent: Server.Agent.t()}} | {:error, term()}
  def ensure(thread_ref, agent_name, opts \\ []) when is_binary(agent_name) do
    with {:ok, thread} <- resolve_thread(thread_ref, opts),
         {:ok, agent} <- ensure_agent(agent_name, opts),
         {:ok, thread} <- maybe_assign(thread, agent, opts) do
      {:ok, %{thread: thread, agent: agent}}
    end
  end

  @doc """
  Open a fresh thread titled `title`, ensure `agent_name`, mint a token, and build the
  `export TLON_*` block. Returns `{:ok, %{thread, agent, token, exports}}`. The static
  bearer path — the caller decides where the block goes (a pi pane's env, stdout).
  """
  @spec env(String.t(), String.t(), keyword()) ::
          {:ok, %{thread: Thread.t(), agent: Server.Agent.t(), token: String.t(), exports: String.t()}}
          | {:error, term()}
  def env(title, agent_name, opts \\ []) when is_binary(title), do: mint_and_export({:open, title}, agent_name, opts)

  @doc "Like `env/3`, but JOIN an existing thread by id instead of opening a fresh one."
  @spec join(integer() | String.t(), String.t(), keyword()) ::
          {:ok, %{thread: Thread.t(), agent: Server.Agent.t(), token: String.t(), exports: String.t()}}
          | {:error, term()}
  def join(thread_id, agent_name, opts \\ []), do: mint_and_export({:join, thread_id}, agent_name, opts)

  @doc """
  A fresh token for an EXISTING (thread, agent) — the Claude-Code `headersHelper` path,
  run on every connect. Both must already exist (the launcher ensured them at start);
  a missing thread is `{:error, {:no_thread, id}}`, a missing agent
  `{:error, {:no_agent, name}}` — never mint against a guess.
  """
  @spec mint_for(integer() | String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def mint_for(thread_id, agent_name) when is_binary(agent_name) do
    with {:ok, thread} <- resolve_thread({:join, thread_id}, []),
         {:agent, agent} when not is_nil(agent) <- {:agent, Staff.agent_by_name(agent_name)} do
      {:ok, Tokens.mint(thread, agent)}
    else
      {:agent, nil} -> {:error, {:no_agent, agent_name}}
      err -> err
    end
  end

  defp mint_and_export(thread_ref, agent_name, opts) do
    with {:ok, %{thread: thread, agent: agent}} <- ensure(thread_ref, agent_name, opts) do
      token = Tokens.mint(thread, agent)
      {:ok, %{thread: thread, agent: agent, token: token, exports: exports(thread, agent, token)}}
    end
  end

  defp resolve_thread({:open, title}, opts) do
    attrs = %{title: title}
    attrs = if scope = opts[:scope], do: Map.put(attrs, :scope, scope), else: attrs
    Channel.open_thread(attrs)
  end

  defp resolve_thread({:join, id}, _opts) do
    case Repo.get(Thread, id) do
      nil -> {:error, {:no_thread, id}}
      thread -> {:ok, thread}
    end
  end

  # `:assign` opt-out (default true, unchanged behavior for existing callers) — see `ensure/3` doc.
  defp maybe_assign(thread, agent, opts) do
    if Keyword.get(opts, :assign, true), do: Staff.assign(thread, agent), else: {:ok, thread}
  end

  defp ensure_agent(name, opts) do
    case Staff.agent_by_name(name) do
      nil ->
        Staff.register_agent(%{
          name: name,
          mandate: Keyword.get(opts, :mandate, "general"),
          engine: Keyword.get(opts, :engine, "local")
        })

      agent ->
        {:ok, agent}
    end
  end

  defp exports(thread, agent, _token) do
    # No TLON_TOKEN in the block: a frozen token strands the pane the moment the token
    # model changes or the world secret regenerates. The adapter mints a fresh token
    # per connect against this URL's origin (POST /mint), so identity travels as the
    # stable, format-agnostic (TLON_THREAD, TLON_AUTHOR, TLON_MCP_URL). The `:token`
    # in this function's return is kept for callers/tests that want a one-shot token,
    # but it is not frozen into any pane's env.
    port = Application.get_env(:server, :mcp_port, 4040)

    """
    export TLON_MCP_URL="http://127.0.0.1:#{port}/mcp"
    export TLON_THREAD="#{thread.id}"
    export TLON_AUTHOR="#{agent.name}"\
    """ <> cwd_export(thread)
  end

  # The thread's worktree, ensured now, for the boot script to cd into — a coworker never writes in
  # the main tree (2026-09-08). A workspace with no repo exports nothing; the pane starts wherever.
  defp cwd_export(thread) do
    case Server.worktree_for_thread(thread) do
      {:ok, path} -> "\nexport TLON_CWD=\"#{path}\""
      {:error, _} -> ""
    end
  end
end
