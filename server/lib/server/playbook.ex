defmodule Server.Playbook do
  @moduledoc """
  A named procedure with success criteria (field survey §4 adopt #4). FACTS say what is TRUE;
  a playbook says HOW, step by step, and what "done" looks like — the half of Devin's
  Knowledge/Playbooks split Tlön lacked. `name` is the handle a coworker runs it by
  (`run_playbook`), a closed slug charset so it reads in a brief; `steps` and `success` are
  markdown. `source_thread_id` points at the thread a solved problem was promoted from.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @name ~r/\A[a-z0-9][a-z0-9-]{0,59}\z/

  schema "playbook" do
    field :name, :string
    field :summary, :string, default: ""
    field :steps, :string
    field :success, :string, default: ""
    field :author, :string
    field :source_thread_id, :integer
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime
  end

  @mutable [:summary, :steps, :success]

  def define_changeset(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %__MODULE__{}
    |> cast(attrs, [:name, :author, :source_thread_id | @mutable])
    |> validate_required([:name, :steps])
    |> validate_format(:name, @name, message: "a slug: a-z 0-9 and dashes, up to 60")
    |> validate_length(:steps, min: 1)
    |> unique_constraint(:name)
    |> put_change(:created_at, now)
    |> put_change(:updated_at, now)
  end

  def edit_changeset(%__MODULE__{} = playbook, attrs) do
    playbook
    |> cast(attrs, @mutable)
    |> validate_required([:steps])
    |> put_change(:updated_at, DateTime.truncate(DateTime.utc_now(), :second))
  end
end
