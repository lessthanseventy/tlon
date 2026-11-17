defmodule Server.Home.Telegram do
  @moduledoc """
  The home inbox's messenger: a Telegram bot, polled outbound (`getUpdates`), so the machine opens
  no port for it. The bot's token is the machine's: `TELEGRAM_BOT_TOKEN`, else the agenix file
  `$XDG_RUNTIME_DIR/agenix/telegram-bot-token`, read at call time and never stored.
  """

  @wait_s 25

  @doc "The messenger's name, a jot's `via`."
  @spec name() :: String.t()
  def name, do: "telegram"

  @doc "The bot's token, nil when the machine has none."
  @spec token() :: String.t() | nil
  def token do
    with nil <- present(System.get_env("TELEGRAM_BOT_TOKEN")),
         dir when is_binary(dir) <- System.get_env("XDG_RUNTIME_DIR"),
         {:ok, text} <- File.read(Path.join([dir, "agenix", "telegram-bot-token"])) do
      present(String.trim(text))
    else
      token when is_binary(token) -> token
      _ -> nil
    end
  end

  @doc """
  The updates from `offset` on, waiting up to #{@wait_s} s for one: `{:ok, [%{id, chat, text}]}`,
  `chat` nil for an update that is no message and `text` nil for a message that is not text. A tap
  on one of a message's choices is `%{id, chat, text: nil, tap, tap_id, ref}`: `tap` the choice's
  data, `ref` the message it was under. A tap is acknowledged here, so the button stops waiting.
  """
  @spec updates(integer()) :: {:ok, [map()]} | {:error, term()}
  def updates(offset) do
    with {:ok, body} <- get("getUpdates?timeout=#{@wait_s}&offset=#{offset}", (@wait_s + 10) * 1000),
         {:ok, updates} <- parse(body) do
      for %{tap_id: tap} <- updates, do: get("answerCallbackQuery?" <> URI.encode_query(callback_query_id: tap), 10_000)
      {:ok, updates}
    end
  end

  @doc """
  Send `text` to `chat`. `opts[:choices]`, `[{label, data}]`, are buttons under it, a tap on one
  coming back from `updates/1`; `opts[:replace]` is the `ref` of a message this one takes the place
  of, its buttons gone.
  """
  @spec say(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def say(chat, text, opts \\ []) do
    with {:ok, _} <- get(call(chat, text, opts[:replace], opts[:choices] || []), 10_000), do: :ok
  end

  @doc "A `getUpdates` reply as `updates/1` answers it."
  @spec parse(binary()) :: {:ok, [map()]} | {:error, term()}
  def parse(body) do
    case JSON.decode(body) do
      {:ok, %{"ok" => true, "result" => updates}} -> {:ok, Enum.map(updates, &update/1)}
      {:ok, %{"description" => why}} -> {:error, why}
      _ -> {:error, "not a Telegram reply"}
    end
  end

  defp update(%{"update_id" => id, "message" => %{"chat" => %{"id" => chat}} = message}),
    do: %{id: id, chat: to_string(chat), text: message["text"]}

  defp update(%{
         "update_id" => id,
         "callback_query" => %{
           "id" => tap,
           "data" => data,
           "message" => %{"message_id" => ref, "chat" => %{"id" => chat}}
         }
       }),
       do: %{id: id, chat: to_string(chat), text: nil, tap: data, tap_id: tap, ref: ref}

  defp update(%{"update_id" => id}), do: %{id: id, chat: nil, text: nil}

  defp get(call, timeout) do
    _ = Application.ensure_all_started([:inets, :ssl])

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    url = ~c"https://api.telegram.org/bot#{token()}/#{call}"

    case :httpc.request(:get, {url, []}, [timeout: timeout, connect_timeout: 5_000, ssl: ssl], body_format: :binary) do
      {:ok, {{_v, 200, _r}, _headers, body}} -> {:ok, body}
      {:ok, {{_v, code, _r}, _headers, _body}} -> {:error, "Telegram answered #{code}"}
      {:error, why} -> {:error, why}
    end
  end

  defp present(""), do: nil
  defp present(value), do: value

  defp call(chat, text, nil, []), do: "sendMessage?" <> URI.encode_query(chat_id: chat, text: text)

  defp call(chat, text, nil, choices) do
    keys = [Enum.map(choices, fn {label, data} -> %{text: label, callback_data: data} end)]
    "sendMessage?" <> URI.encode_query(chat_id: chat, text: text, reply_markup: JSON.encode!(%{inline_keyboard: keys}))
  end

  defp call(chat, text, ref, _choices),
    do: "editMessageText?" <> URI.encode_query(chat_id: chat, message_id: ref, text: text)
end
