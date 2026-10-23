# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**NeuroScav** is a Phoenix 1.7+ web application for neural scavenger hunts. It provides real-time AI-powered scavenger hunt functionality with single-player and team-based modes, powered by Ollama for local LLM inference. The app uses PostgreSQL for persistence, Phoenix LiveView for real-time updates, and GenServers for coordination of stateful operations.

**Tech Stack:**
- **Framework**: Phoenix 1.7.21+, Elixir 1.14+
- **Database**: PostgreSQL with Ecto ORM
- **Real-time**: LiveView + PubSub
- **UI**: Tailwind CSS + Heroicons
- **AI**: Ollama (local LLM)
- **Server**: Bandit
- **HTTP**: Req (built-in)
- **Monitoring**: PromEx for Prometheus metrics
- **Linting**: Credo

## Essential Commands

### Setup & Development
```bash
mix setup              # Install deps, create DB, migrate, setup assets
mix phx.server        # Start development server (http://localhost:4000)
iex -S mix phx.server # Start server with interactive shell
mix deps.get          # Install dependencies only
mix ecto.create       # Create database
mix ecto.migrate      # Run pending migrations
```

### Testing
```bash
mix test              # Run all tests
mix test --failed     # Re-run only previously failed tests
mix test test/path/to/test.exs  # Run single test file
mix coveralls         # Run tests with coverage report
mix coveralls.html    # Generate HTML coverage report (opens in browser)
```

### Code Quality
```bash
mix format            # Format all code
mix credo             # Run linter (strict mode)
mix precommit         # Run format + credo strict (use before committing)
```

### Asset Management
```bash
mix assets.build      # Build CSS and JavaScript
mix assets.deploy     # Build minified assets for production
```

### Database
```bash
mix ecto.reset        # Drop and recreate database with migrations and seeds
mix ecto.rollback [--step 1]  # Rollback migrations
mix ecto.gen.migration name_of_migration  # Create new migration
```

### Debugging
```bash
mix phx.gen.secret    # Generate random secret for SECRET_KEY_BASE
mix raid.sim          # Simulate raids to tune their balance (dev only; see `mix help raid.sim`)
mix raid.sim --strategy greedy --events --seed 42  # one strategy, per-event table, reproducible
```

## Architecture Overview

### Layered Architecture

**Web Layer** (`lib/neuro_scav_web/`)
- LiveView modules handle user interactions and real-time updates
- Plugs for cross-cutting concerns (locale, user ID, rate limiting)
- Components and layouts for reusable UI patterns
- REST API endpoints via controllers

**Coordination Layer** (GenServers in `lib/neuro_scav/servers/`)
- **ScavengersServer**: Generates individual and team scavengers, applies rarity calculation
- **StatsCounterServer**: Aggregates statistics counters by rarity level
- **UserRequestsServer**: Manages user request lifecycle and state

**Business Logic Layer** (`lib/neuro_scav/`)
- **Client**: Integrates with Ollama for AI-powered scavenger generation
- **Scavengers Context**: Database operations and queries
- **PubSub**: Event broadcasting for real-time updates across connections
- **Locale**: Language/translation setup

**Data Layer**
- Ecto schemas and migrations
- PostgreSQL database
- Repo provides all database access

### Data Flow Example: Scavenger Generation

1. User clicks "Generate" in LiveView → handler calls `ScavengersServer.generate_single/2`
2. Server generates scavenger with rarity calculation (deterministic, based on name properties)
3. `StatsCounterServer.update_counter(:rarity)` increments the appropriate counter
4. PubSub broadcasts statistics update to subscribed LiveViews
5. All connected clients receive real-time update without page refresh

### Key Design Patterns

**GenServer-based Concurrency**: All stateful operations (scavenger generation, stats) use GenServers for safe concurrent access and state consistency.

**PubSub Broadcasting**: Decouples producers from consumers, enabling real-time updates across multiple LiveViews without tight coupling.

**Deterministic Rarity Calculation**: The rarity algorithm is pure (no randomness), based on name properties:
- **Legendary**: Name is in hardcoded list
- **Epic**: First and last names share same last 3 characters
- **Rare**: First and last names start with same character
- **Uncommon**: First and last names have equal length
- **Common**: Default fallback

This enables reproducible results and fast computation. The one random exception is the **gnome**: any generated scavenger is replaced by the gnome with a 1 in 2000 chance (`ScavengersServer.gnome_odds/0`); in battle its card beats every other card.

## Project Structure

```
lib/neuro_scav/
├── servers/              # GenServer-based coordinators
│   ├── scavengers_server.ex
│   ├── stats_counter_server.ex
│   └── user_requests_server.ex
├── scavengers/          # Domain logic and schemas
│   ├── names.ex         # Name generation
│   └── statistics.ex    # Statistics schema
├── client.ex            # Ollama AI integration
├── pub_sub.ex           # PubSub event system
├── locale.ex            # i18n setup
├── application.ex       # OTP supervision tree
└── repo.ex              # Ecto repository

lib/neuro_scav_web/
├── live/                # Phoenix LiveView modules
│   └── neuro_scavenger_live/
│       ├── single.ex    # Single-player hunt
│       ├── team.ex      # Team hunt
│       ├── neuro.ex     # AI-powered hunt
│       ├── statistics.ex # Real-time stats dashboard
│       └── glossary.ex  # Item glossary
├── controllers/         # REST API and Share endpoints
├── components/          # Reusable UI components
├── plugs/              # HTTP middleware
├── router.ex           # Route definitions
└── endpoint.ex         # Phoenix endpoint config
```

