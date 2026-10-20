# NeuroScav

[![CI](https://github.com/solar05/neuro_scav/actions/workflows/build.yml/badge.svg)](https://github.com/solar05/neuro_scav/actions/workflows/build.yml)
[![codecov](https://codecov.io/github/solar05/neuro_scav/graph/badge.svg?token=BV9QGO1UOV)](https://codecov.io/github/solar05/neuro_scav)

A Phoenix-based web application for neural scavenger hunts. NeuroScav provides real-time AI-powered scavenger hunt functionality with support for single players, teams, and comprehensive statistics tracking.

## Features

- **Single Scavenger Mode**: Individual players can participate in neural scavenger hunts
- **Team Scavengers Mode**: Collaborative team-based scavenger hunts with real-time updates
- **Neural AI Integration**: Powered by [Ollama](https://ollama.ai) 
- **Live Statistics**: Real-time statistics tracking and aggregation with PubSub
- **Multi-language Support**: Built-in i18n support for English, Russian, German, and Japanese

## Tech Stack

- **Framework**: [Phoenix](https://www.phoenixframework.org/) 1.7.21+
- **Language**: Elixir 1.14+
- **Database**: PostgreSQL with Ecto ORM
- **Real-time Communication**: Phoenix LiveView & PubSub
- **UI**: Tailwind CSS & Heroicons
- **AI**: Ollama for local LLM inference
- **State Management**: Finitomata state machines
- **HTTP Client**: Finch (AI calls go through the [Ollama](https://hex.pm/packages/ollama) client, which is built on Req)
- **Server**: Bandit
- **Monitoring**: PromEx for Prometheus metrics
- **Code Quality**: Credo linter

## Prerequisites

- Elixir 1.14 or later
- Erlang/OTP 25+
- PostgreSQL 12+
- Node.js 16+ (for asset compilation)
- [Ollama](https://ollama.ai) running locally (for AI features)

## Getting Started

### Setup

1. **Install dependencies and setup the project:**

   ```bash
   mix setup
   ```

   This command will:
   - Install Elixir dependencies
   - Create and migrate the database
   - Install frontend dependencies
   - Build CSS and JavaScript assets

2. **Start the development server:**

   ```bash
   mix phx.server
   ```

   Or use IEx for interactive exploration:

   ```bash
   iex -S mix phx.server
   ```

3. **Visit the application:**

   Open your browser to [`http://localhost:4000`](http://localhost:4000)

### Configuration

Create a `.env.local` file in the project root for development:

```env
# Ollama AI Model API
NEURO_MODEL_API_URL=http://localhost:11434/api

# Turnstile CAPTCHA (optional for development)
TURNSTILE_SITE_KEY=your_site_key
TURNSTILE_SECRET_KEY=your_secret_key

# CORS origins allowed for /api (comma-separated, empty = no cross-origin access)
CORS_ORIGINS=http://localhost:3000, https://example.com
```

### Database

- **Create database**: `mix ecto.create`
- **Run migrations**: `mix ecto.migrate`
- **Rollback**: `mix ecto.rollback [--step 1]`
- **Reset**: `mix ecto.reset`

### Testing

Run the test suite:

```bash
# Run all tests
mix test

# Run with coverage report
mix coveralls

# Generate HTML coverage report
mix coveralls.html
```

Tests are automatically set up to:
- Create test database
- Run migrations
- Clean up after execution

## Key Components

### GenServers & Supervisors

- **UserRequestsSupervisor/UserRequestsServer**: Manages individual user requests and lifecycle
- **ScavengersSupervisor/ScavengersServer**: Coordinates scavenger hunt execution
- **StatsCounterSupervisor/StatsCounterServer**: Aggregates and tracks statistics

### LiveViews

- **Single**: Single-player scavenger hunt interface
- **Team**: Multi-player team scavenger hunt
- **Neuro**: AI-powered scavenger functionality
- **Statistics**: Real-time statistics dashboard

## Deployment

### Docker

The project includes a `docker-compose.yml` for local development with PostgreSQL:

```bash
docker-compose up -d
```

### Production Build

```bash
# Generate a release
mix release

# Or with systemd support
mix release --systemd
```

Start with systemd:

```bash
PHX_SERVER=true bin/neuro_scav start
```

### Environment Variables

Required for production:

```env
# Server
PHX_HOST=example.com
PHX_SERVER=true
PORT=4000
SECRET_KEY_BASE=<generated_key>

# Database
DATABASE_URL=ecto://user:password@host/neuro_scav
POOL_SIZE=10
ECTO_IPV6=false

# AI Model
NEURO_MODEL_API_URL=http://localhost:11434/api

# CAPTCHA
TURNSTILE_SITE_KEY=<your_key>
TURNSTILE_SECRET_KEY=<your_key>

# Clustering (optional)
DNS_CLUSTER_QUERY=<query>

# CORS origins allowed for /api (comma-separated)
CORS_ORIGINS=https://example.com, https://app.example.com
```

## Development Tasks

### Asset Management

- **Build assets**: `mix assets.build`
- **Deploy assets** (minified): `mix assets.deploy`
- **Watch assets**: `mix phx.server` (auto-rebuilds in dev)

### Code Quality

- **Run linter**: `mix credo`
- **Format code**: `mix format`
- **Generate secret**: `mix phx.gen.secret`

### Database

- **Create migration**: `mix ecto.gen.migration migration_name`
- **Seed database**: `mix run priv/repo/seeds.exs`

## Internationalization (i18n)

The application supports multiple languages (English, Russian, German, and Japanese). Translation files are located in `priv/gettext/`:

- Extract strings: `mix gettext.extract`
- Merge translations: `mix gettext.merge priv/gettext`

## API Reference

The application provides RESTful JSON API endpoints for programmatic access to scavenger hunt functionality.

### Base URL

```
http://localhost:4000/api
```

### Endpoints

#### Health Check

**GET** `/api/health`

Check if the API is running.

**Response** (200 OK):
```json
{
  "result": "Ok"
}
```

---

#### Generate Single Scavenger

**POST** `/api/generate_single`

Generate a single scavenger hunt item.

**Query Parameters:**
- `lang` (optional): Language preference (`en`, `ru`, `de`, or `ja`). Defaults to language from cookies or `ru`.

**Response** (200 OK):
```json
{
  "scavenger": {
    "name": "Red ball",
    "rarity": "common"
  }
}
```

**Rarity Levels:**
- `common`
- `uncommon`
- `rare`
- `epic`
- `legendary`
- `neuro` (AI-powered)
- `gnome` (Special variant)

---

#### Generate Team Scavengers

**POST** `/api/generate_team`

Generate a team-based scavenger hunt (multiple items).

**Query Parameters:**
- `lang` (optional): Language preference (`en`, `ru`, `de`, or `ja`). Defaults to language from cookies or `ru`.

**Response** (200 OK):
```json
{
  "team": [
    {
      "name": "Red ball",
      "rarity": "common"
    },
    {
      "name": "Blue pen",
      "rarity": "uncommon"
    },
    {
      "name": "Ancient artifact",
      "rarity": "epic"
    }
  ]
}
```

---

#### Get Statistics

**GET** `/api/stats`

Retrieve aggregated statistics for all completed scavenger hunts.

**Response** (200 OK):
```json
{
  "legendary": 42,
  "epic": 156,
  "rare": 328,
  "uncommon": 512,
  "common": 1024,
  "neuro": 89,
  "gnome": 23
}
```

The response contains counts of discovered scavengers grouped by rarity level.

---

### Usage Examples

#### cURL

```bash
# Health check
curl http://localhost:4000/api/health

# Generate single scavenger with English locale
curl -X POST "http://localhost:4000/api/generate_single?lang=en"

# Generate single scavenger with Russian locale
curl -X POST "http://localhost:4000/api/generate_single?lang=ru"

# Generate team scavengers
curl -X POST "http://localhost:4000/api/generate_team"

# Get statistics
curl http://localhost:4000/api/stats
```

---

## Monitoring

The application includes Prometheus metrics through PromEx. Access metrics at `/metrics` in production (when configured).

## Contributing

Contributions are welcome! Please ensure:

- All tests pass: `mix test`
- Code is formatted: `mix format`
- Linting passes: `mix credo`
- Coverage is maintained: `mix coveralls`

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or contributions, please visit the [GitHub repository](https://github.com/solar05/neuro_scav).
