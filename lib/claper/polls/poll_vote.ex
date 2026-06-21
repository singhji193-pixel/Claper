defmodule Claper.Polls.PollVote do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          attendee_identifier: String.t() | nil,
          poll_id: integer() | nil,
          poll_opt_id: integer() | nil,
          user_id: integer() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "poll_votes" do
    field :attendee_identifier, :string

    belongs_to :poll, Claper.Polls.Poll
    belongs_to :poll_opt, Claper.Polls.PollOpt
    belongs_to :user, Claper.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(poll_vote, attrs) do
    poll_vote
    |> cast(attrs, [:attendee_identifier, :user_id, :poll_opt_id, :poll_id])
    |> validate_required([:poll_opt_id, :poll_id])
    |> validate_identity()
    |> unique_constraint(:attendee_identifier, name: :poll_votes_attendee_option_unique)
    |> unique_constraint(:user_id, name: :poll_votes_user_option_unique)
  end

  defp validate_identity(changeset) do
    case {get_field(changeset, :user_id), get_field(changeset, :attendee_identifier)} do
      {nil, nil} ->
        add_error(changeset, :attendee_identifier, "an identity is required")

      {_user_id, attendee_identifier} when not is_nil(attendee_identifier) ->
        validate_length(changeset, :attendee_identifier, min: 1, max: 255)

      _ ->
        changeset
    end
  end
end
