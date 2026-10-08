defmodule Server.Office.Weather do
  @moduledoc """
  The weather outside, for the office's windows: current conditions from wttr.in (no key; it places
  the machine by its address unless the settings file names a place, `"weather_location"`), read
  into the few kinds the room can draw (`kind/1`) with the temperature.

  `now/0` answers from the cache at once — the office snapshot never waits on the network — and a
  read when the report is older than `@every_s` (or missing) fetches a fresh one in the background.
  A failed fetch leaves the last report standing. On unless `TLON_WEATHER=0` (`:start_weather`).
  """
  use GenServer

  @every_s 900

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The last report, `%{kind, temp_c, desc}`, or nil (none yet, or the weather is off)."
  @spec now() :: %{kind: String.t(), temp_c: integer() | nil, desc: String.t()} | nil
  def now do
    if GenServer.whereis(__MODULE__), do: GenServer.call(__MODULE__, :now)
  end

  @doc "A wttr.in weather code as the room draws it; nil for one it does not know."
  def kind(113), do: "clear"
  def kind(116), do: "partly"
  def kind(code) when code in [119, 122], do: "cloudy"
  def kind(code) when code in [143, 248, 260], do: "fog"
  def kind(code) when code in [200, 386, 389, 392, 395], do: "storm"

  def kind(code)
      when code in [179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377],
      do: "snow"

  def kind(code) when code in [176, 263, 266, 281, 284, 293, 296, 299, 302, 305, 308, 311, 314, 353, 356, 359],
    do: "rain"

  def kind(_code), do: nil

  @doc "wttr.in's `format=j1` report as `%{kind, temp_c, desc}`, or nil when it is not one."
  def parse(body) do
    with {:ok, %{"current_condition" => [c | _]}} when is_map(c) <- JSON.decode(body),
         {code, ""} <- Integer.parse(to_string(c["weatherCode"])),
         kind when is_binary(kind) <- kind(code) do
      temp = with t when is_binary(t) <- c["temp_C"], {n, ""} <- Integer.parse(t), do: n, else: (_ -> nil)
      %{kind: kind, temp_c: temp, desc: String.trim(desc(c["weatherDesc"]) || kind)}
    else
      _ -> nil
    end
  end

  @impl true
  def init(opts), do: {:ok, %{report: nil, at: 0, fetch: Keyword.get(opts, :fetch, &fetch/0)}}

  @impl true
  def handle_call(:now, _from, state) do
    now = System.system_time(:second)

    state =
      if now - state.at >= @every_s do
        me = self()
        Task.Supervisor.start_child(Server.TaskSupervisor, fn -> GenServer.cast(me, {:fetched, state.fetch.()}) end)
        %{state | at: now}
      else
        state
      end

    {:reply, state.report, state}
  end

  @impl true
  def handle_cast({:fetched, {:ok, body}}, state), do: {:noreply, %{state | report: parse(body) || state.report}}
  def handle_cast({:fetched, _failed}, state), do: {:noreply, state}

  defp fetch do
    _ = Application.ensure_all_started([:inets, :ssl])
    place = URI.encode(Server.OperatorConfig.setting("weather_location"))

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(
           :get,
           {~c"https://wttr.in/#{place}?format=j1", []},
           [timeout: 10_000, connect_timeout: 5_000, ssl: ssl],
           body_format: :binary
         ) do
      {:ok, {{_v, 200, _r}, _headers, body}} -> {:ok, body}
      other -> {:error, other}
    end
  rescue
    e -> {:error, e}
  end

  defp desc([%{"value" => v} | _]) when is_binary(v), do: v
  defp desc(_), do: nil
end
