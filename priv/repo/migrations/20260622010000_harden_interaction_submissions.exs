defmodule Claper.Repo.Migrations.HardenInteractionSubmissions do
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM poll_votes older
    USING poll_votes newer
    WHERE older.id < newer.id
      AND older.poll_id = newer.poll_id
      AND older.poll_opt_id = newer.poll_opt_id
      AND (
        (older.attendee_identifier IS NOT NULL AND older.attendee_identifier = newer.attendee_identifier)
        OR (older.user_id IS NOT NULL AND older.user_id = newer.user_id)
      )
    """)

    execute("""
    DELETE FROM quiz_responses older
    USING quiz_responses newer
    WHERE older.id < newer.id
      AND older.quiz_id = newer.quiz_id
      AND older.quiz_question_id = newer.quiz_question_id
      AND older.quiz_question_opt_id = newer.quiz_question_opt_id
      AND (
        (older.attendee_identifier IS NOT NULL AND older.attendee_identifier = newer.attendee_identifier)
        OR (older.user_id IS NOT NULL AND older.user_id = newer.user_id)
      )
    """)

    execute("""
    DELETE FROM form_submits older
    USING form_submits newer
    WHERE older.id < newer.id
      AND older.form_id = newer.form_id
      AND (
        (older.attendee_identifier IS NOT NULL AND older.attendee_identifier = newer.attendee_identifier)
        OR (older.user_id IS NOT NULL AND older.user_id = newer.user_id)
      )
    """)

    execute("""
    UPDATE poll_opts option
    SET vote_count = (
      SELECT COUNT(*) FROM poll_votes vote WHERE vote.poll_opt_id = option.id
    )
    """)

    execute("""
    UPDATE quiz_question_opts option
    SET response_count = (
      SELECT COUNT(*) FROM quiz_responses response WHERE response.quiz_question_opt_id = option.id
    )
    """)

    create unique_index(:poll_votes, [:poll_id, :poll_opt_id, :attendee_identifier],
             where: "attendee_identifier IS NOT NULL",
             name: :poll_votes_attendee_option_unique
           )

    create unique_index(:poll_votes, [:poll_id, :poll_opt_id, :user_id],
             where: "user_id IS NOT NULL",
             name: :poll_votes_user_option_unique
           )

    create unique_index(
             :quiz_responses,
             [:quiz_id, :quiz_question_id, :quiz_question_opt_id, :attendee_identifier],
             where: "attendee_identifier IS NOT NULL",
             name: :quiz_responses_attendee_option_unique
           )

    create unique_index(
             :quiz_responses,
             [:quiz_id, :quiz_question_id, :quiz_question_opt_id, :user_id],
             where: "user_id IS NOT NULL",
             name: :quiz_responses_user_option_unique
           )

    create unique_index(:form_submits, [:form_id, :attendee_identifier],
             where: "attendee_identifier IS NOT NULL",
             name: :form_submits_attendee_unique
           )

    create unique_index(:form_submits, [:form_id, :user_id],
             where: "user_id IS NOT NULL",
             name: :form_submits_user_unique
           )
  end

  def down do
    drop_if_exists index(:form_submits, [:form_id, :user_id], name: :form_submits_user_unique)

    drop_if_exists index(:form_submits, [:form_id, :attendee_identifier],
                     name: :form_submits_attendee_unique
                   )

    drop_if_exists index(
                     :quiz_responses,
                     [:quiz_id, :quiz_question_id, :quiz_question_opt_id, :user_id],
                     name: :quiz_responses_user_option_unique
                   )

    drop_if_exists index(
                     :quiz_responses,
                     [:quiz_id, :quiz_question_id, :quiz_question_opt_id, :attendee_identifier],
                     name: :quiz_responses_attendee_option_unique
                   )

    drop_if_exists index(:poll_votes, [:poll_id, :poll_opt_id, :user_id],
                     name: :poll_votes_user_option_unique
                   )

    drop_if_exists index(:poll_votes, [:poll_id, :poll_opt_id, :attendee_identifier],
                     name: :poll_votes_attendee_option_unique
                   )
  end
end
