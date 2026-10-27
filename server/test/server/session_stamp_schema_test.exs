defmodule Server.SessionStampSchemaTest do
  # #679: a row's author is verifiable only if the row carries the SESSION that wrote it. The
  # field exists on message, ticket and event, and no cast list admits it, so a caller's attrs can
  # never assert a session: it is the connection's or NULL.
  use ExUnit.Case, async: true

  alias Server.Event
  alias Server.Message
  alias Server.Ticket

  for schema <- [Message, Ticket, Event] do
    test "#{inspect(schema)} carries session_id" do
      assert :session_id in unquote(schema).__schema__(:fields)
      assert unquote(schema).__schema__(:association, :session).related == Server.Session
    end
  end

  test "session_id smuggled in attrs is never cast" do
    refute Map.has_key?(
             Message.post_changeset(%{thread_id: 1, author: "a", body: "b", session_id: 9}).changes,
             :session_id
           )

    refute Map.has_key?(Ticket.file_changeset(%{workspace_id: 1, title: "t", session_id: 9}).changes, :session_id)
    refute Map.has_key?(Event.record_changeset(%{kind: "cited", session_id: 9}).changes, :session_id)
  end
end
