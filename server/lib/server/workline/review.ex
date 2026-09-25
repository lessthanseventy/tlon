defmodule Server.Workline.Review do
  @moduledoc """
  The reviewer's ONE door (worklines slice 3). The reviewer profile is structurally
  write-fenced (@reviewer_permissions denies write/edit + bash redirects), so review.md
  cannot be hand-written — `submit/3` is the single sanctioned path: server writes
  `work/<slug>/review.md` in the workline root and commits it. The fence stays airtight;
  a hook, not an advisory.
  """

  alias Server.Thread
  alias Server.Workline.Scribe

  @doc """
  Write + commit the review verdict. `{:ok, rel_path}`, `{:error, {:not_in_review, stage}}`
  outside the review stage, or `{:error, reason}` on a git fault. Identical resubmission is
  `{:ok, _}` — the artifact is already committed, which is the point.
  """
  def submit(%Thread{stage: "review", slug: slug} = thread, body, author) when is_binary(body) do
    Scribe.commit(thread, "review.md", body, "workline #{slug}: review verdict (submit_review by #{author})")
  end

  def submit(%Thread{stage: stage}, _body, _author), do: {:error, {:not_in_review, stage}}
end
