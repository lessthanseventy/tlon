defmodule Server.Secrets do
  @moduledoc """
  A conservative secret scanner for the write path: it refuses to let the ledger store an obvious
  credential, so the durable memory — and the automated capture that feeds it — never becomes a
  place a leaked key lives. `validate_no_secret/2` is the changeset validator every FTS-indexed,
  searchable text column (a fact's text, a message's body) runs.

  Deliberately PATTERN-based, not entropy-based: a generic high-entropy detector would flag commit
  SHAs, base64 blobs, and hex hashes — legitimate technical facts server exists to remember. So only
  well-known, prefixed credential shapes match, keeping false positives near zero. `scan/1` returns
  `:ok` or `{:secret, label}`.
  """
  import Ecto.Changeset, only: [add_error: 3, get_field: 2]

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

  @doc "Refuse a changeset whose `field` carries an obvious credential — a changeset error, so it rides the same `{:error, changeset}` path as any invalid write."
  @spec validate_no_secret(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_no_secret(changeset, field) do
    case scan(get_field(changeset, field)) do
      :ok -> changeset
      {:secret, label} -> add_error(changeset, field, "looks like a secret (#{label}); tlon does not store credentials")
    end
  end
end
