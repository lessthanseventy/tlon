defmodule Console.Orchestrator.Router do
  @moduledoc """
  The pure intent-router behind the tertius command line (Slice 1). Natural-language meta-intent
  → a dispatch action tuple; `Console.Orchestrator` executes it and echoes a receipt. Parsing
  only — handle→thread and id resolution happen at dispatch, so this stays a pure function the
  grammar can be pinned against without a live channel.

  Grammar (case-insensitive prefix; the body keeps its original case):
    * `tell <handle> <body>`        → `{:post, handle, body}`
    * `remember <x>` / `note <x>`   → `{:note, x}`
    * `file a ticket <x>` / `ticket[:] <x>` → `{:ticket, x}`
    * `spike <x>`  → `{:open, "build", x}`   ·  `explore <x>` → `{:open, nil, x}`  ·  `build <x>` → `{:open, "intent", x}`
    * `approve [#]N`                → `{:approve, N}`
    * `…blocked…` → `{:query, :blocked}`  ·  `…free…`/`roster` → `{:query, :roster}`
    * anything else                 → `{:chat, text}`  (handed to the tertius agent, v2)
  """

  @prefix_routes [
    {"tell ", :tell},
    {"remember ", :note},
    {"note ", :note},
    {"file a ticket ", :ticket},
    {"ticket: ", :ticket},
    {"ticket ", :ticket},
    {"spike ", {:open, "build"}},
    {"explore ", {:open, nil}},
    {"build ", {:open, "intent"}}
  ]

  @doc """
  Route a typed line to a dispatch action. Pure.
  """
  def route(text) do
    orig = String.trim(text)
    down = String.downcase(orig)
    prefixed(orig, down) || unprefixed(orig, down)
  end

  # First matching prefix wins, so a longer prefix sits above a shorter one it starts with.
  defp prefixed(orig, down) do
    Enum.find_value(@prefix_routes, fn {prefix, kind} ->
      if body = after_prefix(orig, down, prefix), do: prefixed_action(kind, body, orig)
    end)
  end

  defp prefixed_action(:tell, body, orig), do: tell(body, orig)
  defp prefixed_action(:note, body, _orig), do: {:note, body}
  defp prefixed_action(:ticket, body, _orig), do: {:ticket, body}
  defp prefixed_action({:open, kind}, body, _orig), do: {:open, kind, body}

  defp unprefixed(orig, down) do
    cond do
      n = approve_id(orig) -> {:approve, n}
      String.contains?(down, "blocked") -> {:query, :blocked}
      String.contains?(down, "free") or down == "roster" -> {:query, :roster}
      true -> {:chat, orig}
    end
  end

  # The trimmed remainder after a case-insensitively-matched prefix, or nil. ASCII prefixes, so
  # downcasing never changes byte length — the original body is `binary_part` at the same offset.
  defp after_prefix(orig, down, prefix) do
    if String.starts_with?(down, prefix) do
      String.trim(binary_part(orig, byte_size(prefix), byte_size(orig) - byte_size(prefix)))
    end
  end

  # `tell <handle> <body>` needs both a handle and a message; handle-only falls to chat.
  defp tell(body, orig) do
    case String.split(body, " ", parts: 2) do
      [handle, message] when message != "" -> {:post, String.trim_leading(handle, "@"), String.trim(message)}
      _ -> {:chat, orig}
    end
  end

  defp approve_id(orig) do
    case Regex.run(~r/^approve\s+#?(\d+)$/i, orig) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end
end
