defmodule Server.Home.Form do
  @moduledoc """
  The structured way into the home: what a form puts in or changes, checked, with no reader and no
  model, so a date the operator picks is the date they get. Bodies are JSON maps with string keys;
  an error is `{:error, reason}`, one line. A time (`at`) is ISO 8601: with a zone (`Z`, `+02:00`) it
  is that instant, without one (`2026-11-21T09:00`) it is the operator's wall clock in the machine's
  zone, as the reader reads times. `every` is `Server.Home.Clock.every/1`.
  """

  alias Server.Home.Clock
  alias Server.Jot

  @kinds ["todo", "reminder", "note", "waiting", "project"]
  @max_text 500
  @max_list 50
  @every "every is day, week or month, or a number then one of them: 6 week"
  @at "at is ISO 8601: 2026-11-21T09:00 (local) or with a zone, 2026-11-21T09:00:00Z"

  @doc """
  A reading, as `Server.Home.Organize.file/3` takes it, from the body of an add: `kind`
  (`todo`, `reminder`, `note`, `waiting`, `project`), `text`, and by kind `at` and `every` (a
  reminder, which needs `at`), `who` (a waiting-on), `steps` (a project, at least one) and `project`
  (a to-do's project id, in the reading as `project`).
  """
  @spec add(map()) :: {:ok, map()} | {:error, String.t()}
  def add(%{"kind" => kind} = params) when kind in @kinds do
    with {:ok, text} <- text(params["text"]),
         {:ok, due} <- time(params["at"], kind),
         {:ok, every} <- repeat(params["every"], kind),
         {:ok, extra} <- extra(kind, params) do
      {:ok, Map.merge(%{kind: kind, text: text, due_at: due, every: every, ids: [], amends: false}, extra)}
    end
  end

  def add(_params), do: {:error, "kind is todo, reminder, note, waiting or project"}

  @doc """
  What an edit of `jot` changes, from its body (`text`, `at`, `every` or null to stop it, `kind` only
  `todo` or `reminder`): a map of the fields changed, `text`, `kind`, `due_at`, `every`.
  """
  @spec edit(Jot.t(), map()) :: {:ok, map()} | {:error, String.t()}
  def edit(%Jot{kind: current} = jot, params) do
    with {:ok, kind} <- kind(jot, params),
         {:ok, text} <- edited_text(params),
         {:ok, at} <- edited_at(params),
         {:ok, every} <- edited_every(params) do
      shape(jot, kind || current, text, at, every, current)
    end
  end

  @doc "A list of texts, trimmed and without blanks, as a plan: `{:ok, texts}`, `:error` when it is not one."
  @spec texts(term()) :: {:ok, [String.t()]} | :error
  def texts(list) when is_list(list) and length(list) <= @max_list do
    if Enum.all?(list, &is_binary/1),
      do:
        {:ok, list |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.map(&String.slice(&1, 0, @max_text))},
      else: :error
  end

  def texts(_other), do: :error

  defp text(text) when is_binary(text) do
    case String.trim(text) do
      "" -> {:error, "text is required"}
      text -> {:ok, String.slice(text, 0, @max_text)}
    end
  end

  defp text(_none), do: {:error, "text is required"}

  defp time(nil, "reminder"), do: {:error, "a reminder needs at"}
  defp time(nil, _kind), do: {:ok, nil}
  defp time(at, "reminder"), do: parse(at)
  defp time(_at, _kind), do: {:error, "at is for a reminder"}

  defp parse(at) when is_binary(at) do
    with :error <- zoned(at), :error <- local(at), do: {:error, @at}
  end

  defp parse(_at), do: {:error, @at}

  defp zoned(at) do
    at
    |> seconds()
    |> DateTime.from_iso8601()
    |> case do
      {:ok, at, _offset} -> {:ok, DateTime.truncate(at, :second)}
      _ -> :error
    end
  end

  defp local(at) do
    at
    |> seconds()
    |> NaiveDateTime.from_iso8601()
    |> case do
      {:ok, naive} -> {:ok, naive |> Clock.utc() |> DateTime.truncate(:second)}
      _ -> :error
    end
  end

  defp seconds(at), do: Regex.replace(~r/^(.*T\d\d:\d\d)(Z|[+-]\d\d:\d\d)?$/, at, "\\1:00\\2")

  defp repeat(nil, _kind), do: {:ok, nil}
  defp repeat(every, "reminder"), do: every(every)
  defp repeat(_every, _kind), do: {:error, "every is for a reminder"}

  defp every(every) do
    case Clock.every(every) do
      nil -> {:error, @every}
      every -> {:ok, every}
    end
  end

  defp extra("waiting", params) do
    case params["who"] do
      who when is_binary(who) and who != "" -> {:ok, %{who: String.trim(who)}}
      _ -> {:error, "who is required for a waiting-on"}
    end
  end

  defp extra("project", params) do
    case texts(params["steps"]) do
      {:ok, [_ | _] = steps} -> {:ok, %{steps: steps}}
      _ -> {:error, "steps is a list of texts, at least one"}
    end
  end

  defp extra("todo", %{"project" => id}) when is_integer(id), do: {:ok, %{project: id}}
  defp extra("todo", %{"project" => nil}), do: {:ok, %{}}
  defp extra("todo", %{"project" => _id}), do: {:error, "project is a project's id"}
  defp extra(_kind, %{"project" => nil}), do: {:ok, %{}}
  defp extra(_kind, %{"project" => _id}), do: {:error, "project is for a to-do"}
  defp extra(_kind, _params), do: {:ok, %{}}

  defp kind(_jot, %{"kind" => kind}) when kind not in ["todo", "reminder"],
    do: {:error, "kind is only todo or reminder"}

  defp kind(%Jot{kind: current}, %{"kind" => kind}) when current in ["todo", "reminder"], do: {:ok, kind}
  defp kind(_jot, %{"kind" => _kind}), do: {:error, "kind is only todo or reminder"}
  defp kind(_jot, _params), do: {:ok, nil}

  defp edited_text(%{"text" => text}), do: text(text)
  defp edited_text(_params), do: {:ok, nil}

  defp edited_at(%{"at" => nil}), do: {:ok, nil}
  defp edited_at(%{"at" => at}), do: parse(at)
  defp edited_at(_params), do: {:ok, nil}

  defp edited_every(%{"every" => nil}), do: {:ok, :stop}
  defp edited_every(%{"every" => every}), do: every(every)
  defp edited_every(_params), do: {:ok, nil}

  defp shape(jot, kind, text, at, every, current) do
    cond do
      kind != "reminder" and (at != nil or is_binary(every)) ->
        {:error, no_time(kind, current)}

      kind == "reminder" and at == nil and timeless?(jot, every) ->
        {:error, "a reminder needs at"}

      true ->
        {:ok, changes(jot, kind, text, at, every)}
    end
  end

  defp timeless?(%Jot{kind: "todo"}, _every), do: true
  defp timeless?(%Jot{due_at: nil}, every), do: is_binary(every)
  defp timeless?(_jot, _every), do: false

  defp no_time("todo", "todo"), do: "a to-do has no time: send kind reminder with at"
  defp no_time("todo", _reminder), do: "a to-do has no time and no repeat"
  defp no_time(_kind, _current), do: "at is for a reminder"

  defp changes(jot, kind, text, at, every) do
    [
      text: text,
      kind: if(kind != jot.kind, do: kind),
      due_at: if(kind == "todo" and jot.kind == "reminder", do: :clear, else: at),
      every: if(kind == "todo" and jot.kind == "reminder", do: :stop, else: every)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn
      {key, :clear} -> {key, nil}
      {key, :stop} -> {key, nil}
      other -> other
    end)
  end
end
