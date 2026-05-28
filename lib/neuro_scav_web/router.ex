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
    plug :accepts, ["json"]
    plug :fetch_session
    plug NeuroScavWeb.Plugs.SetLocale
    plug NeuroScavWeb.Plugs.RateLimit, limit: 200, window_ms: 60_000
  end

  # Minimal pipeline for static assets served by controllers (e.g. og:image).
  # Must not have plug :accepts, ["html"] — crawlers request these with Accept: image/*
  pipeline :image do
    plug :accepts, ["html", "png", "jpg", "jpeg", "gif", "webp"]
  end

  scope "/", NeuroScavWeb do
    pipe_through :browser

    live "/", NeuroScavengerLive.Single, :single_scavenger
    live "/neuro_scavengers", NeuroScavengerLive.Neuro, :neuro_scavengers
    live "/single_scavenger", NeuroScavengerLive.Single, :single_scavenger
    live "/team_scavengers", NeuroScavengerLive.Team, :team_scavengers
    live "/statistics", NeuroScavengerLive.Statistics, :statistics
    live "/glossary", NeuroScavengerLive.Glossary, :glossary

    get "/share/:token", ShareController, :show
  end

  scope "/", NeuroScavWeb do
    pipe_through :image

    get "/share/:token/image", ShareController, :og_image
  end

  scope "/api", NeuroScavWeb.Api do
    pipe_through :api

    get "/health", HealthController, :health
    get "/generate_single", ScavengersController, :generate_single
    get "/generate_team", ScavengersController, :generate_team
    get "/stats", ScavengersController, :stats
  end

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
