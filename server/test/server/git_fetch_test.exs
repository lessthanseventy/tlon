defmodule Server.GitFetchTest do
  # Fetches of origin in the one shared .git race for refs/remotes/origin/main's lock; the loser fails
  # "cannot lock ref" though the ref is fine, and succeeds as a no-op once the winner is done.
  use ExUnit.Case, async: true

  alias Server.GitFetch

  @lost "error: cannot lock ref 'refs/remotes/origin/main': is at 7d80359 but expected a2cc6ee"

  # a fetch stub that answers the given results in order, counting its calls
  defp stub(answers) do
    {:ok, agent} = Agent.start_link(fn -> answers end)
    fun = fn -> Agent.get_and_update(agent, fn [a | rest] -> {a, rest} end) end
    {fun, agent}
  end

  test "a fetch that loses the ref lock is retried and succeeds" do
    {fun, _} = stub([{@lost, 1}, {@lost, 1}, {"", 0}])
    assert {"", 0} = GitFetch.retry(fun, 1)
  end

  test "a lost lock is retried only so many times, then the last answer stands" do
    {fun, agent} = stub([{@lost, 1}, {@lost, 1}, {@lost, 1}, {"", 0}])
    assert {@lost, 1} = GitFetch.retry(fun, 1)
    assert [{"", 0}] = Agent.get(agent, & &1)
  end

  test "any other failure is not retried" do
    {fun, agent} = stub([{"fatal: could not read from remote", 128}, {"", 0}])
    assert {"fatal: could not read from remote", 128} = GitFetch.retry(fun, 1)
    assert [{"", 0}] = Agent.get(agent, & &1)
  end
end
