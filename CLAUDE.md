# Prode — World Cup Prediction App

Football prediction platform (similar to Prode Master) for the FIFA World Cup. Solo developer project. Backend-first; v1 target is 2 weeks.

**Full development plan:** `docs/PLAN.md` — read it before making architectural decisions or starting a new phase.

---

## Stack

- Elixir 1.17+ / OTP 27, Phoenix 1.7, Phoenix LiveView 1.0
- PostgreSQL 16, Ecto SQL 3.11
- Oban 2.18 (background jobs, cron)
- Req 0.5 (HTTP client)
- Ueberauth + Ueberauth.Strategy.Google (OAuth)
- web_push_elixir (web push notifications)
- API-Football v3 (`https://v3.football.api-sports.io`) as sports data provider
- Mox + Bypass + ExMachina for testing

---

## Commands

```bash
mix setup              # install deps, create DB, migrate, seed
mix phx.server         # start dev server (port 4000)
iex -S mix phx.server  # start with IEx attached

mix test               # run all tests
mix test --only integration
mix test test/path/to/file_test.exs:42  # single test

mix format             # format code
mix credo --strict     # linting
mix dialyzer           # type checking
mix coveralls.html     # coverage report

mix ecto.migrate
mix ecto.rollback
mix ecto.gen.migration <name>
```

---

## Locked decisions — do not change without explicit user approval

These rules are the product. Drifting on any of them silently is a serious bug.

### Scoring
- **Group stage:** 5 pts exact score, 3 pts correct outcome (right winner/draw, wrong score), 0 pts wrong outcome
- **Knockout stages:** 2× multiplier (10 / 6 / 0)
- **Bonus — top scorer:** +10 pts if correct (tournament-level)
- **Bonus — group winners:** +10 pts per correct group (8 groups, max 80 pts on this category alone)
- **Bonus predictions lock** at tournament kickoff, not per-match
- Scoring lives in `Prode.Scoring.Engine` — pure functions, no DB access, exhaustive unit tests

### Prediction locking
- **Predictions lock 15 minutes before kickoff** (`prediction_lock_at = kickoff_at - 15 min`)
- Users may edit predictions freely until the lock
- **Three-layer enforcement** (all required, none optional):
  1. UI: form disabled when lock time has passed
  2. Changeset: validation rejects late submissions
  3. Database: `SELECT … FOR UPDATE` on match row inside transaction, re-check lock
- `Prode.Predictions.MatchLocker` GenServer fires exactly at `prediction_lock_at` and sets `match.locked = true`

### Tournament scope
- **v1 supports the FIFA World Cup only**
- Tournament has 8 group stages (A-H) + R16, QF, SF, 3rd place, Final
- All knockout stages have `points_multiplier: 2.0`

### Groups
- **Invite-only via 6-character alphanumeric code** in v1
- No public discovery, no group chat in v1
- Group owners can become admins; flat permission model otherwise

### External API access
- **All API-Football calls go through `Prode.External.RateLimiter`** — never call Req directly from contexts or LiveViews
- The `MatchPoller` GenServer is the **only** process that polls fixtures
- Other parts of the system get updates via PubSub broadcasts on `"match:#{id}"`, never by hitting the API
- Honor rate-limit headers; back off when `x-ratelimit-requests-remaining < 200`
- Pro tier ($19/mo) is required before tournament kickoff — free tier (100 req/day) is dev only

### Auth & notifications
- Google Sign-In is primary; email/password is fallback
- Web push (W3C) + opt-in WhatsApp (Meta Cloud API)
- Notifications fire only on match start and match end in v1
- Hard cap: max 1 push per user per match, max 3 WhatsApp per user per day

### Monetization
- **No payments in v1.** Do not add Stripe, MercadoPago, or any payment-related code without explicit instruction.

---

## Architecture conventions

### Context boundaries are strict
- Contexts: `Accounts`, `Tournaments`, `Matches`, `Predictions`, `Scoring`, `Groups`, `Notifications`
- A context's schemas are private to that context
- Never `alias Other.Context.Schema` and query it directly — call the context's public function instead
- If you need data across contexts, the calling context exposes a public function that returns plain data

