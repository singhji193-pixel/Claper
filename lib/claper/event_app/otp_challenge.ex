defmodule Claper.EventApp.OtpChallenge do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ["pending", "sent", "verified", "expired", "locked"]
  @delivery_statuses ["pending", "sent", "disabled", "failed"]

  schema "event_app_otp_challenges" do
    field :email, :string
    field :code_hash, :string
    field :status, :string, default: "pending"
    field :attempts_count, :integer, default: 0
    field :max_attempts, :integer, default: 5
    field :expires_at, :utc_datetime
    field :sent_at, :utc_datetime
    field :consumed_at, :utc_datetime
    field :delivery_status, :string, default: "pending"
    field :delivery_error, :string
    field :request_ip, :string
    field :user_agent, :string

    belongs_to :event, Claper.Events.Event

    timestamps()
  end

  @doc false
  def changeset(challenge, attrs) do
    challenge
    |> cast(attrs, [
      :event_id,
      :email,
      :code_hash,
      :status,
      :attempts_count,
      :max_attempts,
      :expires_at,
      :sent_at,
      :consumed_at,
      :delivery_status,
      :delivery_error,
      :request_ip,
      :user_agent
    ])
    |> validate_required([:event_id, :email, :code_hash, :status, :expires_at])
    |> update_change(:email, &normalize_email/1)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:delivery_status, @delivery_statuses)
    |> validate_number(:attempts_count, greater_than_or_equal_to: 0)
    |> validate_number(:max_attempts, greater_than: 0)
  end

  def status_changeset(challenge, attrs) do
    challenge
    |> cast(attrs, [
      :status,
      :attempts_count,
      :sent_at,
      :consumed_at,
      :delivery_status,
      :delivery_error
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:delivery_status, @delivery_statuses)
    |> validate_number(:attempts_count, greater_than_or_equal_to: 0)
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_email(email), do: email
end
