defmodule ClaperWeb.Router do
  use ClaperWeb, :router

  import ClaperWeb.{UserAuth, EventController}

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {ClaperWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
    plug(ClaperWeb.Plugs.Locale)
  end

  pipeline :admin_required do
    plug(ClaperWeb.Plugs.AdminRequiredPlug)
  end

  pipeline :lti do
    plug(:accepts, ["html", "json"])
    plug(:put_root_layout, html: {ClaperWeb.LayoutView, :root})
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:fetch_current_user)
    plug(ClaperWeb.Plugs.Locale)
  end

  pipeline :protect_mailbox do
    plug ClaperWeb.MailboxGuard
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :pwa_api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(:attendee_identifier)
  end

  pipeline :rate_limit_auth do
    plug ClaperWeb.Plugs.RateLimitPlug,
      max_requests: 10,
      interval_ms: 60_000,
      prefix: "auth"
  end

  # Manage attendee_identifier in requests
  pipeline :attendee_registration do
    plug(:attendee_identifier)
  end

  scope "/", ClaperWeb, host: "app.nextgensummit.co" do
    pipe_through([:browser, :attendee_registration])

    get("/login", PwaAuthController, :new)
    post("/login", PwaAuthController, :create)
    get("/verify", PwaAuthController, :verify)
    post("/verify", PwaAuthController, :verify_code)
    delete("/session", PwaAuthController, :delete)
  end

  live_session :pwa_attendee_vanity do
    scope "/", ClaperWeb, host: "app.nextgensummit.co" do
      pipe_through([:browser, :attendee_registration])

      live("/", PwaLive.App, :home)
      live("/agenda", PwaLive.App, :agenda)
      live("/agenda/:agenda_item_id", PwaLive.App, :session)
      live("/people", PwaLive.App, :people)
      live("/scan", PwaLive.App, :scan)
      live("/bingo", PwaLive.App, :bingo)
      live("/ticket", PwaLive.App, :ticket)
      live("/profile", PwaLive.App, :profile)
    end
  end

  live_session :attendee do
    scope "/", ClaperWeb do
      pipe_through([:browser, :attendee_registration, ClaperWeb.Plugs.Iframe])

      live("/", EventLive.Join, :index)
      live("/join", EventLive.Join, :join)
      live("/e/:code", EventLive.Show, :show)
      live("/e/:code/agenda", EventLive.Agenda, :show)
      live("/e/:code/bingo", EventLive.Bingo, :show)
    end
  end

  scope "/app", ClaperWeb do
    pipe_through([:browser, :attendee_registration])

    get("/:code/login", PwaAuthController, :new)
    post("/:code/login", PwaAuthController, :create)
    get("/:code/verify", PwaAuthController, :verify)
    post("/:code/verify", PwaAuthController, :verify_code)
    delete("/:code/session", PwaAuthController, :delete)
  end

  live_session :pwa_attendee do
    scope "/app", ClaperWeb do
      pipe_through([:browser, :attendee_registration])

      live("/:code", PwaLive.App, :home)
      live("/:code/agenda", PwaLive.App, :agenda)
      live("/:code/agenda/:agenda_item_id", PwaLive.App, :session)
      live("/:code/people", PwaLive.App, :people)
      live("/:code/scan", PwaLive.App, :scan)
      live("/:code/bingo", PwaLive.App, :bingo)
      live("/:code/ticket", PwaLive.App, :ticket)
      live("/:code/profile", PwaLive.App, :profile)
    end
  end

  scope "/api/pwa", ClaperWeb do
    pipe_through([:pwa_api])

    get("/:code/bootstrap", PwaController, :bootstrap)
  end

  scope "/api/integrations", ClaperWeb do
    pipe_through([:api])

    post("/hi-events/webhook", HiEventsWebhookController, :create)
    post("/hievents/events", HiEventsWebhookController, :create)
  end

  live_session :user,
    root_layout: {ClaperWeb.LayoutView, :user} do
    scope "/", ClaperWeb do
      pipe_through([:browser, :require_authenticated_user])

      post "/export/forms/:form_id", StatController, :export_form
      post "/export/polls/:poll_id", StatController, :export_poll
      post "/export/quizzes/:quiz_id", StatController, :export_quiz
      post "/export/quizzes/:quiz_id/qti", StatController, :export_quiz_qti
      post "/export/:event_id/messages", StatController, :export_all_messages
      post "/export/:event_id/bingo", StatController, :export_bingo

      live("/events", EventLive.Index, :index)
      live("/events/new", EventLive.Index, :new)
      live("/events/:id/edit", EventLive.Index, :edit)
      live("/events/:id/stats", StatLive.Index, :index)

      live("/users/settings", UserSettingsLive.Show, :show)
      live("/users/settings/edit/password", UserSettingsLive.Show, :edit_password)
      live("/users/settings/edit/email", UserSettingsLive.Show, :edit_email)
      live("/users/settings/set/password", UserSettingsLive.Show, :set_password)
    end
  end

  live_session :presenter, on_mount: ClaperWeb.UserLiveAuth do
    scope "/", ClaperWeb do
      pipe_through([:browser, :require_authenticated_user])

      live("/e/:code/presenter", EventLive.Presenter, :show)
      live("/e/:code/manage", EventLive.Manage, :show)
      live("/e/:code/manage/add/poll", EventLive.Manage, :add_poll)
      live("/e/:code/manage/edit/poll/:id", EventLive.Manage, :edit_poll)
      live("/e/:code/manage/add/form", EventLive.Manage, :add_form)
      live("/e/:code/manage/import", EventLive.Manage, :import)
      live("/e/:code/manage/edit/form/:id", EventLive.Manage, :edit_form)
      live("/e/:code/manage/add/embed", EventLive.Manage, :add_embed)
      live("/e/:code/manage/edit/embed/:id", EventLive.Manage, :edit_embed)
      live("/e/:code/manage/add/quiz", EventLive.Manage, :add_quiz)
      live("/e/:code/manage/edit/quiz/:id", EventLive.Manage, :edit_quiz)
      live("/e/:code/manage/agenda", EventLive.AgendaManage, :index)
      live("/e/:code/manage/agenda/new", EventLive.AgendaManage, :new)
      live("/e/:code/manage/agenda/:id/edit", EventLive.AgendaManage, :edit)
      live("/e/:code/manage/bingo", EventLive.BingoManage, :index)
      live("/e/:code/manage/bingo/new", EventLive.BingoManage, :new)
      live("/e/:code/manage/bingo/:id/edit", EventLive.BingoManage, :edit)
      live("/e/:code/manage/app", EventLive.AppManage, :index)
    end
  end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through(:browser)
      live_dashboard("/dashboard", metrics: ClaperWeb.Telemetry)
    end
  end

  # Enables the Swoosh mailbox preview in development.
  #
  # Note that preview only shows emails that were sent by the same
  # node running the Phoenix server.
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through [:browser, :protect_mailbox]
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  ## Authentication routes
  scope "/", ClaperWeb do
    pipe_through([:browser, :redirect_if_user_is_authenticated, :rate_limit_auth])

    get("/users/register", UserRegistrationController, :new)
    post("/users/register", UserRegistrationController, :create)

    get("/users/register/confirm", UserRegistrationController, :confirm)
    get("/users/log_in", UserSessionController, :new)
    post("/users/log_in", UserSessionController, :create)
    get("/users/magic/:token", UserConfirmationController, :confirm_magic)
    get("/users/reset_password", UserResetPasswordController, :new)
    post("/users/reset_password", UserResetPasswordController, :create)
    get("/users/reset_password/:token", UserResetPasswordController, :edit)
    post("/users/reset_password/:token", UserResetPasswordController, :update)

    get("/users/confirm", UserConfirmationController, :new)
    post("/users/confirm", UserConfirmationController, :create)
    get("/users/confirm/:token", UserConfirmationController, :update)

    get("/users/oidc", UserOidcAuth, :new)
    get("/users/oidc/callback", UserOidcAuth, :callback)
  end

  scope "/", ClaperWeb do
    pipe_through([:lti])

    get("/.well-known/jwks.json", Lti.RegistrationController, :jwks)
    get("/lti/register", Lti.RegistrationController, :new)
    post("/lti/register", Lti.RegistrationController, :create)
    post("/lti/login", Lti.LaunchController, :login)
    get("/lti/login", Lti.LaunchController, :login)
    post("/lti/launch", Lti.LaunchController, :launch)
  end

  scope "/", ClaperWeb do
    pipe_through([:browser, :require_authenticated_user])

    post("/events/:uuid/slide.jpg", EventController, :slide_generate)
    get("/users/settings/confirm_email/:token", UserSettingsController, :confirm_email)
    delete("/users/register/delete", UserRegistrationController, :delete)
  end

  scope "/", ClaperWeb do
    pipe_through([:browser])

    get("/tos", PageController, :tos)
    get("/privacy", PageController, :privacy)

    delete("/users/log_out", UserSessionController, :delete)
  end

  # Admin panel routes - LiveView implementation
  live_session :admin, root_layout: {ClaperWeb.LayoutView, :admin} do
    scope "/admin", ClaperWeb.AdminLive do
      pipe_through [:browser, :require_authenticated_user, :admin_required]

      live "/", DashboardLive, :index

      live "/users", UserLive, :index
      live "/users/new", UserLive, :new
      live "/users/:id/edit", UserLive, :edit
      live "/users/:id", UserLive, :show

      live "/events", EventLive, :index
      live "/events/new", EventLive, :new
      live "/events/:id/edit", EventLive, :edit
      live "/events/:id", EventLive, :show

      live "/agenda", AgendaLive, :index
      live "/agenda/new", AgendaLive, :new
      live "/agenda/:id/edit", AgendaLive, :edit

      live "/oidc_providers", OidcProviderLive, :index
      live "/oidc_providers/new", OidcProviderLive, :new
      live "/oidc_providers/:id/edit", OidcProviderLive, :edit
      live "/oidc_providers/:id", OidcProviderLive, :show

      live "/audit_logs", AuditLogLive, :index
      live "/audit_logs/:id", AuditLogLive, :show
    end
  end
end
