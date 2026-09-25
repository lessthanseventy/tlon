defmodule Server.SecretsTest do
  # Total-recall slice B — the write-path secret scanner. Pattern-based on purpose: it must NOT flag
  # the technical facts funes exists to remember (commit SHAs, hex, base64), only real credentials.
  use ExUnit.Case, async: true

  alias Server.Secrets

  doctest Server.Secrets

  test "passes ordinary technical text — no false positives on shas, hex, or prose" do
    assert Secrets.scan("exqlite sets busy_timeout via a NIF; see commit 3fa9c2e") == :ok
    assert Secrets.scan("the digest is a4f08c4b1db9e7f0c2a1 and the base64 is Zm9vYmFyYmF6") == :ok
    assert Secrets.scan("a task-oriented refactor of the sk-learn adapter") == :ok
    assert Secrets.scan(nil) == :ok
    assert Secrets.scan("") == :ok
  end

  test "flags an AWS access key id" do
    assert {:secret, "AWS access key"} = Secrets.scan("prod key AKIAIOSFODNN7EXAMPLE lives here")
  end

  test "flags OpenAI/Anthropic-style sk- keys" do
    assert {:secret, "API key (sk-)"} = Secrets.scan("OPENAI_API_KEY=sk-abcdefghij0123456789ABCDEF")
    assert {:secret, "API key (sk-)"} = Secrets.scan("sk-ant-api03-xxxxxxxxxxxxxxxxxxxxyy")
  end

  test "flags a GitHub token" do
    assert {:secret, "GitHub token"} = Secrets.scan("token: ghp_" <> String.duplicate("a", 36))
  end

  test "flags a private key header" do
    assert {:secret, "private key"} = Secrets.scan("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNz...")
  end

  test "flags a Slack token" do
    assert {:secret, "Slack token"} = Secrets.scan("xoxb-123456789012-abcdefghijklmnop")
  end
end
