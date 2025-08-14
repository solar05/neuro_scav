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
  end

  scope "/", NeuroScavWeb do
    pipe_through :browser

    live "/", NeuroScavengerLive.Single, :single_scavenger
    live "/neuro_scavengers", NeuroScavengerLive.Neuro, :neuro_scavengers
    live "/single_scavenger", NeuroScavengerLive.Single, :single_scavenger
    live "/team_scavengers", NeuroScavengerLive.Team, :team_scavengers
    live "/statistics", NeuroScavengerLive.Statistics, :statistics
  end

  scope "/api", NeuroScavWeb.Api do
    pipe_through :api

    get "/health", HealthController, :health
  end

  # Other scopes may use custom stacks.
  # scope "/api", NeuroScavWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
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
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
