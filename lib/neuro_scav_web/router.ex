defmodule NeuroScavWeb.Router do
  use NeuroScavWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NeuroScavWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug NeuroScavWeb.Plugs.SetLocale
    plug NeuroScavWeb.Plugs.SetUserId
  end

  pipeline :api do
    plug CORSPlug, origin: &NeuroScavWeb.Router.cors_origins/0
    plug :accepts, ["json"]
    plug :fetch_session
    plug NeuroScavWeb.Plugs.SetLocale
    plug NeuroScavWeb.Plugs.RateLimit, limit: 200, window_ms: 60_000
  end

  # Pipeline for image endpoints fetched by crawlers (og:image, etc.).
  # No plug :accepts — Telegram and other bots send arbitrary Accept headers
  # (image/*, image/png, */*) and should never get a 406.
  pipeline :image do
  end

  scope "/", NeuroScavWeb do
    pipe_through :browser

    live "/", NeuroScavengerLive.Single, :single_scavenger
    live "/neuro_scavengers", NeuroScavengerLive.Neuro, :neuro_scavengers
    live "/team_scavengers", NeuroScavengerLive.Team, :team_scavengers
    live "/statistics", NeuroScavengerLive.Statistics, :statistics
    live "/glossary", NeuroScavengerLive.Glossary, :glossary
    live "/wheel", NeuroScavengerLive.Wheel, :wheel

    get "/share/:token", ShareController, :show
  end

  scope "/", NeuroScavWeb do
    pipe_through :image

    get "/share/:token/image", ShareController, :og_image
  end

  scope "/api", NeuroScavWeb.Api do
    pipe_through :api

    get "/health", HealthController, :health
    post "/generate_single", ScavengersController, :generate_single
    post "/generate_team", ScavengersController, :generate_team
    get "/stats", ScavengersController, :stats

    # CORS preflight: CORSPlug halts before the action, this only catches stray OPTIONS
    options "/*path", HealthController, :options
  end

  @doc false
  def cors_origins, do: Application.get_env(:neuro_scav, :cors_origins, [])

  # Other scopes may use custom stacks.
  # scope "/api", NeuroScavWeb do
  #   pipe_through :api
  # end

  if Application.compile_env(:neuro_scav, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: NeuroScavWeb.Telemetry
    end
  end
end
