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

  test "a voice note carries the file to fetch" do
    body = ~s({"ok":true,"result":[{"update_id":8,"message":{"chat":{"id":42},"voice":{"file_id":"f1","duration":3}}}]})

    assert Telegram.parse(body) == {:ok, [%{id: 8, chat: "42", text: nil, voice: "f1"}]}
  end

  test "a tap on a choice carries the choice's data and the message it was under" do
    body =
      ~s({"ok":true,"result":[{"update_id":7,"callback_query":{"id":"q1","data":"done:3",) <>
        ~s("message":{"message_id":90,"chat":{"id":42}}}}]})

    assert Telegram.parse(body) == {:ok, [%{id: 7, chat: "42", text: nil, tap: "done:3", tap_id: "q1", ref: 90}]}
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
