# NeuroScav Architecture Guide

## Overview

NeuroScav is a Phoenix-based web application for neural scavenger hunts. The system is built on a modular architecture with clear separation of concerns between the AI/business logic layer (`lib/neuro_scav/`) and the web/presentation layer (`lib/neuro_scav_web/`).

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Web Layer (LiveView)                         │
│  ┌──────────────────┬──────────────────┬──────────────────┐    │
│  │  Single Mode     │   Team Mode      │  Statistics      │    │
│  │  Live View       │   Live View      │  Live View       │    │
│  └──────────────────┴──────────────────┴──────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│               PubSub Broadcasting Layer                          │
│  - Real-time event distribution                                 │
│  - Statistics updates                                           │
│  - Team synchronization                                        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              GenServer Coordination Layer                        │
│  ┌────────────────────┬────────────────────┬─────────────────┐ │
│  │ ScavengersServer   │ StatsCounterServer │ UserRequests*   │ │
│  │ - Scavenger gen    │ - Counter mgmt     │ - User sessions │ │
│  │ - Rarity logic     │ - Statistics       │ - Request track │ │
│  └────────────────────┴────────────────────┴─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│            Business Logic & Data Access Layer                   │
│  ┌──────────────┬──────────────┬──────────────┬──────────────┐  │
│  │  Client      │  Scavengers  │  Contexts    │  Database    │  │
│  │  - AI calls  │  - Schemas   │  - Queries   │  - Ecto      │  │
│  │  - Ollama    │  - Models    │  - Updates   │  - Postgres  │  │
│  └──────────────┴──────────────┴──────────────┴──────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              External Services                                   │
│  ┌──────────────┬──────────────┐                                │
│  │  Ollama AI   │  PostgreSQL  │                                │
│  │  (LLM)       │  (Database)  │                                │
│  └──────────────┴──────────────┘                                │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Web Layer (`lib/neuro_scav_web/`)

**Purpose:** Handles HTTP requests, WebSocket connections, and user interactions.

#### LiveView Modules
- **Single** - Single-player scavenger hunt interface
  - User initiates a hunt
  - Displays generated scavengers
  - Shows individual statistics
  
- **Team** - Multi-player team scavenger hunt
  - Manages team creation/joining
  - Real-time team member updates
  - Collective statistics tracking

- **Neuro** - AI-powered scavenger functionality
  - Handles neural generation requests
  - Displays AI-generated scavengers

- **Statistics** - Real-time statistics dashboard
  - Subscribes to PubSub statistics updates
  - Displays aggregated counters
  - Shows top performers

#### Components & Templates
- Reusable UI components in `lib/neuro_scav_web/components/`
- Page layouts in `lib/neuro_scav_web/layouts/`
- HTTP middleware (plugs) in `lib/neuro_scav_web/plugs/`

### 2. PubSub Broadcasting Layer (`lib/neuro_scav/pub_sub.ex`)

**Purpose:** Real-time event distribution across processes and connections.

**Key Topics:**
- `statistics:{hunt_id}` - Statistics updates for a specific hunt
- `user:{user_id}` - User-specific events
- `team:{team_id}` - Team-specific events

**Functions:**
- `broadcast/2` - Send events to user
- `broadcast_statistics/1` - Push updated statistics
- Subscribe patterns for LiveView modules

### 3. GenServer Coordination Layer

#### ScavengersServer (`lib/neuro_scav/servers/scavengers_server.ex`)

**Purpose:** Central scavenger generation and rarity calculation engine.

**Key Responsibilities:**
- Generate individual scavengers
- Generate team scavengers (5 max members)
- Calculate rarity (legendary, epic, rare, uncommon, common)

**Rarity Algorithm:**
```elixir
1. Legendary   - Name matches legendary_names list
2. Epic        - First & last names share same last 3 characters
3. Rare        - First & last names start with same character
4. Uncommon    - First & last names have equal length
5. Common      - Default
```

**Key Functions:**
- `generate_single/1` - Generate one scavenger
- `generate_team/1` - Generate team of 5
- `generate_single/2` - Generate and notify user asynchronously
- `generate_team/2` - Generate team and notify user asynchronously

#### StatsCounterServer (`lib/neuro_scav/servers/stats_counter_server.ex`)

**Purpose:** Aggregates and manages statistics counters.

**Available Counters:**
- `:common` - Common rarity count
- `:uncommon` - Uncommon rarity count
- `:rare` - Rare rarity count
- `:epic` - Epic rarity count
- `:legendary` - Legendary rarity count
- `:neuro` - AI-generated count
- `:gnome` - Special gnome captures

**Key Functions:**
- `update_counter/1` - Increment single counter
- `update_multiple_counters/1` - Increment multiple counters
- `gnome_captured/0` - Special gnome capture event

#### UserRequestsServer (`lib/neuro_scav/servers/user_requests_server.ex`)

**Purpose:** Manages individual user request lifecycle and state.

**Responsibilities:**
- Track active user requests
- Handle request completion/timeout
- Maintain user session state
- Clean up expired requests

**Key Functions:**
- `create_request/1` - Start tracking a user request
- `complete_request/1` - Mark request as complete
- `get_request/1` - Retrieve request info

### 4. Business Logic Layer (`lib/neuro_scav/`)

#### Client (`lib/neuro_scav/client.ex`)

**Purpose:** AI service integration layer.

**Key Responsibilities:**
- Initialize Ollama client connection
- Generate AI-powered scavengers
- Parse AI responses
- Handle language-specific prompts

**Key Functions:**
- `init/0` - Initialize Ollama connection
- `generate_scav/1` - Generate AI scavenger (language optional)
- `present_prompt/1` - Format prompt for Ollama
- `present_language/1` - Validate and normalize language

