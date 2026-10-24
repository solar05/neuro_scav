# NeuroScav API Reference

The application provides RESTful JSON API endpoints for programmatic access to scavenger generation and statistics.

## Base URL

```
http://localhost:4000/api
```

Requests are rate limited to 200 per 60 seconds. Cross-origin access is allowed only for the origins in `CORS_ORIGINS`.

## Endpoints

### Health Check

**GET** `/api/health`

Check if the API is running.

**Response** (200 OK):
```json
{
  "result": "Ok"
}
```

---

### Generate Single Scavenger

**POST** `/api/generate_single`

Generate a single scavenger.

**Query Parameters:**
- `lang` (optional): Language preference (`en`, `ru`, `de`, or `ja`). Defaults to language from cookies or `ru`.

**Response** (200 OK):
```json
{
  "scavenger": {
    "name": "Alice Adams",
    "rarity": "rare"
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

### Generate Team Scavengers

**POST** `/api/generate_team`

Generate a team of five scavengers.

**Query Parameters:**
- `lang` (optional): Language preference (`en`, `ru`, `de`, or `ja`). Defaults to language from cookies or `ru`.

**Response** (200 OK):
```json
{
  "team": [
    {
      "name": "Alice Adams",
      "rarity": "rare"
    },
    {
      "name": "Lena Rose",
      "rarity": "uncommon"
    },
    {
      "name": "Mark Twain",
      "rarity": "common"
    }
  ]
}
```

---

### Get Statistics

**GET** `/api/stats`

Retrieve aggregated statistics of generated scavengers.

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

## Usage Examples

### cURL

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
