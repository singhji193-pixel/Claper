defmodule ClaperWeb.PwaAuthView do
  use ClaperWeb, :view

  import ClaperWeb.PwaLive.App, only: [app_path: 1, app_path: 2, ngs_icon: 1, ngs_theme_style: 1]

  alias Claper.EventApp
  alias Claper.Events.Event

  def theme_style(%Event{} = event) do
    event.id
    |> EventApp.settings_for_event()
    |> ngs_theme_style()
  end

  def theme_style(_event), do: "--ngs-primary: #f15a24; --ngs-accent: #365a91;"
end
