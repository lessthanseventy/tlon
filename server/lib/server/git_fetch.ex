defmodule Server.GitFetch do
  @moduledoc """
  Fetches of origin share one `.git` (landings, KeepUp, the release PM): the fetch that loses the race
  on a ref's lock fails "cannot lock ref" though the ref is fine, and succeeds as a no-op once the
  winner is done. `retry/2` runs a fetch that answers `{output, exit}` again on exactly that failure.
  """

  @tries 3

  @doc "Run `fetch`, retrying a lost ref lock up to #{@tries} times, `backoff` ms times the try between."
  @spec retry((-> {String.t(), non_neg_integer()}), pos_integer()) :: {String.t(), non_neg_integer()}
  def retry(fetch, backoff \\ 250), do: retry(fetch, backoff, 1)

  defp retry(fetch, backoff, try) do
    case fetch.() do
      {out, code} = failed when code != 0 and try < @tries ->
        if out =~ "cannot lock ref" do
          Process.sleep(backoff * try)
          retry(fetch, backoff, try + 1)
        else
          failed
        end

      done ->
        done
    end
  end
end
