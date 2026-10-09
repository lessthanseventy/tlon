defmodule Server.TestArtifacts do
  @moduledoc """
  `Server.Workline.Artifacts` stand-ins for any suite: `Missing` owes every stage's artifact,
  `Present` has them all. Pass one as `artifacts:` to `Server.Workline` or its continuation.
  """

  defmodule Missing do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, _requirement), do: {:error, "work/x/plan.md is not committed"}
  end

  defmodule Present do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, _requirement), do: {:ok, "committed"}
  end
end
