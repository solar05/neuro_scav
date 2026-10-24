# NeuroScav

[![CI](https://github.com/solar05/neuro_scav/actions/workflows/build.yml/badge.svg)](https://github.com/solar05/neuro_scav/actions/workflows/build.yml)
[![codecov](https://codecov.io/github/solar05/neuro_scav/graph/badge.svg?token=BV9QGO1UOV)](https://codecov.io/github/solar05/neuro_scav)

A Phoenix LiveView app around Tarkov-style scavengers: generate them alone, in teams or with a local LLM, battle them against other players, take a squad on a text roguelike raid, and share the results as cards with preview images.

## Features

| Mode | Route | What it does |
|------|-------|--------------|
| **Single** | `/` | Generates a scavenger. Its rarity (common → legendary) follows from the name, deterministically; a 1 in 2000 chance gives the gnome instead, whose card beats every other |
| **Team** | `/team_scavengers` | A team of five scavengers; collected sets give bonuses in battle |
| **Neuro** | `/neuro_scavengers` | Scavengers made up by an LLM via [Ollama](https://ollama.ai), of the `neuro` rarity |
| **Battle** | `/battle` | Card battles between two players by invite link or an open room for a random opponent: a duel, team against team, or a draft from open cards; anyone else watches |
| **Raid** | `/raid` | A text roguelike: a squad crosses a random map of one of nine locations, meets events with stat checks, keys, payments and karma, bosses, weather and night, and leaves through an exit — or doesn't |
| **Wheel** | `/wheel` | A wheel of fortune over your own entries |
| **Glossary** | `/glossary` | The rarity rules and their chances |
| **Statistics** | `/statistics` | Live counters of generated scavengers by rarity, and how raids went at each location: raids finished, wipes, scavs that made it out |

- **Share links**: a scavenger, a team and a finished raid can be shared as a page with an Open Graph preview. The preview image is an SVG rendered to PNG on the server (Resvg, Bender fonts embedded); the card lies on a tactical map of the region with a scene of a location.
- **Real-time**: LiveView and PubSub; battles and statistics update for everyone connected.
- **Four languages**: English, Russian, German and Japanese.
- **JSON API** for generation and statistics (see [docs/API.md](docs/API.md)).

## Tech Stack

- **Framework**: [Phoenix](https://www.phoenixframework.org/) 1.8, LiveView 1.2
- **Language**: Elixir 1.14+
- **Database**: PostgreSQL with Ecto
- **Real-time Communication**: Phoenix LiveView & PubSub
- **UI**: Bootstrap styles (bundled by the Tailwind CLI), Heroicons and [Tabler Icons](https://tabler.io/icons) (vendored SVGs in `assets/vendor/tabler-icons`)
- **AI**: Ollama for local LLM inference
- **HTTP Client**: Finch (AI calls go through the [Ollama](https://hex.pm/packages/ollama) client, which is built on Req)
- **Share images**: [Resvg](https://hex.pm/packages/resvg) (SVG → PNG)
- **Server**: Bandit
- **Monitoring**: PromEx for Prometheus metrics
- **Code Quality**: Credo linter

## Prerequisites

- Elixir 1.14 or later (`mise.toml` pins the version used in development)
- Erlang/OTP 25+
- PostgreSQL 12+
- [Ollama](https://ollama.ai) running locally (only for the Neuro mode)
- Node.js — optional, only for the Playwright check script (`check_mobile.js`); assets are built by the standalone esbuild and Tailwind binaries

## Getting Started

### Setup

1. **Install dependencies and setup the project:**

   ```bash
   mix setup
   ```

   This command will:
   - Install Elixir dependencies
   - Create and migrate the database, run the seeds
   - Install the esbuild and Tailwind binaries
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

Settings are read from environment variables at runtime (`config/runtime.exs`). Nothing loads a `.env` file, so export them in your shell (or use direnv, mise `[env]` and the like). In development every one is optional:

```env
# Ollama AI Model API (this is the default)
NEURO_MODEL_API_URL=http://localhost:11434/api

# CORS origins allowed for /api (comma-separated, empty = no cross-origin access)
CORS_ORIGINS=http://localhost:3000, https://example.com
```

Turnstile CAPTCHA keys are required in production only (see [Environment Variables](#environment-variables)).

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

# Re-run only the failed ones
mix test --failed

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

A longer walk through the layers is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### Processes

- **UserRequestsSupervisor/UserRequestsServer**: Manages individual user requests and lifecycle
- **ScavengersSupervisor/ScavengersServer**: Generates scavengers and teams, works out rarities and team sets
- **StatsCounterSupervisor/StatsCounterServer**: Aggregates and tracks statistics
- **BattleRoom**: one process per battle room (invite link), registered in `NeuroScav.BattleRegistry` under `NeuroScav.BattleSupervisor`
- **RaidStore**: raids in progress kept in ETS, so a raid page that reconnects (a phone back from the background, a dropped network) picks its raid up again; stale raids are swept

### Raid engine (`lib/neuro_scav/raid*`)

Plain data and functions, no processes; the LiveView keeps the raid, `RaidStore` a copy.

- **`NeuroScav.Raid`**: the raid itself — events and their options, checks, movement across the map, what the squad sees and remembers
- **`Raid.Squad`**: members, their battle-card stats, wounds, the stash and its consumables
- **`Raid.Chart`**: the map's shape, the locations, random maps with their exits and bosses
- **`Raid.Catalog`**: every event, search, exit and location
- **`Raid.Report`**: a finished raid in short, encoded into a share link and strictly validated when decoded

### Share pages (`ShareController`)

| Page | Preview image |
|------|---------------|
| `/share/:token` | `/share/:token/image` |
| `/share/team/:token` | `/share/team/:token/image` |
| `/share/raid/:token` | `/share/raid/:token/image` |

The token carries the card's data, so nothing is stored. Images are served without content negotiation (crawlers send arbitrary `Accept` headers) and cached for a day.

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

- **Before committing**: `mix precommit` (format + `credo --strict`)
- **Run linter**: `mix credo`
- **Format code**: `mix format`
- **Generate secret**: `mix phx.gen.secret`

### Raid balance

`mix raid.sim` plays thousands of raids with random squads and prints how they end, per strategy (cautious, careful, greedy, random). A development tool only: Mix isn't part of a release. See `mix help raid.sim`.

```bash
mix raid.sim                                  # 5000 raids per strategy
mix raid.sim --runs 20000 --seed 42           # more raids, the same ones every time
mix raid.sim --strategy greedy --events       # one strategy, with a table per event
mix raid.sim --route pmc,veteran,labs         # a fixed route instead of a random map
```

### Rarity distribution

`mix rarity.sim` generates scavengers the way the site does (the gnome included) without counting them anywhere, and prints each rarity's count and share next to its exact chance, with the deviation in standard deviations: within ±2σ is chance, past ±3σ (marked `!`) generation and the odds disagree. `--csv` prints rows with the seed and runs in each, to append to one file and sum up later. See `mix help rarity.sim`.

```bash
mix rarity.sim                                # 100000 scavengers per locale
mix rarity.sim --runs 1000000                 # more scavengers, closer to the odds
mix rarity.sim --locale en --seed 42          # one locale, the same ones every time
mix rarity.sim --csv >> rarities.csv          # rows to collect over many runs
```

### Database

- **Create migration**: `mix ecto.gen.migration migration_name`
- **Seed database**: `mix run priv/repo/seeds.exs`

### LiveDashboard

In development Phoenix LiveDashboard is at [`/dev/dashboard`](http://localhost:4000/dev/dashboard).

## Internationalization (i18n)

The application supports multiple languages (English, Russian, German, and Japanese). Translation files are located in `priv/gettext/`:

- Extract strings: `mix gettext.extract`
- Merge translations: `mix gettext.merge priv/gettext`

## API Reference

The JSON API (health check, scavenger and team generation, statistics), with request and response examples and cURL usage, is described in [docs/API.md](docs/API.md).

## Monitoring

The application includes Prometheus metrics through PromEx. Access metrics at `/metrics` in production (when configured).

## Contributing

Contributions are welcome! Please ensure:

- All tests pass: `mix test`
- Formatting and linting pass: `mix precommit`
- Coverage is maintained: `mix coveralls`

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or contributions, please visit the [GitHub repository](https://github.com/solar05/neuro_scav).
