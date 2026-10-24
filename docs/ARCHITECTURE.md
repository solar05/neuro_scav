# NeuroScav Architecture Guide

## Overview

NeuroScav is a Phoenix 1.7 LiveView application. The code is split into two halves:

- `lib/neuro_scav/` — the domain: scavenger generation, card battles, raids, statistics
- `lib/neuro_scav_web/` — the web: LiveViews, controllers, plugs, components

Most state lives in processes (GenServers, ETS, a process per battle room) rather than in the database: PostgreSQL holds only the statistics counters. Shared results (a scavenger, a team, a finished raid) aren't stored at all — the share link carries them.

## System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│ Web Layer (lib/neuro_scav_web)                                       │
│   LiveViews: Single · Team · Neuro · Battle · Raid · Wheel           │
│              Glossary · Statistics                                   │
│   on every page: LegendaryToast · OnlineCounter (Presence)           │
│   ShareController (share pages, PNG previews) · /api controllers     │
│   Plugs: SetLocale · SetUserId · RateLimit                           │
└──────────────────────────────────────────────────────────────────────┘
                        ↓ calls          ↑ PubSub messages
┌──────────────────────────────────────────────────────────────────────┐
│ Processes (lib/neuro_scav/servers)                                   │
│   ScavengersServer · StatsCounterServer · UserRequestsServer         │
│   BattleRoom (one per room) · RaidStore (ETS)                        │
└──────────────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────────────┐
│ Domain (lib/neuro_scav)                                              │
│   Raid engine: Raid · Squad · Chart · Catalog · Report               │
│   Scavengers.Names · Client (Ollama) · Scavengers context            │
│   PubSub + PubSub.Topics                                             │
└──────────────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────────────┐
│ PostgreSQL: one statistics row  ·  Ollama: the scav:latest model     │
└──────────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Web Layer (`lib/neuro_scav_web/`)

#### LiveViews (`live/neuro_scavenger_live/`)

| Module | Route | Works with |
|--------|-------|------------|
| **Single** | `/` | `ScavengersServer.generate_single/2`; the result comes back by PubSub |
| **Team** | `/team_scavengers` | `ScavengersServer.generate_team/2,3` (up to five), team sets |
| **Neuro** | `/neuro_scavengers` | `UserRequestsServer.schedule_request/2` — a queue of requests to Ollama |
| **Battle** | `/battle`, `/battle/:id` | a `BattleRoom` per invite link, its `battle:<id>` topic, Presence |
| **Raid** | `/raid` | the raid engine (`NeuroScav.Raid`), `RaidStore`, `Raid.Report` for the share link |
| **Wheel** | `/wheel` | nothing outside the page |
| **Glossary** | `/glossary` | the rarity rules, `ScavengersServer.odds/2` |
| **Statistics** | `/statistics` | the `statistics:lobby` topic |

Mounted into every LiveView by `NeuroScavWeb.live_view/0`:

- **`LegendaryToast`** (`live/legendary_toast.ex`) — a toast on every page when someone else rolls a legendary (`finds:lobby`)
- **`OnlineCounter`** (`live/online_counter.ex`) — the online badge: every connected page tracked in `NeuroScavWeb.Presence` under its user id, so several tabs count once

`NeuroScavWeb.GnomeCapture` (`live/gnome_capture.ex`) is `use`d by the pages that show the gnome: a click on it counts in the `:gnome` counter.

#### Controllers (`controllers/`)

