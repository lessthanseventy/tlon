defmodule Server.Home.TelegramTest do
  use ExUnit.Case, async: true

  alias Server.Home.Telegram

  test "a getUpdates reply is its messages: the update's id, the chat as text, the text" do
    body =
      ~s({"ok":true,"result":[{"update_id":5,"message":{"chat":{"id":42},"text":"milk"}},) <>
        ~s({"update_id":6,"message":{"chat":{"id":42},"voice":{"duration":3}}}]})

    assert Telegram.parse(body) ==
             {:ok, [%{id: 5, chat: "42", text: "milk"}, %{id: 6, chat: "42", text: nil}]}
  end

  test "an update that is no message (an edit, a join) keeps its id and names no chat" do
    assert Telegram.parse(~s({"ok":true,"result":[{"update_id":9,"edited_message":{}}]})) ==
             {:ok, [%{id: 9, chat: nil, text: nil}]}
  end

  test "a refusal is an error with what Telegram said" do
    assert Telegram.parse(~s({"ok":false,"description":"Unauthorized"})) == {:error, "Unauthorized"}
    assert {:error, _} = Telegram.parse("<html>")
  end
end