### Pure logic isolation
- `Prode.Scoring.Engine` has no Repo calls, no PubSub broadcasts, no side effects
- It takes structs in, returns numbers out
- All side-effecting work (updating predictions, broadcasting, enqueuing jobs) lives in workers and contexts

### Real-time updates via PubSub
- Topics: `"match:#{id}"`, `"group:#{id}"`, `"user:#{id}"`, `"tournament:#{id}"`
- Only the `MatchPoller` and Oban workers broadcast; LiveViews subscribe only
- Never call `Phoenix.PubSub.broadcast` from inside a LiveView event handler

### Background jobs
- All deferred work goes through Oban (queues: `default`, `scoring`, `notifications`, `external_api`, `sync`)
- Workers must be idempotent — use `calculated_at` or similar timestamps to detect re-runs
- Cron jobs use `Oban.Plugins.Cron`, not `:timer` or Quantum

### Testing
- External APIs mocked via `Mox` against `Prode.External.SportsDataClient` behaviour
- Real HTTP recorded with `Bypass` in a separate integration suite (not on every test run)
- Concurrent tests use `Ecto.Adapters.SQL.Sandbox` in shared mode
- Use `ExMachina` factories from `Prode.Factory`; never hand-build entities in tests
- Scoring engine has table-driven tests covering every outcome × stage combination

### Naming & style
- English for code, comments, module names, and commit messages
- Spanish for user-facing strings (Argentine audience primary)
- `mix format` is non-negotiable — CI rejects unformatted code
- `mix credo --strict` must pass before merging

---

## Where to start a session

Always confirm which phase or day of `docs/PLAN.md` is being worked on **before** writing code. If unclear, ask the user. Section 14 (day-by-day breakdown) is the authoritative sequence.

Each day in the plan has a concrete "end-of-day deliverable" — match the work to it, do not expand scope beyond it.

---

## Workflow expectations

1. **Read first, code second.** Before any non-trivial change, read the relevant files and `docs/PLAN.md` section. Confirm understanding before editing.
2. **Plan before implementing.** For anything beyond a one-file change, present a plan and wait for approval.
3. **Test as you go.** New context functions get tests in the same commit. New schemas get changeset tests.
4. **Commit per logical unit.** Small commits with clear messages, not end-of-day mega-commits.
5. **Honest reporting.** If something didn't work or got skipped, say so explicitly. Do not paper over partial work.

---

## Environment variables (development)

Required in `.env` (loaded via dotenv or direnv):

```
API_FOOTBALL_KEY=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
VAPID_PUBLIC_KEY=
VAPID_PRIVATE_KEY=
VAPID_SUBJECT=mailto:dev@prode.local
WHATSAPP_PHONE_NUMBER_ID=
WHATSAPP_ACCESS_TOKEN=
WHATSAPP_BUSINESS_ACCOUNT_ID=
DATABASE_URL=postgres://postgres:postgres@localhost:5432/prode_dev
SECRET_KEY_BASE=  # mix phx.gen.secret
```

Generate `SECRET_KEY_BASE` with `mix phx.gen.secret`. Get the API-Football key from `dashboard.api-football.com`.

---

## Files & directories worth knowing

```
docs/PLAN.md                          # Full development plan — source of truth
lib/prode/                            # Business logic (contexts)
lib/prode/external/                   # External API clients (API-Football, WhatsApp)
lib/prode/scoring/engine.ex           # Pure scoring functions
lib/prode/workers/                    # Oban workers
lib/prode_web/                        # Phoenix layer (controllers, LiveViews, channels)
test/support/factory.ex               # ExMachina factories
test/support/fixtures/api_football/   # Recorded API responses for Bypass
priv/repo/migrations/                 # Database migrations
priv/repo/seeds.exs                   # World Cup tournament + stages seed
```

---

## When stuck or uncertain

- Check `docs/PLAN.md` first
- For API-Football endpoint details: `https://www.api-football.com/documentation-v3`
- For Phoenix/LiveView patterns: prefer current `hexdocs.pm` over training-data memory
- For ambiguity in product behavior: ask the user, do not guess
