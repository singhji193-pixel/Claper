defmodule ClaperWeb.PwaAuthView do
  use ClaperWeb, :view

  import ClaperWeb.PwaLive.App, only: [pwa_icon: 1, pwa_theme_style: 1]

  alias Claper.EventApp
  alias Claper.Events.Event

  def theme_style(%Event{} = event) do
    event.id
    |> EventApp.settings_for_event()
    |> pwa_theme_style()
  end

  def theme_style(_event), do: "--pwa-primary: #f15a24; --pwa-accent: #365a91;"
end
