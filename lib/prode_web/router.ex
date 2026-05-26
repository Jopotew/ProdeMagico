defmodule ProdeWeb.Router do
  use ProdeWeb, :router

  import ProdeWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ProdeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug ProdeWeb.Plugs.ApiAuth
  end

  # ── Main app (5-tab mobile interface) ────────────────────────────────
  scope "/", ProdeWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :app,
      on_mount: [
        {ProdeWeb.UserAuth, :require_authenticated},
        {ProdeWeb.LiveHelpers, :default}
      ],
      layout: {ProdeWeb.Layouts, :mobile} do
      live "/", PronosticosLive, :index
      live "/posiciones", PosicionesLive, :index
      live "/torneos", TorneosLive, :index
      live "/torneos/:tournament_id/bonus", BonusLive, :index
      live "/join/:code", JoinLive, :index
      live "/fixture", FixtureLive, :index
      live "/mas", MasLive, :index
    end
  end

  # Public API endpoints
  scope "/api/v1", ProdeWeb.Api do
    pipe_through :api

    resources "/tournaments", TournamentsController, only: [:index, :show]
    get "/matches", MatchesController, :index
    get "/matches/:id", MatchesController, :show
  end

  # Authenticated API endpoints
  scope "/api/v1", ProdeWeb.Api do
    pipe_through :api_authenticated

    post "/matches/:id/predict", MatchesController, :predict

    resources "/groups", GroupsController, only: [:index, :create, :show]
    post "/groups/join", GroupsController, :join
    get "/groups/:id/leaderboard", GroupsController, :leaderboard

    get "/users/me", UsersController, :me
    get "/users/me/predictions", UsersController, :predictions
    post "/users/me/push-subscription", UsersController, :push_subscription
  end

  # ── Admin routes ─────────────────────────────────────────────────────────
  scope "/admin", ProdeWeb.Admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin]

    live_session :admin,
      on_mount: [
        {ProdeWeb.UserAuth, :require_authenticated},
        {ProdeWeb.UserAuth, :require_admin}
      ] do
      live "/import", MatchImportLive, :index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:prode, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ProdeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Google OAuth routes
  scope "/auth", ProdeWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  ## Authentication routes

  scope "/", ProdeWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ProdeWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/profile", ProfileLive, :show
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", ProdeWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{ProdeWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
