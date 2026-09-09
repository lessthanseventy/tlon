defmodule Console.Mention do
  @moduledoc """
  @-mention routing — the Tlön coworkers share one thread and address each other by name. A server
  message that `@`-names a coworker wakes it by arriving as a turn in its tmux window (the Cockpit
  does the `tmux send-keys`; this module only DECIDES who to wake and what to say). Pure, so it tests
  without a TTY or a live tmux.

  The handle → window mapping (`coworkers/1`) is the one piece of structural knowledge here — it is
  DERIVED from the active workspace's roster (`Console.Space`), not a compile-time table: each roster entry
  named `n` is handle AND window `n` (UX slice 5 retired the `-machine` suffix), matching the window name the Cockpit's
  roster-driven spawn code creates (C2.3). Every call here that resolves handles takes the roster as
  an explicit arg — callers source it from `Space.fetch/1`/`Space.first_workspace/0` (server-down/no-workspace
  → `[]`, no handles resolve, nobody is woken).

  ## Experiment knobs (env, off by default — see docs/tlon-experiments)

    * `TLON_MENTION_LABEL=anon` labels the injected turn's sender as "someone" instead of its handle,
      for the "does the argument survive without the personas" run. NOTE: server still records the
      true author, so pair it with a prompt telling them to answer the injected turn, not re-read the
      thread.
  """

  alias Console.Crew

  @doc """
  The active handle → window map for a BENCH (`Server.Coworker` seats) — each name maps to itself,
  because handle and window are the same string since the `-machine` suffix retired (UX slice 5).
  The map survives as the "is this one of ours?" lookup every resolve does.
  """
  @spec coworkers([Server.Coworker.t()]) :: %{String.t() => String.t()}
  def coworkers(bench \\ []), do: Map.new(bench, &{&1.name, &1.name})

  @doc "The {handle, window} pairs @-mentioned in `body` (deduped, first-seen order), resolved against `roster`."
  @spec mentions(String.t() | nil, [map()]) :: [{String.t(), String.t()}]
  def mentions(body, roster \\ [])
  def mentions(nil, _roster), do: []

  def mentions(body, roster) do
    cw = coworkers(roster)

    ~r/@([\w-]+)/
    |> Regex.scan(body, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(fn handle ->
      case Map.get(cw, handle) do
        nil -> []
        window -> [{handle, window}]
      end
    end)
  end

  @doc """
  The injection turns for a posted message. With an explicit coworker `@`-mention, wakes each
  mentioned coworker (except the author's own window — the loop guard). With NO coworker mention,
  falls back to `opts[:lead]` — the thread's staffed lead coworker — so a bare operator reply
  still reaches someone. Each turn is `{window_name, one_line_text}`. `roster` resolves handles
  (see `coworkers/1`) — server-down/no-workspace callers pass `[]`, so nobody is woken.

  `opts[:staffed_window]` (e.g. `"t9"`) redirects the lead onto its OWN per-thread window: on a
  staffed thread the lead coworker runs in a `t<id>` window, not the standing handle→window
  slot, so any target that resolves to the lead's standing window is rewritten onto it. Without it,
  a staffed thread's turns would wake the STANDING coworker instead of the session working THAT
  thread. The author-exclusion loop guard runs before the redirect (an agent's own post — its
  standing window — is dropped first), so the thread's own session never wakes itself.
  """
  @spec route(map(), keyword(), [map()]) :: [{String.t(), String.t()}]
  def route(row, opts \\ [], roster \\ [])

  def route(%{author: author, body: body, thread_id: tid}, opts, roster) do
    author_window = resolve(author, tid, roster)
    targets = mention_targets(body, opts[:lead], tid, roster)
    lead_window = opts[:lead] && resolve(opts[:lead], tid, roster)
    staffed = opts[:staffed_window]

    for_result =
      for window <- targets, window != author_window do
        {redirect(window, lead_window, staffed),
         "[tlon thread #{tid_str(tid)}] #{display_author(author)}: #{one_line(body)}"}
      end

    Enum.uniq(for_result)
  end

  def route(_, _, _), do: []

  # A handle → window: the roster-derived map, else a crew role's per-thread window (`r<tid>`), else
  # nil. Crew roles only resolve WITH a thread id — their window is per-thread, so a nil tid
  # (standing thread, general console) leaves a crew handle unresolved and it is simply not woken.
  defp resolve(handle, tid, roster) do
    cond do
      w = coworkers(roster)[handle] -> w
      role = tid && Crew.handle_role(handle) -> Crew.crew_window(role, tid)
      true -> nil
    end
  end

  # On a staffed thread the lead lives in its own `t<id>` window: rewrite any target that resolves
  # to the lead's standing window onto it. nil staffed_window (standing thread / no per-thread
  # session) = no redirect, the old handle→window target stands.
  defp redirect(window, lead_window, staffed) when is_binary(staffed) and window == lead_window, do: staffed
  defp redirect(window, _lead_window, _staffed), do: window

  # The windows to wake: the @-mentioned handles resolved for THIS thread, or — when none are
  # named — the thread's lead coworker's window (nil/unknown → []).
  defp mention_targets(body, lead, tid, roster) do
    case mentioned_handles(body) do
      [] -> lead |> lead_window(tid, roster) |> List.wrap()
      handles -> handles |> Enum.map(&resolve(&1, tid, roster)) |> Enum.reject(&is_nil/1)
    end
  end

  defp lead_window(nil, _tid, _roster), do: nil
  defp lead_window(handle, tid, roster), do: resolve(handle, tid, roster)

  # Every @handle token in the body (deduped, first-seen). Resolution to windows happens per-thread
  # in `resolve/3`; this stays purely lexical so crew handles are seen even though they are not in
  # the roster-derived `coworkers/1` map.
  defp mentioned_handles(body) do
    ~r/@([\w-]+)/
    |> Regex.scan(body, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp one_line(body), do: String.replace(body || "", "\n", " ")
  defp tid_str(nil), do: "?"
  defp tid_str(tid), do: "##{tid}"

  # The sender label on the injected turn — the real handle, or "someone" under TLON_MENTION_LABEL=anon.
  defp display_author(author) do
    case System.get_env("TLON_MENTION_LABEL") do
      "anon" -> "someone"
      _ -> author
    end
  end
end
