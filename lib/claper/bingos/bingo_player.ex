defmodule Claper.Bingos.BingoPlayer do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          attendee_identifier: String.t(),
          name: String.t(),
          title: String.t() | nil,
          company: String.t() | nil,
          intro: String.t() | nil,
          email: String.t() | nil,
          phone: String.t() | nil,
          linkedin_url: String.t() | nil,
          website_url: String.t() | nil,
          share_title: boolean(),
          share_company: boolean(),
          share_intro: boolean(),
          share_email: boolean(),
          share_phone: boolean(),
          share_linkedin_url: boolean(),
          share_website_url: boolean(),
          code: String.t(),
          event_id: integer(),
          event: Claper.Events.Event.t() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "bingo_players" do
    field :attendee_identifier, :string
    field :name, :string
    field :title, :string
    field :company, :string
    field :intro, :string
    field :email, :string
    field :phone, :string
    field :linkedin_url, :string
    field :website_url, :string
    field :share_title, :boolean, default: false
    field :share_company, :boolean, default: false
    field :share_intro, :boolean, default: false
    field :share_email, :boolean, default: false
    field :share_phone, :boolean, default: false
    field :share_linkedin_url, :boolean, default: false
    field :share_website_url, :boolean, default: false
    field :code, :string

    belongs_to :event, Claper.Events.Event

    timestamps()
  end

  @doc false
  def changeset(player, attrs \\ %{}) do
    player
    |> cast(attrs, [
      :event_id,
      :attendee_identifier,
      :name,
      :title,
      :company,
      :intro,
      :email,
      :phone,
      :linkedin_url,
      :website_url,
      :share_title,
      :share_company,
      :share_intro,
      :share_email,
      :share_phone,
      :share_linkedin_url,
      :share_website_url,
      :code
    ])
    |> update_change(:code, &normalize_code/1)
    |> normalize_profile_urls()
    |> validate_required([:event_id, :attendee_identifier, :name, :code])
    |> validate_profile()
    |> validate_length(:code, min: 4, max: 12)
    |> assoc_constraint(:event)
    |> unique_constraint(:attendee_identifier, name: :bingo_players_event_attendee_unique)
    |> unique_constraint(:code, name: :bingo_players_event_code_unique)
  end

  @doc false
  def name_changeset(player, attrs \\ %{}) do
    profile_changeset(player, attrs)
  end

  @doc false
  def profile_changeset(player, attrs \\ %{}) do
    player
    |> cast(attrs, [
      :name,
      :title,
      :company,
      :intro,
      :email,
      :phone,
      :linkedin_url,
      :website_url,
      :share_title,
      :share_company,
      :share_intro,
      :share_email,
      :share_phone,
      :share_linkedin_url,
      :share_website_url
    ])
    |> normalize_profile_urls()
    |> validate_required([:name])
    |> validate_profile()
  end

  defp normalize_code(nil), do: nil
  defp normalize_code(code), do: code |> String.trim() |> String.upcase()

  defp normalize_profile_urls(changeset) do
    changeset
    |> update_change(:linkedin_url, &normalize_url/1)
    |> update_change(:website_url, &normalize_url/1)
  end

  defp validate_profile(changeset) do
    changeset
    |> validate_length(:name, min: 2, max: 40)
    |> validate_length(:title, max: 80)
    |> validate_length(:company, max: 80)
    |> validate_length(:intro, max: 280)
    |> validate_length(:email, max: 120)
    |> validate_length(:phone, max: 40)
    |> validate_length(:linkedin_url, max: 255)
    |> validate_length(:website_url, max: 255)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "must be a valid email address"
    )
    |> validate_format(:linkedin_url, ~r/^https?:\/\/([^\/]+\.)?linkedin\.com\/.+/i,
      message: "must be a LinkedIn URL"
    )
    |> validate_format(:website_url, ~r/^https?:\/\/[^\s]+\.[^\s]+$/i,
      message: "must be a valid URL"
    )
  end

  defp normalize_url(nil), do: nil

  defp normalize_url(url) do
    url = String.trim(url)

    cond do
      url == "" -> nil
      String.match?(url, ~r/^https?:\/\//i) -> url
      String.match?(url, ~r/^[a-z][a-z0-9+.-]*:/i) -> url
      true -> "https://#{url}"
    end
  end
end
