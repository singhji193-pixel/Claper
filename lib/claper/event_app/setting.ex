defmodule Claper.EventApp.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @default_home_tagline "Your event companion for schedule, networking, and live moments."
  @hex_color ~r/^#[0-9a-fA-F]{6}$/

  schema "event_app_settings" do
    field :enabled, :boolean, default: true
    field :install_prompt_enabled, :boolean, default: true
    field :ticket_enabled, :boolean, default: false
    field :people_enabled, :boolean, default: false
    field :chat_enabled, :boolean, default: false
    field :live_interactions_enabled, :boolean, default: false
    field :qa_enabled, :boolean, default: false
    field :resources_enabled, :boolean, default: false
    field :sponsors_enabled, :boolean, default: false
    field :primary_color, :string, default: "#C9A84C"
    field :accent_color, :string, default: "#8B6218"
    field :home_tagline, :string, default: @default_home_tagline

    belongs_to :event, Claper.Events.Event

    timestamps()
  end

  def default_home_tagline, do: @default_home_tagline

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [
      :event_id,
      :enabled,
      :install_prompt_enabled,
      :ticket_enabled,
      :people_enabled,
      :chat_enabled,
      :live_interactions_enabled,
      :qa_enabled,
      :resources_enabled,
      :sponsors_enabled,
      :primary_color,
      :accent_color,
      :home_tagline
    ])
    |> validate_required([
      :event_id,
      :enabled,
      :install_prompt_enabled,
      :ticket_enabled,
      :people_enabled,
      :chat_enabled,
      :live_interactions_enabled,
      :qa_enabled,
      :resources_enabled,
      :sponsors_enabled,
      :primary_color,
      :accent_color,
      :home_tagline
    ])
    |> validate_format(:primary_color, @hex_color)
    |> validate_format(:accent_color, @hex_color)
    |> validate_length(:home_tagline, max: 140)
    |> unique_constraint(:event_id, name: :event_app_settings_event_unique)
  end

  def public(%__MODULE__{} = setting) do
    %{
      enabled: setting.enabled,
      install_prompt_enabled: setting.install_prompt_enabled,
      ticket_enabled: setting.ticket_enabled,
      people_enabled: setting.people_enabled,
      chat_enabled: setting.chat_enabled,
      live_interactions_enabled: setting.live_interactions_enabled,
      qa_enabled: setting.qa_enabled,
      resources_enabled: setting.resources_enabled,
      sponsors_enabled: setting.sponsors_enabled,
      theme: %{
        primary_color: setting.primary_color,
        accent_color: setting.accent_color
      },
      home_tagline: setting.home_tagline || @default_home_tagline
    }
  end
end
