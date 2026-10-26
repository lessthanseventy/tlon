defmodule Server.Office.NeedsPage do
  @moduledoc """
  Wakes Uqbar on its study when a need newly enters its group (`Needs.grouped/1`'s `uqbar`). Needs
  are derived when read, so there is no insert to hook: a per-minute pass (`Server.Jobs.Drain`)
  posts ONE `tlon` message per workspace naming the keys not yet paged. "Paged" is that message's
  `payload["need_page"]`, no older than the item, so it survives a restart. Waits while Uqbar is
  mid-turn and `@gap_s` after its last page; the keys stay unpaged, so the next page carries them.
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.Message
  alias Server.Office.Needs
  alias Server.Repo

  @gap_s 300
  @listed 20

  @doc "Page each workspace's Uqbar for its newly unrouted needs. `:ok`."
  def run(now \\ DateTime.utc_now()) do
    if Server.OperatorConfig.setting("uqbar_routing") do
      now
      |> Needs.grouped()
      |> Map.fetch!(:uqbar)
      |> Enum.reject(&is_nil(&1.workspace_id))
      |> Enum.group_by(& &1.workspace_id)
      |> Enum.each(fn {ws, items} -> page(ws, items, now) end)
    else
      :ok
    end
  end

  defp page(ws, items, now) do
    with {:ok, study} <- Server.Outside.study(ws),
         pages = pages(study.id),
         [_ | _] = fresh <- Enum.reject(items, &paged?(&1, pages)),
         true <- quiet?(study.id, pages, now) do
      keys = Enum.map(fresh, & &1.key)
      Channel.post(%{thread_id: study.id, author: "tlon", body: body(fresh), payload: %{"need_page" => keys}})
    end

    :ok
  end

  # `{created_at, keys}` of every page on the study, newest first
  defp pages(thread_id) do
    from(m in Message,
      where: m.thread_id == ^thread_id and m.author == "tlon" and fragment("? \\? 'need_page'", m.payload),
      order_by: [desc: m.id],
      limit: 200,
      select: {m.created_at, m.payload}
    )
    |> Repo.all()
    |> Enum.map(fn {at, p} -> {at, p["need_page"]} end)
  end

  # message.created_at is whole seconds, so the item's `at` is compared at the same grain
  defp paged?(item, pages) do
    at = DateTime.truncate(item.at, :second)
    Enum.any?(pages, fn {page_at, keys} -> item.key in keys and DateTime.compare(page_at, at) != :lt end)
  end

  defp quiet?(thread_id, pages, now) do
    Server.Presence.Thinking.thinking_for(thread_id) == [] and
      case pages do
        [{at, _} | _] -> DateTime.diff(now, at) >= @gap_s
        [] -> true
      end
  end

  defp body(fresh) do
    listed = fresh |> Enum.take(@listed) |> Enum.map_join("\n", &"- #{&1.key} (#{&1.kind}) #{&1.title}")

    "@uqbar #{length(fresh)} new #{if length(fresh) == 1, do: "need waits", else: "needs wait"} in your group. " <>
      "Read operator_inbox, then settle_need or pass_up_need each `route: uqbar` item:\n" <> listed
  end
end
