defmodule Claper.Quizzes.QuizResponse do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          attendee_identifier: String.t() | nil,
          quiz: Claper.Quizzes.Quiz.t() | nil,
          quiz_question: Claper.Quizzes.QuizQuestion.t() | nil,
          quiz_question_opt: Claper.Quizzes.QuizQuestionOpt.t() | nil,
          user: Claper.Accounts.User.t() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "quiz_responses" do
    field :attendee_identifier, :string

    belongs_to :quiz, Claper.Quizzes.Quiz
    belongs_to :quiz_question, Claper.Quizzes.QuizQuestion
    belongs_to :quiz_question_opt, Claper.Quizzes.QuizQuestionOpt
    belongs_to :user, Claper.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(quiz_response, attrs) do
    quiz_response
    |> cast(attrs, [
      :attendee_identifier,
      :user_id,
      :quiz_id,
      :quiz_question_id,
      :quiz_question_opt_id
    ])
    |> validate_required([:quiz_id, :quiz_question_id, :quiz_question_opt_id])
    |> validate_identity()
    |> unique_constraint(:attendee_identifier, name: :quiz_responses_attendee_option_unique)
    |> unique_constraint(:user_id, name: :quiz_responses_user_option_unique)
  end

  defp validate_identity(changeset) do
    if is_nil(get_field(changeset, :user_id)) and
         is_nil(get_field(changeset, :attendee_identifier)) do
      add_error(changeset, :attendee_identifier, "an identity is required")
    else
      changeset
    end
  end
end
