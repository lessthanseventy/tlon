defmodule Console.SafeTest do
  use ExUnit.Case, async: false

  alias Console.Safe

  describe "call/1" do
    test "wraps a value" do
      assert Safe.call(fn -> 42 end) == {:ok, 42}
    end

    test "a raise is {:error, exception}; describe/1 gives its message" do
      assert {:error, %RuntimeError{} = e} = Safe.call(fn -> raise "kaboom" end)
      assert Safe.describe(e) == "kaboom"
    end

    test "an exit (a dead server GenServer) is {:error, {:exit, reason}}; describe/1 inspects it" do
      assert {:error, {:exit, reason}} = Safe.call(fn -> GenServer.call(:no_such_process_anywhere, :probe) end)
      assert Safe.describe({:exit, reason}) =~ "no_such_process_anywhere"
    end

    test "a throw is trapped too" do
      assert Safe.call(fn -> throw(:oops) end) == {:error, {:throw, :oops}}
    end
  end

  describe "value/2" do
    test "returns the value, or the fallback on raise/exit/throw" do
      assert Safe.value(fn -> :fine end, :fallback) == :fine
      assert Safe.value(fn -> raise "x" end, :fallback) == :fallback
      assert Safe.value(fn -> exit(:boom) end, :fallback) == :fallback
      assert Safe.value(fn -> throw(:t) end, :fallback) == :fallback
    end
  end

  describe "read/3 — the logged read guard" do
    test "returns the fun's value on success" do
      assert Safe.read(:crew, nil, fn -> %{coworkers: []} end) == %{coworkers: []}
    end

    test "degrades a raise to the fallback and logs it" do
      File.rm(Console.CrashLog.path())

      assert Safe.read(:crew, :fallback, fn -> raise "kaboom" end) == :fallback

      log = File.read!(Console.CrashLog.path())
      assert log =~ "read error: crew"
      assert log =~ "kaboom"
    end

    test "degrades an exit (a dead server GenServer) to the fallback and logs it" do
      File.rm(Console.CrashLog.path())

      read = fn -> GenServer.call(:no_such_process_anywhere, :probe) end
      assert Safe.read(:presence, %{}, read) == %{}

      assert File.read!(Console.CrashLog.path()) =~ "read error: presence"
    end

    test "degrades a throw to the fallback" do
      assert Safe.read(:stack, [], fn -> throw(:oops) end) == []
    end

    test "logged/3 titles the entry as given (the render backstop)" do
      File.rm(Console.CrashLog.path())
      assert Safe.logged("render error", :prev, fn -> raise "paint" end) == :prev
      assert File.read!(Console.CrashLog.path()) =~ "render error"
    end
  end
end
