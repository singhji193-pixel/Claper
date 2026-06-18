defmodule Claper.HiEvents.Order do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hi_events_orders" do
    field :external_order_id, :string
    field :status, :string, default: "active"
    field :buyer_name, :string
    field :buyer_email, :string
    field :total_cents, :integer
    field :currency, :string
    field :raw_payload, :map, default: %{}

    belongs_to :event, Claper.Events.Event
    belongs_to :integration, Claper.HiEvents.Integration

    timestamps()
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :event_id,
      :integration_id,
      :external_order_id,
      :status,
      :buyer_name,
      :buyer_email,
      :total_cents,
      :currency,
      :raw_payload
    ])
    |> validate_required([
      :event_id,
      :integration_id,
      :external_order_id,
      :status,
      :raw_payload
    ])
    |> update_change(:buyer_email, &normalize_email/1)
    |> validate_format(:buyer_email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> unique_constraint(:external_order_id, name: :hi_events_orders_external_order_unique)
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  defp normalize_email(email), do: email
end