- **`ShareController`** — share pages for a scavenger, a team and a finished raid, and their Open Graph images. The token in the link carries the data and is strictly validated when decoded. The image is an SVG (the card on the region's tactical map, a location scene on its strip) rendered to PNG by Resvg, with the Bender fonts embedded; the art in `priv/static/images/share/` and the fonts are read at compile time. Images get an ETag and are cached for a day.
- **`Api.HealthController`, `Api.ScavengersController`** — the JSON API, see [API.md](API.md).

#### Components (`components/`)

- `core_components.ex` — form inputs, flash, icons (Heroicons, and the Tabler icons from `assets/vendor/tabler-icons` as an SVG sprite)
- `raid_components.ex` — the raid map, stash, legend and the naming helpers shared with the share pages
- `layouts.ex`, `layouts/` — the `root` and `app` layouts, and `share` with the Open Graph meta tags

#### Plugs (`plugs/`)

- **`SetLocale`** — the language from the `lang` param or cookie (`en`, `ru`, `de`, `ja`; `ru` by default), kept in the cookie and session
- **`SetUserId`** — an anonymous user id in the session; PubSub topics, battles and raids are keyed by it
- **`RateLimit`** — Hammer, 200 requests per minute by IP or session user (the `/api` pipeline)

### 2. PubSub (`lib/neuro_scav/pub_sub.ex`, `pub_sub/topics.ex`)

**Topics:**

| Topic | Carries |
|-------|---------|
| `user:<user_id>:<page>` | a user's generation results for a page: `{:single_generated, scav}`, `{:team_generated, team}`, `{:neuro_generated, scav}`, `:neuro_generation_error` |
| `statistics:lobby` | the counters after every update |
| `finds:lobby` | legendary finds, for the toast |
| `battle:<id>` | `{:battle_updated, state}` on every change of a room, `:battle_closed` |
| `online` | Presence of the connected pages |

**Functions:** `subscribe/2`, `broadcast/2` (user topics), `subscribe_statistics/0`, `broadcast_statistics/1`, `subscribe_finds/0`, `broadcast_find/2`, `subscribe_battle/1`, `broadcast_battle/2`.

### 3. Processes (`lib/neuro_scav/servers/`)

#### ScavengersServer

Generates scavengers from the name lists of `Scavengers.Names` (first, last and legendary names per language) and works out their rarity.

**Rarity algorithm** (deterministic, the same name always gets the same rarity):

```
1. Legendary - the name is in the language's legendary list
2. Epic      - first and last names rhyme: the same ending from the last vowel ("Гена Лена")
3. Rare      - first and last names start with the same character ("Alice Abrams")
4. Uncommon  - first and last names are as long ("Tom Ward")
5. Common    - none of the above
```

The one random exception: any generated scavenger is the gnome with a chance of 1 in `gnome_odds/0` (2000); its card beats every other.

**Key functions:**
- `generate_single/2`, `generate_team/2,3` — asynchronous: counted in statistics, legendaries announced on `finds:lobby`, the result broadcast to the user
- `generate_single/1`, `generate_team/1` — synchronous (the API)
- `generate_card/2` — a battle card, synchronously, counted like the others
- `generate_uncounted/1` — not counted nor announced (battle bots, a raid's random squad)
- `names/2`, `generate_scavenger/2` — the same generation without the server, not counted nor announced (`mix rarity.sim`)
- `check_name/1`, `odds/2`, `team_sets/1`, `max_team_members/0` (5)

#### StatsCounterServer

Seven counters: `:common`, `:uncommon`, `:rare`, `:epic`, `:legendary`, `:neuro`, `:gnome`. It starts from the `statistics` row; every update is written back to it (`Scavengers.update_statistics/2`) and broadcast to `statistics:lobby`.

**Key functions:** `update_counter/1`, `update_multiple_counters/1`, `gnome_captured/0`, `available_counters/0`.

#### UserRequestsServer

The queue of Neuro requests to Ollama, one at a time on a timer:

- `schedule_request/2` → `:scheduled`, `:already_scheduled` (one per user) or `:requests_limit_reached` (10 in the queue)
- a request older than 5 minutes is dropped unprocessed
- the result (`{:neuro_generated, scav}`, counted as `:neuro`) or the error goes to the user's topic; the requests are counted in PromEx

#### BattleRoom

One card battle between two players, a process per invite link registered in `NeuroScav.BattleRegistry` under the `NeuroScav.BattleSupervisor` DynamicSupervisor. The creator is the first player, the first other visitor the second, everyone after that watches.

- **Modes:** `:duel` (a card each), `:team` (a team each), `:draft` (picks in snake order from open cards)
- **Open rooms** wait for a random opponent; **bot rooms** (`create_with_bot/3`) seat a bot that thinks 2–5 seconds and chats in phrases
- **Anomalies:** every battle gets a random condition that bends the rules (Tarkov RNG, naked run, night raid, wipe, uninsured)
- **Turn timer:** when it runs out, the bot's logic moves for whoever is late
- **Presence and chat:** pages are monitored (an absent player is `away`); the last 50 chat messages stay in the room
- Every change goes to `battle:<id>`; LiveViews render only the viewer's own cards until the reveal, so nothing leaks to the browser
- A room stops after an hour without activity

#### RaidStore

Raids in progress in ETS, keyed by `{user_id, run}` (the run is in the raid page's address, so each tab has its own), so a page that reconnects — a phone back from the background, a dropped network — picks its raid up again. A raid lives an hour after its last step, a sweep every 10 minutes drops the stale ones, and the store holds `max_runs/0` raids at most. The server only owns the table: reads and writes go straight to it.

### 4. Domain (`lib/neuro_scav/`)

#### Raid engine (`raid.ex`, `raid/`)

Plain data and functions, no processes: the Raid LiveView keeps the raid in its assigns and copies it to `RaidStore` after every step.

- **`NeuroScav.Raid`** — the raid: the squad crosses a map of layers of nodes with an event at each; an event's options need a stat check, are safe, need an item (a key) or a condition (a payment, the scavs' trust — karma). A check is made by the member best at the stat, with their loot's bonuses and karma. The squad sees the next nodes, the rest by their kind of event — or not at all at night and in the fog — and remembers what it has seen.
- **`Raid.Squad`** — members and their battle-card stats, wounds, the stash and its consumables. The squad is up to five: names the player types in, or random ones from `generate_uncounted/1`.
- **`Raid.Chart`** — the map's shape (4 wide, 10–13 layers, 3–4 paths across, a boss on 80% of maps), the locations, random maps
- **`Raid.Catalog`** — every event, search and exit, and the nine locations with their exits, bosses and events
- **`Raid.Report`** — a finished raid in short (location, exit, members, loot, language), encoded as URL-safe base64 JSON into the share link; decoding checks every value against the known ones

`mix raid.sim` (`lib/mix/tasks/raid.sim.ex`) plays thousands of raids with random squads to tune the balance. Its counterpart for generation, `mix rarity.sim` (`lib/mix/tasks/rarity.sim.ex`), generates scavengers by the hundred thousand and checks their rarities against the exact odds.

#### Client (`client.ex`)

The Ollama client: the `scav:latest` model, temperature 0.8, a 60-second timeout, languages `en`, `ru`, `de` and `ja` (romaji). `generate_scav/1` returns `{:ok, "First Last"}`. The API URL is `NEURO_MODEL_API_URL`.

#### Scavengers context (`scavengers.ex`, `scavengers/`)

- `NeuroScav.Scavengers` — get, create and update the statistics
- `Scavengers.Statistics` — the schema: seven integer counters in one row
- `Scavengers.Names` — the name lists per language

#### Application & supervision (`application.ex`)

```
NeuroScav.Supervisor (one_for_one)
├── NeuroScavWeb.Telemetry
├── NeuroScav.PromEx
├── NeuroScav.Repo
├── DNSCluster
├── Phoenix.PubSub (NeuroScav.PubSub)
├── NeuroScavWeb.Presence
├── Registry (NeuroScav.BattleRegistry)
├── DynamicSupervisor (NeuroScav.BattleSupervisor)
│   └── NeuroScav.BattleRoom (one per room)
├── NeuroScav.RaidStore
├── NeuroScavWeb.Endpoint
├── :systemd.ready()
├── NeuroScav.UserRequestsSupervisor → UserRequestsServer   ┐
├── NeuroScav.ScavengersSupervisor → ScavengersServer        │ not in the test env:
└── NeuroScav.StatsCounterSupervisor → StatsCounterServer    ┘ tests start them themselves
```

### 5. Data Layer (`lib/neuro_scav/repo.ex`)

PostgreSQL through Ecto, with a single table: `statistics` (`priv/repo/migrations`). Battles, raids in progress and the Neuro queue are in memory and don't survive a restart.

## Data Flow Examples

### Single Scavenger Generation

```
User clicks "Generate" (Single LiveView)
        ↓
ScavengersServer.generate_single(user_id, locale)   (cast)
        ↓
ScavengersServer:
  - picks a first and last name of the language
  - works out the rarity (or rolls the gnome, 1 in 2000)
  - StatsCounterServer.update_counter(rarity)
  - a legendary: PubSub.broadcast_find → finds:lobby → toasts on other users' pages
        ↓
user:<id>:single_scavenger ← {:single_generated, scavenger} → Single LiveView renders the card
        ↓
StatsCounterServer writes the row, broadcasts statistics:lobby → Statistics LiveView re-renders
```

### Team Scavenger Generation

```
User asks for a team (Team LiveView)
        ↓
ScavengersServer.generate_team(user_id, locale, count)   (cast, up to 5)
        ↓
ScavengersServer generates every member, then
StatsCounterServer.update_multiple_counters(rarities)
        ↓
user:<id>:team_scavengers ← {:team_generated, team} → Team LiveView renders the team and its sets
```

### AI (Neuro) Scavenger Generation

```
User asks for a neuro scavenger (Neuro LiveView)
        ↓
UserRequestsServer.schedule_request(user_id, locale) → :scheduled
        ↓
on the next tick the server takes the oldest request (dropped if older than 5 minutes)
        ↓
Client.generate_scav(locale) → Ollama, model scav:latest
        ↓
{:ok, "First Last"} → StatsCounterServer.update_counter(:neuro)
        ↓
user:<id>:neuro_scavenger ← {:neuro_generated, scavenger}  (or :neuro_generation_error)
```

### Card Battle

```
Player A opens /battle and creates a room
        ↓
BattleRoom starts under BattleSupervisor, registered by its id
        ↓
Player B opens the invite link /battle/:id → the second player (later visitors watch)
        ↓
every draw, redraw, pick and chat message → BattleRoom → battle:<id> ← {:battle_updated, state}
        ↓
both ready → cards meet slot by slot, stat by stat, under the battle's anomaly → the result
```

### Raid and Its Share Link

```
User recruits a squad (Raid LiveView, /raid?run=…)
        ↓
NeuroScav.Raid: random map → event → option → check → next node … → exit
  (the raid copied to RaidStore after every step; a reconnect picks it up)
        ↓
Raid.Report.new(raid, locale) |> Raid.Report.encode() → /share/raid/<token>
        ↓
ShareController.raid decodes and validates the token → the page, og:image → /share/raid/<token>/image
        ↓
SVG (card on the region's map, the location's scene) → Resvg → PNG
```

## Key Design Patterns

### 1. State in Processes

Stateful parts are processes: GenServers for generation, counters and the Neuro queue, a process per battle room under a DynamicSupervisor, ETS for raids in progress. The database only keeps the counters.

### 2. Event Broadcasting via PubSub

Producers don't know their consumers: a generation, a counter update or a battle move is broadcast, and every subscribed LiveView updates itself.

### 3. Pure Domain Logic

The rarity rules and the raid engine are plain functions over plain data: easy to test, and the raid can be simulated by the thousand (`mix raid.sim`).

### 4. Deterministic Rarity

The rarity follows from the name alone, so results are reproducible and cheap; the gnome is the only random exception. Share cards pick their location by the name's hash in the same spirit.

### 5. Stateless Sharing

A share link carries its card, so nothing is stored; the token is a trust boundary and is decoded strictly.

### 6. Compile-Time Assets

The name lists, the share art and fonts and the Tabler icons are read at compile time into module attributes.

## Testing Strategy

### Test Organization

- **Domain and processes** (`test/neuro_scav/`): the raid engine (`raid_test`, `raid_mechanics_test`, `raid_report_test`), `raid_store_test`, `battle_room_test`, `scavengers_server_test`, `scavengers/names_test`, `stats_counter_server_test`, `user_request_server_test`
- **LiveViews** (`test/neuro_scav_web/live/`): a test file per page, plus the toast and the online counter
- **Controllers and plugs** (`test/neuro_scav_web/controllers/`, `plugs/`): the share pages and images, the API, locale and user id
- **Mix tasks** (`test/mix/tasks/`): `raid_sim_test`, `rarity_sim_test`

The generation and counter servers aren't started in the test environment; tests start what they need with `start_supervised!/1`.

### Coverage

- Target: >80% code coverage
- Tool: ExCoveralls (`mix coveralls`, `mix coveralls.html`)
- Before committing: `mix precommit` (format + `credo --strict`)

## Configuration & Environment

Settings come from environment variables read at runtime in `config/runtime.exs`; nothing loads a `.env` file. In development they are all optional (see [Configuration](../README.md#configuration)), in production see [Environment Variables](../README.md#environment-variables).

- `config/config.exs` — general settings (locales, esbuild, Tailwind)
- `config/dev.exs`, `config/test.exs`, `config/prod.exs` — per-environment overrides
- `config/runtime.exs` — runtime-evaluated config (Ollama URL, CORS origins, and in production the database, Turnstile, the host)

## Monitoring & Metrics

### Prometheus Metrics

`PromEx.Plug` in the endpoint serves `/metrics`. Besides PromEx's standard plugins, `PromEx.Plugins.NeuroScav` (`lib/neuro_scav/plugins/neuro_scav.ex`) counts the Neuro requests processed and measures their duration.

### LiveDashboard

In development Phoenix LiveDashboard is at `/dev/dashboard`.

## Scaling Notes

`DNSCluster` and Phoenix PubSub already work across clustered nodes, but much of the state is per node: the generation and counter servers are registered locally, battle rooms are in a local `Registry`, raids in progress in a local ETS table, and the Neuro queue in one process. Several nodes would need a distributed registry for rooms and servers and a shared raid store.

---

**Last Updated:** October 2026
