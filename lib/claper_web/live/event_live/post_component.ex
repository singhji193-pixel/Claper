defmodule ClaperWeb.EventLive.PostComponent do
  use ClaperWeb, :live_component

  def render(assigns) do
    ~H"""
    <div id={@id} class="claper-chat-row">
      <%= if @post.attendee_identifier == @attendee_identifier || (not is_nil(@current_user) && @post.user_id == @current_user.id) do %>
        <div class="claper-chat-bubble claper-chat-bubble--mine relative z-0 text-white">
          <button
            phx-click={
              JS.toggle(
                to: "#post-menu-#{@post.id}",
                out: "animate__animated animate__fadeOut",
                in: "animate__animated animate__fadeIn"
              )
            }
            phx-click-away={
              JS.hide(to: "#post-menu-#{@post.id}", transition: "animate__animated animate__fadeOut")
            }
            class="claper-chat-menu-button"
            aria-label={gettext("Message options")}
          >
            <img src="/images/icons/ellipsis-horizontal-white.svg" class="h-5" alt="" />
          </button>

          <%= if @post.name || leader?(@post, @event, @leaders) || pinned?(@post) do %>
            <div class="claper-chat-meta">
              <%= if @post.name do %>
                <p class="claper-chat-author">{@post.name}</p>
              <% end %>
              <%= if leader?(@post, @event, @leaders) do %>
                <div class="claper-chat-badge claper-chat-badge--host">
                  <img src="/images/icons/star.svg" class="h-3" alt="" />
                  <span>{gettext("Host")}</span>
                </div>
              <% end %>

              <%= if pinned?(@post) do %>
                <div class="claper-chat-badge claper-chat-badge--pinned">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="icon icon-tabler icon-tabler-pin-filled"
                    width="12"
                    height="12"
                    viewBox="0 0 24 24"
                    stroke-width="2"
                    stroke="currentColor"
                    fill="none"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path stroke="none" d="M0 0h24v24H0z" fill="none"></path>
                    <path
                      d="M15.113 3.21l.094 .083l5.5 5.5a1 1 0 0 1 -1.175 1.59l-3.172 3.171l-1.424 3.797a1 1 0 0 1 -.158 .277l-.07 .08l-1.5 1.5a1 1 0 0 1 -1.32 .082l-.095 -.083l-2.793 -2.792l-3.793 3.792a1 1 0 0 1 -1.497 -1.32l.083 -.094l3.792 -3.793l-2.792 -2.793a1 1 0 0 1 -.083 -1.32l.083 -.094l1.5 -1.5a1 1 0 0 1 .258 -.187l.098 -.042l3.796 -1.425l3.171 -3.17a1 1 0 0 1 1.497 -1.26z"
                      stroke-width="0"
                      fill="currentColor"
                    >
                    </path>
                  </svg>
                  <span>{gettext("Pinned")}</span>
                </div>
              <% end %>
            </div>
          <% end %>

          <div id={"post-menu-#{@post.id}"} class="claper-chat-menu hidden animate__faster">
            <span class="text-red-500">
              {link(gettext("Delete"),
                to: "#",
                phx_click: "delete",
                phx_value_id: @post.uuid,
                phx_value_event_id: @event.uuid,
                data: [confirm: gettext("Are you sure?")]
              )}
            </span>
          </div>
          <p class="claper-chat-body">{ClaperWeb.Helpers.format_body(@post.body)}</p>

          <div class="claper-chat-reaction-summary">
            <%= if @post.like_count > 0 do %>
              <div class="claper-chat-reaction-count">
                <img src="/images/icons/thumb.svg" class="h-4" alt="" />
                <span>{@post.like_count}</span>
              </div>
            <% end %>
            <%= if @post.love_count > 0 do %>
              <div class="claper-chat-reaction-count">
                <img src="/images/icons/heart.svg" class="h-4" alt="" />
                <span>{@post.love_count}</span>
              </div>
            <% end %>
            <%= if @post.lol_count > 0 do %>
              <div class="claper-chat-reaction-count">
                <img src="/images/icons/laugh.svg" class="h-4" alt="" />
                <span>{@post.lol_count}</span>
              </div>
            <% end %>
          </div>
        </div>
      <% else %>
        <div class="claper-chat-bubble claper-chat-bubble--other relative z-0 text-black">
          <%= if @post.name || leader?(@post, @event, @leaders) || pinned?(@post) do %>
            <div class="claper-chat-meta">
              <%= if @post.name do %>
                <p class="claper-chat-author">{@post.name}</p>
              <% end %>
              <%= if leader?(@post, @event, @leaders) do %>
                <div class="claper-chat-badge claper-chat-badge--host">
                  <img src="/images/icons/star.svg" class="h-3" alt="" />
                  <span>{gettext("Host")}</span>
                </div>
              <% end %>
              <%= if pinned?(@post) do %>
                <div class="claper-chat-badge claper-chat-badge--pinned">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="12"
                    height="12"
                    viewBox="0 0 24 24"
                    fill="currentColor"
                    aria-hidden="true"
                  >
                    <path d="M15.113 3.21l.094.083 5.5 5.5a1 1 0 0 1-1.175 1.59l-3.172 3.171-1.424 3.797a1 1 0 0 1-.158.277l-.07.08-1.5 1.5a1 1 0 0 1-1.32.082l-.095-.083L9 16.415l-3.793 3.792a1 1 0 0 1-1.497-1.32l.083-.094L7.585 15l-2.792-2.793a1 1 0 0 1-.083-1.32l.083-.094 1.5-1.5a1 1 0 0 1 .258-.187l.098-.042 3.796-1.425 3.171-3.17a1 1 0 0 1 1.497-1.26Z" />
                  </svg>
                  <span>{gettext("Pinned")}</span>
                </div>
              <% end %>
            </div>
          <% end %>

          <%= if @is_leader do %>
            <button
              phx-click={
                JS.toggle(
                  to: "#post-menu-#{@post.id}",
                  out: "animate__animated animate__fadeOut",
                  in: "animate__animated animate__fadeIn"
                )
              }
              phx-click-away={
                JS.hide(
                  to: "#post-menu-#{@post.id}",
                  transition: "animate__animated animate__fadeOut"
                )
              }
              class="claper-chat-menu-button"
              aria-label={gettext("Message options")}
            >
              <img src="/images/icons/ellipsis-horizontal.svg" class="h-5" alt="" />
            </button>
            <div id={"post-menu-#{@post.id}"} class="claper-chat-menu claper-chat-menu--dark hidden">
              <span class="text-red-500">
                {link(gettext("Delete"),
                  to: "#",
                  phx_click: "delete",
                  phx_value_id: @post.uuid,
                  phx_value_event_id: @event.uuid,
                  data: [confirm: gettext("Are you sure?")]
                )}
              </span>
            </div>
          <% end %>

          <p class="claper-chat-body">{ClaperWeb.Helpers.format_body(@post.body)}</p>

          <div class="claper-chat-reactions">
            <%= if @reaction_enabled do %>
              <%= if not Enum.member?(@liked_posts, @post.id) do %>
                <button
                  phx-click="react"
                  phx-value-type="👍"
                  phx-value-post-id={@post.uuid}
                  class="claper-chat-reaction"
                  aria-label={gettext("Like message")}
                  aria-pressed="false"
                >
                  <img src="/images/icons/thumb.svg" class="h-4" alt="" />
                  <%= if @post.like_count > 0 do %>
                    <span class="ml-1">{@post.like_count}</span>
                  <% end %>
                </button>
              <% else %>
                <button
                  phx-click="unreact"
                  phx-value-type="👍"
                  phx-value-post-id={@post.uuid}
                  class="claper-chat-reaction is-active"
                  aria-label={gettext("Remove like from message")}
                  aria-pressed="true"
                >
                  <span>
                    <img src="/images/icons/thumb.svg" class="h-4" alt="" />
                  </span>
                  <%= if @post.like_count > 0 do %>
                    <span class="ml-1">{@post.like_count}</span>
                  <% end %>
                </button>
              <% end %>
              <%= if not Enum.member?(@loved_posts, @post.id) do %>
                <button
                  phx-click="react"
                  phx-value-type="❤️"
                  phx-value-post-id={@post.uuid}
                  class="claper-chat-reaction"
                  aria-label={gettext("Love message")}
                  aria-pressed="false"
                >
                  <img src="/images/icons/heart.svg" class="h-4" alt="" />
                  <%= if @post.love_count > 0 do %>
                    <span class="ml-1">{@post.love_count}</span>
                  <% end %>
                </button>
              <% else %>
                <button
                  phx-click="unreact"
                  phx-value-type="❤️"
                  phx-value-post-id={@post.uuid}
                  class="claper-chat-reaction is-active"
                  aria-label={gettext("Remove love from message")}
                  aria-pressed="true"
                >
                  <img src="/images/icons/heart.svg" class="h-4" alt="" />
                  <%= if @post.love_count > 0 do %>
                    <span class="ml-1">{@post.love_count}</span>
                  <% end %>
                </button>
              <% end %>
              <%= if not Enum.member?(@loled_posts, @post.id) do %>
                <button
                  phx-click="react"
                  phx-value-type="😂"
                  phx-value-post-id={@post.uuid}
                  class="claper-chat-reaction"
                  aria-label={gettext("Laugh at message")}
                  aria-pressed="false"
                >
                  <img src="/images/icons/laugh.svg" class="h-4" alt="" />
                  <%= if @post.lol_count > 0 do %>
                    <span class="ml-1">{@post.lol_count}</span>
                  <% end %>
                </button>
              <% else %>
                <button
                  phx-click="unreact"
                  phx-value-type="😂"
                  phx-value-post-id={@post.uuid}
                  class="claper-chat-reaction is-active"
                  aria-label={gettext("Remove laugh from message")}
                  aria-pressed="true"
                >
                  <img src="/images/icons/laugh.svg" class="h-4" alt="" />
                  <%= if @post.lol_count > 0 do %>
                    <span class="ml-1">{@post.lol_count}</span>
                  <% end %>
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp leader?(post, event, leaders) do
    !is_nil(post.user_id) &&
      (post.user_id == event.user_id ||
         Enum.any?(leaders, fn leader ->
           leader.user_id == post.user_id
         end))
  end

  defp pinned?(post), do: post.pinned
end
