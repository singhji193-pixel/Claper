defmodule ClaperWeb.Component.Alert do
  use ClaperWeb, :view_component

  def info(assigns) do
    assigns =
      assigns
      |> assign_new(:stick, fn -> false end)
      |> assign(:tone, :info)
      |> assign(:role, "status")
      |> assign(:live, "polite")

    notification(assigns)
  end

  def error(assigns) do
    assigns =
      assigns
      |> assign_new(:stick, fn -> false end)
      |> assign(:tone, :error)
      |> assign(:role, "alert")
      |> assign(:live, "assertive")

    notification(assigns)
  end

  defp notification(assigns) do
    ~H"""
    <div
      class={"claper-flash claper-flash--#{@tone}"}
      role={@role}
      aria-live={@live}
      aria-atomic="true"
      x-data="{ open: true }"
      x-show={if @stick, do: "true", else: "open"}
      x-init="setTimeout(() => {open = false}, 7000)"
      x-transition
    >
      <div class="claper-flash__icon" aria-hidden="true">
        <svg :if={@tone == :info} viewBox="0 0 24 24" fill="none">
          <path
            d="M20 6 9 17l-5-5"
            stroke="currentColor"
            stroke-width="2.4"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
        <svg :if={@tone == :error} viewBox="0 0 24 24" fill="none">
          <path
            d="M12 8v5m0 3.5v.01M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
            stroke="currentColor"
            stroke-width="2.2"
            stroke-linecap="round"
          />
        </svg>
      </div>

      <p class="claper-flash__message">{@message}</p>

      <button
        type="button"
        class="claper-flash__dismiss"
        aria-label="Dismiss notification"
        x-on:click="open = false"
      >
        <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <path
            d="m7 7 10 10M17 7 7 17"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
          />
        </svg>
      </button>
    </div>
    """
  end
end
