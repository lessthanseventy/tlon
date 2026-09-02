defmodule Console.StackTest do
  @moduledoc """
  Console.Stack.show/1 — the Commits pane's `Enter` detail. Driven against a throwaway git repo so
  the classification (the pure part the renderer colors off) is exercised end-to-end, not mocked.
  The rest of Stack shells out to git/df/nix and is left to the `verify` skill.
  """
  use ExUnit.Case, async: true

  alias Console.Stack

  setup do
    dir = Path.join(System.tmp_dir!(), "aleph-stack-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    git = fn args -> System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) end
    git.(["init", "-q"])
    git.(["config", "user.email", "t@t"])
    git.(["config", "user.name", "T"])
    File.write!(Path.join(dir, "a.txt"), "one\ntwo\n")
    git.(["add", "."])
    git.(["commit", "-q", "-m", "seed"])
    File.write!(Path.join(dir, "a.txt"), "one\nCHANGED\n")
    git.(["commit", "-qa", "-m", "change a line"])
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  describe "show/2" do
    test "classifies the commit's diff into file/hunk/add/del/meta/context lines", %{dir: dir} do
      lines = Stack.show("HEAD", dir)
      kinds = lines |> Enum.map(& &1.kind) |> Enum.uniq()

      assert :file in kinds
      assert :hunk in kinds
      assert :add in kinds
      assert :del in kinds
      # the commit header ("commit <sha>", "Author:", "Date:") lands as :meta
      assert :meta in kinds

      # the changed line is an add; the removed line a del
      assert Enum.any?(lines, &(&1.kind == :add and &1.text == "+CHANGED"))
      assert Enum.any?(lines, &(&1.kind == :del and &1.text == "-two"))
    end

    test "the +++/--- file markers are :meta, not add/del", %{dir: dir} do
      lines = Stack.show("HEAD", dir)
      assert Enum.any?(lines, &(&1.kind == :meta and String.starts_with?(&1.text, "+++")))
      assert Enum.any?(lines, &(&1.kind == :meta and String.starts_with?(&1.text, "---")))
    end

    test "a bad hash / nil / empty is [], never a crash", %{dir: dir} do
      assert Stack.show("nope-not-a-hash", dir) == []
      assert Stack.show(nil, dir) == []
      assert Stack.show("", dir) == []
    end
  end
end
