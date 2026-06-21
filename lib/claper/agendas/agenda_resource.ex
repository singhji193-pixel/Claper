defmodule Claper.Agendas.AgendaResource do
  use Ecto.Schema
  import Ecto.Changeset

  schema "agenda_resources" do
    field :title, :string
    field :kind, :string, default: "link"
    field :url, :string
    field :position, :integer, default: 0
    field :published, :boolean, default: false

    belongs_to :event, Claper.Events.Event
    belongs_to :agenda_item, Claper.Agendas.AgendaItem

    timestamps()
  end

  def changeset(resource, attrs) do
    resource
    |> cast(attrs, [:event_id, :agenda_item_id, :title, :kind, :url, :position, :published])
    |> update_change(:title, &normalize/1)
    |> update_change(:url, &normalize/1)
    |> validate_required([:event_id, :agenda_item_id, :title, :kind, :url, :position])
    |> validate_length(:title, min: 2, max: 120)
    |> validate_length(:url, max: 2_048)
    |> validate_inclusion(:kind, ["pdf", "slides", "recording", "link"])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_https_url()
    |> assoc_constraint(:event)
    |> assoc_constraint(:agenda_item)
    |> check_constraint(:kind, name: :agenda_resources_kind_check)
  end

  defp validate_https_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> []
        _ -> [url: "must be a valid HTTPS URL"]
      end
    end)
  end

  defp normalize(value) when is_binary(value), do: String.trim(value)
  defp normalize(value), do: value
end