## Important Configuration

**Environment Variables** (.env.local for development):
```bash
NEURO_MODEL_API_URL=http://localhost:11434/api  # Ollama endpoint
TURNSTILE_SITE_KEY=...                          # CAPTCHA (optional for dev)
TURNSTILE_SECRET_KEY=...
DATABASE_URL=...                                # PostgreSQL (runtime)
```

**Multi-language Support**: Application supports English, Russian, German, and Japanese. Translations are in `priv/gettext/` using Gettext.

**Rate Limiting**: API endpoint `/api` has rate limit of 200 requests per 60 seconds via Hammer ETS backend.

## LiveView Guidelines (Phoenix v1.8)

- Always begin LiveView templates with `<Layouts.app flash={@flash} ...>` wrapping all inner content
- Use `<.icon name="hero-x-mark" class="..."/>` for icons — never use `Heroicons` module directly
- Use the imported `<.input>` component from `core_components.ex` for form inputs (overriding `class` replaces all defaults)
- Pass `current_scope` to `<Layouts.app>` for authenticated routes — fix missing `current_scope` errors by placing routes in the correct `live_session`
- `<.flash_group>` is **forbidden** outside `layouts.ex`

## Elixir Guidelines

- **Always** use `mix precommit` before committing code
- **Always** use `Req` library for HTTP requests (available by default; avoid httpoison, tesla, httpc)
- Never use `String.to_atom/1` on user input (memory leak)
- Access list elements with `Enum.at/2` or pattern matching — never bracket syntax `list[i]`
- Bind the result of `if`/`case`/`cond` to a variable outside; you cannot rebind inside the block:
  ```elixir
  # VALID
  socket = if connected?(socket), do: assign(socket, :val, val), else: socket
  ```
- Never nest multiple modules in the same file (causes cyclic dependency / compile errors)
- Never use map access syntax (`changeset[:field]`) on structs — use `my_struct.field` or `Ecto.Changeset.get_field/2`
- Predicate function names must end with `?`, not start with `is_`
- For concurrent enumeration with backpressure: `Task.async_stream(collection, callback, timeout: :infinity)`
- Use `mix help TASK` before running unfamiliar tasks

## Ecto Guidelines

- Always preload associations in queries before accessing them in templates
- `Ecto.Schema` fields always use `:string` type, even for text columns
- Use `Ecto.Changeset.get_field(changeset, :field)` to read changeset values — never `changeset[:field]`
- Fields set programmatically (e.g., `user_id`) must **not** appear in `cast` calls; set them explicitly on the struct
- Always use `mix ecto.gen.migration migration_name` to generate migration files

## Phoenix Guidelines

- Router `scope` blocks provide an alias prefix — never add your own `alias` for routes within a scope to avoid duplicate module prefixes
- `Phoenix.View` is not included in Phoenix 1.7+ — do not use it

## Testing Notes

- Use `start_supervised!/1` to start processes in tests (guarantees cleanup)
- Avoid `Process.sleep/1` — use `Process.monitor/1` and assert on the `{:DOWN, ...}` message
- Use `_ = :sys.get_state(pid)` to ensure a process has handled prior messages before the next assertion
- Run specific file: `mix test test/path/to/test.exs`; re-run failures: `mix test --failed`

Coverage target: >80% using ExCoveralls. Run `mix coveralls.html` to see detailed report.

## Monitoring & Metrics

PromEx provides Prometheus metrics at `/metrics` endpoint. Tracks:
- Request latency
- Scavenger generation time
- Statistics update frequency
- Database query performance

## Common Tasks

**Generate a single scavenger** (test in IEx):
```elixir
iex> NeuroScav.ScavengersServer.generate_single(:en)
%{"name" => "John Smith", "rarity" => "uncommon"}
```

**Update statistics**:
```elixir
iex> NeuroScav.StatsCounterServer.update_counter(:legendary)
iex> NeuroScav.StatsCounterServer.update_multiple_counters([:rare, :uncommon, :common])
```

**Get current statistics**:
```elixir
iex> NeuroScav.Scavengers.get_statistics()
```

**Subscribe to PubSub events** (in LiveView):
```elixir
PubSub.subscribe(:single_scavenger, %{"user_id" => user_id})
```

## API Endpoints

- `GET /api/health` - Health check
- `GET /api/generate_single?lang=en` - Generate single scavenger
- `GET /api/generate_team?lang=en` - Generate team of 5 scavengers
- `GET /api/stats` - Get aggregated statistics
- `GET /api/check_name?name=First Last` - Rarity and battle card stats of a name

## When Modifying This Codebase

- **Adding a LiveView**: Use the `Single` module as a template; remember to subscribe to PubSub in `mount/3` if real-time updates are needed
- **Adding a GenServer**: Follow patterns in `servers/` directory; always implement `init/1` and message handlers with `handle_call/3` or `handle_cast/2`
- **Database changes**: Always use `mix ecto.gen.migration` for new migrations; follow Ecto conventions
- **API endpoints**: Add routes to `router.ex` and handlers to `controllers/api/`
- **UI components**: Place in `components/` directory and import via `lib/neuro_scav_web.ex`
