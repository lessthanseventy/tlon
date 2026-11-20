defmodule Server.Home.Source.Mail.Imap do
  @moduledoc """
  A read-only IMAP client, the few commands the mail source needs: `LOGIN`, `EXAMINE INBOX`
  (never `SELECT`), `UID SEARCH`, `UID FETCH` with `BODY.PEEK` and `LOGOUT`. There is no command that
  writes, and nothing here is able to mark a message read. A response's literals (`{N}` then N bytes)
  are read by length. The wire is a `Server.Home.Source.Mail.Imap.Transport`,
  `Server.Home.Source.Mail.Imap.TLS` by default.
  An error reason is a short fixed text: never what the server said, never the password.
  """

  defmodule Transport do
    @moduledoc "The wire under the client: what a test replaces with a scripted server."
    @callback connect(String.t(), :inet.port_number()) :: {:ok, term()} | {:error, term()}
    @callback send(term(), iodata()) :: :ok | {:error, term()}
    @callback recv(term()) :: {:ok, binary()} | {:error, term()}
    @callback close(term()) :: :ok
  end

  defmodule TLS do
    @moduledoc "TLS with the certificate and its host name verified."
    @behaviour Transport

    @timeout_ms 20_000

    @impl true
    def connect(host, port) do
      :ssl.connect(
        String.to_charlist(host),
        port,
        [
          :binary,
          active: false,
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: String.to_charlist(host),
          customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
        ],
        @timeout_ms
      )
    end

    @impl true
    def send(socket, data), do: :ssl.send(socket, data)

    @impl true
    def recv(socket), do: :ssl.recv(socket, 0, @timeout_ms)

    @impl true
    def close(socket), do: :ssl.close(socket)
  end

  @fields "FROM SUBJECT DATE MESSAGE-ID CONTENT-TYPE CONTENT-TRANSFER-ENCODING"
  @body_bytes 20_000
  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  @type config :: %{
          required(:host) => String.t(),
          required(:user) => String.t(),
          required(:password) => String.t(),
          optional(:port) => :inet.port_number(),
          optional(:transport) => module()
        }
  @type message :: %{uid: integer(), header: binary(), body: binary()}

  @doc """
  The messages of the inbox newer than `mark` (`%{validity: n, uid: n}`; nil or a changed UIDVALIDITY
  starts over): `{:ok, validity, messages}`, the oldest `limit` of them after a mark, the newest with none, each with its `uid`, the raw
  `header` fields and the first bytes of the raw `body`; with no mark, only those since `since`
  (a `Date`). `{:error, reason}` on any failure.
  """
  @spec new_messages(config(), map() | nil, Date.t(), pos_integer()) ::
          {:ok, integer(), [message()]} | {:error, String.t()}
  def new_messages(%{user: user, password: password} = config, mark, since, limit) do
    transport = Map.get(config, :transport, TLS)

    if String.contains?(user <> password, ["\r", "\n", <<0>>]) do
      {:error, "mail credentials are malformed"}
    else
      case transport.connect(config.host, Map.get(config, :port, 993)) do
        {:ok, socket} ->
          conn = %{transport: transport, socket: socket, buffer: "", tag: 0}

          try do
            read(conn, config, mark, since, limit)
          after
            transport.close(socket)
          end

        {:error, _} ->
          {:error, "mail server not reachable"}
      end
    end
  end

  defp read(conn, config, mark, since, limit) do
    with {:ok, conn} <- greeting(conn),
         {:ok, _, conn} <- command(conn, "LOGIN #{quoted(config.user)} #{quoted(config.password)}", "LOGIN"),
         {:ok, lines, conn} <- command(conn, "EXAMINE INBOX", "EXAMINE"),
         {:ok, validity} <- validity(lines),
         mark = if(match?(%{validity: ^validity}, mark), do: mark),
         {:ok, found, conn} <- search(conn, mark, since),
         {:ok, messages, conn} <- fetch(conn, take(found, mark, limit)) do
      command(conn, "LOGOUT", "LOGOUT")
      {:ok, validity, messages}
    end
  end

  defp greeting(conn) do
    case read_line(conn) do
      {:ok, "* OK" <> _, conn} -> {:ok, conn}
      _ -> {:error, "mail server did not greet"}
    end
  end

  defp validity(lines) do
    Enum.find_value(lines, {:error, "mailbox has no UIDVALIDITY"}, fn line ->
      case Regex.run(~r/\[UIDVALIDITY (\d+)\]/, line) do
        [_, n] -> {:ok, String.to_integer(n)}
        nil -> nil
      end
    end)
  end

  defp search(conn, nil, since), do: search(conn, "SINCE #{date(since)}", 0)
  defp search(conn, %{uid: uid}, _since), do: search(conn, "UID #{uid + 1}:*", uid)

  defp search(conn, criteria, floor) when is_binary(criteria) do
    with {:ok, lines, conn} <- command(conn, "UID SEARCH #{criteria}", "UID SEARCH") do
      uids =
        for "* SEARCH" <> rest <- lines,
            n <- String.split(rest),
            {uid, ""} <- [Integer.parse(n)],
            uid > floor,
            do: uid

      {:ok, uids, conn}
    end
  end

  # with a mark the oldest, so the mark only passes what was read; the first look-back keeps the newest
  defp take(uids, nil, limit), do: uids |> Enum.uniq() |> Enum.sort() |> Enum.take(-limit)
  defp take(uids, _mark, limit), do: uids |> Enum.uniq() |> Enum.sort() |> Enum.take(limit)

  defp fetch(conn, []), do: {:ok, [], conn}

  defp fetch(conn, uids) do
    what = "(UID BODY.PEEK[HEADER.FIELDS (#{@fields})] BODY.PEEK[TEXT]<0.#{@body_bytes}>)"

    with {:ok, lines, conn} <- command(conn, "UID FETCH #{Enum.join(uids, ",")} #{what}", "UID FETCH") do
      messages =
        lines
        |> Enum.flat_map(&fetch_fields/1)
        |> Enum.reduce(%{}, fn {seq, fields}, by_seq -> Map.update(by_seq, seq, fields, &Map.merge(&1, fields)) end)
        |> Map.values()
        |> Enum.flat_map(&message/1)
        |> Enum.sort_by(& &1.uid)

      {:ok, messages, conn}
    end
  end

  # a server may spread one message's data over several responses, told apart by sequence number
  defp fetch_fields(line) do
    with [_, seq, rest] <- Regex.run(~r/^\* (\d+) FETCH (.*)$/s, line),
         {[_ | _] = items, _} <- value(rest) do
      [{seq, fields(items)}]
    else
      _ -> []
    end
  end

  defp message(%{"UID" => uid} = fields) do
    case Integer.parse(uid) do
      {uid, ""} -> [%{uid: uid, header: part(fields, "BODY[HEADER"), body: part(fields, "BODY[TEXT")}]
      _ -> []
    end
  end

  defp message(_), do: []

  defp fields(items) do
    items
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      [key, val] when is_binary(key) -> [{String.upcase(key), val}]
      _ -> []
    end)
    |> Map.new()
  end

  defp part(fields, prefix) do
    Enum.find_value(fields, "", fn {key, val} -> if String.starts_with?(key, prefix) and is_binary(val), do: val end)
  end

  @doc """
  One IMAP value at the start of `text`, as `{value, rest}`: a parenthesised list a list, a quoted
  string, a `{N}` literal (N bytes after the line's end) or an atom a binary. `:error` on text that
  is none.
  """
  @spec value(binary()) :: {binary() | [term()], binary()} | :error
  def value(<<" ", rest::binary>>), do: value(rest)
  def value(<<"(", rest::binary>>), do: list(rest, [])
  def value(<<"\"", rest::binary>>), do: quoted_string(rest, [])

  def value(<<"{", rest::binary>>) do
    with [n, after_brace] <- :binary.split(rest, "}\r\n"),
         {n, ""} <- Integer.parse(n),
         <<literal::binary-size(^n), tail::binary>> <- after_brace do
      {literal, tail}
    else
      _ -> :error
    end
  end

  def value(<<char, _::binary>> = text) when char not in [?), ?\s], do: atom(text, 0, 0)
  def value(_), do: :error

  defp list(<<")", rest::binary>>, acc), do: {Enum.reverse(acc), rest}
  defp list(<<" ", rest::binary>>, acc), do: list(rest, acc)

  defp list(text, acc) do
    case value(text) do
      {item, rest} -> list(rest, [item | acc])
      :error -> :error
    end
  end

  defp quoted_string(<<"\\", char, rest::binary>>, acc), do: quoted_string(rest, [char | acc])
  defp quoted_string(<<"\"", rest::binary>>, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  defp quoted_string(<<char, rest::binary>>, acc), do: quoted_string(rest, [char | acc])
  defp quoted_string("", _), do: :error

  # an atom may hold a bracketed section with spaces and parens: BODY[HEADER.FIELDS (FROM SUBJECT)]
  defp atom(text, size, depth) do
    case text do
      <<atom::binary-size(^size), char, _::binary>> when depth == 0 and char in [?\s, ?), ?(] ->
        {atom, binary_part(text, size, byte_size(text) - size)}

      <<atom::binary-size(^size)>> when depth == 0 ->
        {atom, ""}

      <<_::binary-size(^size), ?[, _::binary>> ->
        atom(text, size + 1, depth + 1)

      <<_::binary-size(^size), ?], _::binary>> ->
        atom(text, size + 1, max(depth - 1, 0))

      <<_::binary-size(^size), _, _::binary>> ->
        atom(text, size + 1, depth)

      _ ->
        :error
    end
  end

  defp command(conn, text, verb) do
    tag = "a#{conn.tag + 1}"
    conn = %{conn | tag: conn.tag + 1}

    case conn.transport.send(conn.socket, [tag, " ", text, "\r\n"]) do
      :ok -> collect(conn, tag, verb, [])
      _ -> {:error, "mail connection lost"}
    end
  end

  defp collect(conn, tag, verb, acc) do
    case read_line(conn) do
      {:ok, line, conn} ->
        cond do
          String.starts_with?(line, tag <> " OK") -> {:ok, Enum.reverse(acc), conn}
          String.starts_with?(line, tag <> " ") -> {:error, "#{verb} refused"}
          true -> collect(conn, tag, verb, [line | acc])
        end

      {:error, _} = error ->
        error
    end
  end

  # a logical line: up to CRLF, with each literal it announces taken whole, its `{N}\r\n` kept
  defp read_line(conn), do: read_line(conn, "")

  defp read_line(conn, acc) do
    case :binary.split(conn.buffer, "\r\n") do
      [line, rest] ->
        case Regex.run(~r/\{(\d+)\}$/, line) do
          [_, n] -> literal(%{conn | buffer: rest}, acc <> line <> "\r\n", String.to_integer(n))
          nil -> {:ok, acc <> line, %{conn | buffer: rest}}
        end

      [_] ->
        with {:ok, conn} <- more(conn), do: read_line(conn, acc)
    end
  end

  defp literal(%{buffer: buffer} = conn, acc, n) when byte_size(buffer) >= n do
    <<chunk::binary-size(^n), rest::binary>> = buffer
    read_line(%{conn | buffer: rest}, acc <> chunk)
  end

  defp literal(conn, acc, n) do
    with {:ok, conn} <- more(conn), do: literal(conn, acc, n)
  end

  defp more(conn) do
    case conn.transport.recv(conn.socket) do
      {:ok, data} -> {:ok, %{conn | buffer: conn.buffer <> data}}
      {:error, _} -> {:error, "mail connection lost"}
    end
  end

  defp quoted(text), do: ~s("#{text |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")}")

  defp date(%Date{day: day, month: month, year: year}), do: "#{day}-#{Enum.at(@months, month - 1)}-#{year}"
end