**Supported Languages:**
- `:en` - English
- `:ru` - Russian

#### Scavengers Context (`lib/neuro_scav/scavengers.ex`)

**Purpose:** Database operations and schema management.

**Responsibilities:**
- CRUD operations for scavenger records
- Schema definitions and validations
- Database queries

**Key Schemas:**
- Scavenger - Individual scavenger record
- Statistics - Hunt statistics tracking

#### Application & Supervision (`lib/neuro_scav/application.ex`)

**Purpose:** Application lifecycle and process supervision.

**Supervised Processes:**
1. Ecto Repository
2. PubSub coordinator
3. ScavengersServer - Scavenger generation
4. StatsCounterServer - Statistics aggregation
5. UserRequestsSupervisor - User request management
6. PromEx Metrics - Prometheus integration

### 5. Data Layer (`lib/neuro_scav/repo.ex`)

**Purpose:** Ecto repository for database access.

**Database:** PostgreSQL

**Key Migrations:**
- Scavengers table
- Statistics tables
- Audit trails

## Data Flow Examples

### Single Scavenger Generation Flow

```
User clicks "Generate" in Single LiveView
        ↓
Phoenix receives action
        ↓
LiveView calls ScavengersServer.generate_single/2
        ↓
ScavengersServer processes:
  - Picks random first & last names
  - Calculates rarity
  - Returns scavenger map
        ↓
StatsCounterServer.update_counter(:rarity)
        ↓
PubSub broadcasts statistics update
        ↓
StatisticsLiveView receives update
        ↓
LiveView re-renders statistics
```

### Team Scavenger Generation Flow

```
User initiates team hunt
        ↓
LiveView calls ScavengersServer.generate_team/2
        ↓
ScavengersServer generates 5 scavengers:
  - For each member: generate → calculate rarity
  - Collect rarity list: [:rare, :common, :epic, ...]
        ↓
ScavengersServer calls:
StatsCounterServer.update_multiple_counters(rarities)
        ↓
StatsCounterServer aggregates all rarity updates
        ↓
PubSub broadcasts updated statistics
        ↓
All team members receive real-time update
```

### AI Scavenger Generation Flow

```
User requests AI scavenger
        ↓
Client.generate_scav/1 is called
        ↓
Client initializes Ollama connection
        ↓
Sends prompt: "gen#{language}" (e.g., "genen")
        ↓
Ollama processes with model "scav:latest"
        ↓
Client parses JSON response:
  {"firstName": "...", "lastName": "..."}
        ↓
Returns: {:ok, "FirstName LastName"}
        ↓
LiveView displays AI result
```

## Key Design Patterns

### 1. GenServer-Based Concurrency

All stateful operations (scavenger generation, statistics tracking) use GenServers for:
- Safe concurrent access
- State consistency
- Message-based communication

### 2. Event Broadcasting via PubSub

- Decouples producers from consumers
- Enables real-time updates across LiveViews
- Supports multiple subscribers

### 3. Layered Architecture

```
Presentation (LiveView) → Pure separation
Web Layer (Router, Plugs) → Pure separation
Business Logic (Servers, Contexts) → Core logic
Data Layer (Repo, Schemas) → Storage abstraction
```

### 4. Rarity Calculation

Deterministic algorithm based on name properties (no randomness):
- Enables reproducible results
- Fast computation
- Elegant pattern matching

## Process Supervision Tree

```
NeuroScav.Application
├── Ecto.Repo (database connection pool)
├── Phoenix.PubSub (event broadcasting)
├── NeuroScav.ScavengersServer (scavenger generation)
├── NeuroScav.StatsCounterServer (statistics)
├── NeuroScav.UserRequestsSupervisor
│   └── NeuroScav.UserRequestsServer (multiple instances)
├── PromEx (Prometheus metrics)
└── Phoenix.Endpoint (web server)
```

## Testing Strategy

### Test Organization

- **Unit Tests**: Core logic (rarity calculation, client responses)
- **Integration Tests**: GenServer interactions, PubSub messaging
- **Feature Tests**: LiveView user flows

### Key Test Files

- `test/neuro_scav/servers/scavengers_server_test.exs`
- `test/neuro_scav/servers/stats_counter_server_test.exs`
- `test/neuro_scav_web/live/` - LiveView tests

### Coverage

- Target: >80% code coverage
- Tool: ExCoveralls

## Configuration & Environment

### Development Environment

```elixir
# .env.local
NEURO_MODEL_API_URL=http://localhost:11434/api
TURNSTILE_SITE_KEY=dev_key
TURNSTILE_SECRET_KEY=dev_secret
```

### Runtime Configuration

- `config/config.exs` - General settings
- `config/dev.exs` - Development overrides
- `config/prod.exs` - Production settings
- `config/runtime.exs` - Runtime-evaluated config

## Monitoring & Metrics

### Prometheus Metrics

- Request latency
- Scavenger generation time
- Statistics update frequency
- Database query performance

### Access

- Development: `/metrics` endpoint
- Production: Configure Prometheus scraping

## Future Architecture Considerations

### Scaling

1. **Database**: Connection pooling (currently 10)
2. **Genservers**: Consider distributed Elixir nodes
3. **PubSub**: Switch to PubSub over distributed system
4. **AI Service**: Load balance multiple Ollama instances

### Enhancements

1. **Caching**: Add redis for frequently accessed data
2. **Queue**: Implement job queue for async operations
3. **Events**: Event sourcing for audit trail
4. **Search**: Add Elasticsearch for analytics queries

---

**Last Updated:** May 2026  
**Version:** 1.0  
**Maintainer:** NeuroScav Team
