defmodule Server.Secrets do
  @moduledoc """
  A conservative secret scanner for the write path (total-recall slice B): it refuses to let the
  ledger store an obvious credential, so the durable memory — and the automated capture that will
  feed it — never becomes a place a leaked key lives.

  Deliberately PATTERN-based, not entropy-based: a generic high-entropy detector would flag commit
  SHAs, base64 blobs, and hex hashes — legitimate technical facts funes exists to remember. So only
  well-known, prefixed credential shapes match, keeping false positives near zero. `scan/1` returns
  `:ok` or `{:secret, label}`.
  """

  @patterns [
    {"AWS access key", ~r/\bAKIA[0-9A-Z]{16}\b/},
    {"API key (sk-)", ~r/\bsk-(?:ant-)?[A-Za-z0-9_-]{20,}/},
    {"GitHub token", ~r/\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b/},
    {"GitHub fine-grained token", ~r/\bgithub_pat_[A-Za-z0-9_]{22,}/},
    {"Google API key", ~r/\bAIza[0-9A-Za-z_-]{35}\b/},
    {"Slack token", ~r/\bxox[baprs]-[A-Za-z0-9-]{10,}/},
    {"private key", ~r/-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----/}
  ]

  @spec scan(String.t() | nil) :: :ok | {:secret, String.t()}
  def scan(nil), do: :ok

  def scan(text) when is_binary(text) do
    Enum.find_value(@patterns, :ok, fn {label, re} ->
      if Regex.match?(re, text), do: {:secret, label}
    end)
  end
end
