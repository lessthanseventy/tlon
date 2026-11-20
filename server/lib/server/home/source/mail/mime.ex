defmodule Server.Home.Source.Mail.Mime do
  @moduledoc """
  A message made readable, best effort: the From, Subject, Date and Message-ID with RFC 2047 encoded
  words decoded, and the start of the body as plain text (quoted-printable or base64 undone; a
  multipart's first text part, `text/plain` before `text/html`, whose tags are stripped). Odd mail
  gives less text, never an error.
  """

  @type readable :: %{
          from: String.t(),
          subject: String.t(),
          date: String.t(),
          message_id: String.t() | nil,
          body: String.t()
        }

  @doc "The readable message of a raw `header` (the fields asked for) and raw `body`, its text at most `limit` characters."
  @spec read(binary(), binary(), pos_integer()) :: readable()
  def read(header, body, limit) do
    headers = headers(header)

    %{
      from: headers |> Map.get("from", "") |> words() |> clean(),
      subject: headers |> Map.get("subject", "") |> words() |> clean(),
      date: headers |> Map.get("date", "") |> clean(),
      message_id: headers |> Map.get("message-id") |> id(),
      body: headers |> text(body) |> clean() |> String.slice(0, limit)
    }
  rescue
    _ -> %{from: "", subject: "", date: "", message_id: nil, body: ""}
  end

  @doc "The fields of a raw header block, names lowercased, folded lines joined; a field repeated keeps its first."
  @spec headers(binary()) :: %{String.t() => String.t()}
  def headers(block) do
    block
    |> String.replace(~r/\r?\n[ \t]+/, " ")
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, ":", parts: 2) do
        [name, value] -> [{name |> String.trim() |> String.downcase(), String.trim(value)}]
        _ -> []
      end
    end)
    |> Enum.reverse()
    |> Map.new()
  end

  @doc "`value` with its RFC 2047 encoded words (`=?utf-8?B?...?=`, `=?iso-8859-1?Q?...?=`) decoded."
  @spec words(String.t()) :: String.t()
  def words(value) do
    value
    |> String.replace(~r/(\?=)\s+(?==\?)/, "\\1")
    |> then(
      &Regex.replace(~r/=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?=/, &1, fn whole, charset, enc, data ->
        word(whole, charset, enc, data)
      end)
    )
  end

  defp word(whole, charset, enc, data) do
    decoded = if String.downcase(enc) == "b", do: base64(data), else: qp(String.replace(data, "_", " "))
    if decoded == "", do: whole, else: utf8(decoded, charset)
  end

  defp id(nil), do: nil

  defp id(value) do
    case Regex.run(~r/<([^<>\s]+)>/, value) do
      [_, id] -> id
      nil -> if(String.trim(value) != "", do: String.trim(value))
    end
  end

  defp text(headers, body) do
    ctype = Map.get(headers, "content-type", "text/plain")
    cte = headers |> Map.get("content-transfer-encoding", "7bit") |> String.downcase()

    case parts(ctype, cte, body) do
      [] -> ""
      found -> render(Enum.find(found, &match?({"plain", _}, &1)) || hd(found))
    end
  end

  defp render({"plain", text}), do: text
  defp render({"html", html}), do: strip(html)

  # the text parts of an entity, in order, as {"plain" | "html", text}
  defp parts(ctype, cte, body) do
    {type, params} = content_type(ctype)

    cond do
      String.starts_with?(type, "multipart/") ->
        case params["boundary"] do
          nil -> []
          boundary -> multipart(boundary, body)
        end

      type in ["text/plain", "text/html"] ->
        subtype = if type == "text/html", do: "html", else: "plain"
        [{subtype, cte |> decode(body) |> utf8(params["charset"] || "utf-8")}]

      true ->
        []
    end
  end

  defp multipart(boundary, body) do
    body
    |> String.split("--" <> boundary)
    |> Enum.drop(1)
    |> Enum.flat_map(fn part ->
      case String.split(part, ~r/\r?\n\r?\n/, parts: 2) do
        [head, content] ->
          headers = headers(head)

          parts(
            Map.get(headers, "content-type", "text/plain"),
            headers |> Map.get("content-transfer-encoding", "7bit") |> String.downcase(),
            content
          )

        _ ->
          []
      end
    end)
  end

  defp content_type(value) do
    [type | params] = String.split(value, ";")

    params =
      for param <- params, [key, val] <- [String.split(param, "=", parts: 2)], into: %{} do
        {key |> String.trim() |> String.downcase(), val |> String.trim() |> String.trim("\"")}
      end

    {type |> String.trim() |> String.downcase(), params}
  end

  defp decode("base64", body), do: base64(body)
  defp decode("quoted-printable", body), do: qp(body)
  defp decode(_, body), do: body

  # a body cut short by the byte limit ends mid-quantum: what is there decodes, unpadded
  defp base64(data) do
    data = String.replace(data, ~r/[^A-Za-z0-9+\/]/, "")
    data = if rem(byte_size(data), 4) == 1, do: binary_part(data, 0, byte_size(data) - 1), else: data

    case Base.decode64(data, padding: false) do
      {:ok, bin} -> bin
      :error -> ""
    end
  end

  defp qp(data) do
    data
    |> String.replace(~r/=\r?\n/, "")
    |> then(&Regex.replace(~r/=([0-9A-Fa-f]{2})/, &1, fn _, hex -> <<String.to_integer(hex, 16)>> end))
  end

  defp utf8(bin, charset) do
    String.replace_invalid(
      case String.downcase(charset) do
        cs when cs in ["iso-8859-1", "latin1", "windows-1252", "iso-8859-15"] ->
          :unicode.characters_to_binary(bin, :latin1)

        _ ->
          bin
      end
    )
  end

  defp strip(html) do
    html
    |> String.replace(~r/<(script|style)\b.*?<\/\1\s*>/is, " ")
    |> String.replace(~r/<[^>]*>?/s, " ")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
  end

  defp clean(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()
end
