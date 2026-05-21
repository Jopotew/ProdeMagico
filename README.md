# Prode — World Cup Prediction App

A football prediction platform for the FIFA World Cup built with Elixir, Phoenix, and PostgreSQL.

## Stack

- **Elixir 1.17+ / OTP 27**, Phoenix 1.8, Phoenix LiveView 1.1
- **PostgreSQL 16**, Ecto SQL 3.14
- **Oban 2.22** (background jobs, cron)
- **Req 0.5** (HTTP client)
- **Ueberauth + Google OAuth** (primary auth)
- **API-Football v3** (sports data provider)
- **web_push_elixir** (W3C push notifications)
- **ExMachina + Mox + Bypass** (testing)

## Quick start

```powershell
# 1. Install Elixir + Erlang via Scoop (Windows)
scoop install elixir erlang

# 2. Install dependencies
mix deps.get

# 3. Copy the env template and fill in your credentials
copy .env.example .env

# 4. Load env vars (PowerShell - run once per terminal session)
Get-Content .env | ForEach-Object {
  if ($_ -match '^([^#][^=]*)=(.*)$') {
    [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
  }
}

# 5. Create DB, run migrations, seed World Cup tournament data
mix setup

# 6. Start the server
mix phx.server
# => http://localhost:4000
```

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | prod only | `ecto://user:pass@host/db` |
| `SECRET_KEY_BASE` | prod only | `mix phx.gen.secret` |
| `GOOGLE_CLIENT_ID` | yes | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | yes | Google OAuth client secret |
| `API_FOOTBALL_KEY` | yes | API-Football v3 key |
| `VAPID_PUBLIC_KEY` | notifications | Web push VAPID public key |
| `VAPID_PRIVATE_KEY` | notifications | Web push VAPID private key |
| `VAPID_SUBJECT` | notifications | `mailto:contact@yourdomain.com` |
| `WHATSAPP_PHONE_NUMBER_ID` | WhatsApp | Meta Cloud API phone number ID |
| `WHATSAPP_ACCESS_TOKEN` | WhatsApp | Meta Cloud API access token |

Generate VAPID keys: `npx web-push generate-vapid-keys`.

## Common commands

```bash
mix setup                           # install deps, create DB, migrate, seed
mix phx.server                      # dev server at :4000
iex -S mix phx.server               # dev server with IEx attached

mix test                            # unit + integration tests (~2s)
mix test --only integration         # integration tests only
mix test test/path/file_test.exs:42 # single test

mix format                          # format code
mix credo --strict                  # linting
mix dialyzer                        # type checking
mix coveralls.html                  # coverage report

mix ecto.migrate
mix ecto.rollback
mix ecto.gen.migration <name>
```

## Architecture overview

```
lib/prode/
  accounts/          # Users, Google OAuth + email/password auth
  tournaments/       # Tournament, Stage, Team schemas
  matches/           # Match schema, MatchPoller GenServer
  predictions/       # Prediction, BonusPrediction, MatchLocker
  scoring/           # Pure scoring engine (no DB access)
  groups/            # Groups, Memberships, invite codes, leaderboard
  notifications/     # PushSubscription, dispatch helpers
  external/          # API-Football client, WhatsApp client, RateLimiter
  workers/           # All Oban workers

lib/prode_web/
  controllers/api/   # JSON API (v1) endpoints
  plugs/             # ApiAuth Bearer token plug
  live/              # LiveViews (profile, settings)
```

### Scoring rules

| Outcome | Group stage | Knockout (2x) |
|---|---|---|
| Exact score | 5 pts | 10 pts |
| Correct winner / draw | 3 pts | 6 pts |
| Wrong outcome | 0 pts | 0 pts |

Bonus: +10 pts for correct top scorer, +10 pts per correct group winner (8 groups, max 80 bonus pts).

### Prediction locking

Predictions lock **15 minutes before kickoff**. Enforced at three layers:
1. UI form disabled
2. Changeset validation rejects late submissions
3. `SELECT … FOR UPDATE` inside a DB transaction (race-safe)

### Background jobs (Oban)

| Worker | Trigger | Purpose |
|---|---|---|
| `FixtureSyncWorker` | Daily 04:00 UTC | Sync fixtures from API-Football |
| `PointsCalculator` | Match finishes | Award points for all predictions |
| `BonusPointsCalculator` | Tournament ends | Award bonus predictions |
| `TopScorerSyncWorker` | Daily 05:00 UTC | Cache top scorer standings |
| `NotificationSweep` | Every 15 min | Enqueue match-start notifications |
| `NotificationDispatcher` | Per user/event | Send push + WhatsApp |

## JSON API

Base URL: `/api/v1` — all responses are `application/json`.

**Public** (no auth required):
- `GET /tournaments` — list active tournaments
- `GET /tournaments/:id` — tournament detail with stages
- `GET /matches?tournament_id=:id` — matches for a tournament
- `GET /matches/:id` — single match

**Authenticated** (pass session token as `Authorization: Bearer <token>`):
- `POST /matches/:id/predict` — submit or update a prediction
- `GET /groups` — your groups
- `POST /groups` — create a group
- `GET /groups/:id` — group detail
- `POST /groups/join` — join by invite code `{"invite_code": "ABC123"}`
- `GET /groups/:id/leaderboard` — paginated leaderboard (`?limit=50&offset=0`)
- `GET /users/me` — current user profile
- `GET /users/me/predictions` — your predictions with points
- `POST /users/me/push-subscription` — register a push subscription

## Testing

```bash
mix test                    # unit tests (fast, no DB for scoring engine)
mix test --only integration # DB-backed integration tests
```

Key test files:
- [engine_test.exs](test/prode/scoring/engine_test.exs) — exhaustive scoring coverage
- [match_locker_test.exs](test/prode/predictions/match_locker_test.exs) — GenServer locking
- [prediction_flow_test.exs](test/prode/integration/prediction_flow_test.exs) — predict → score → leaderboard
- [groups_test.exs](test/prode/integration/groups_test.exs) — group creation, joining, ranking
