# Prode World Cup — Development Plan v1

**Project:** Customized football prediction application for the FIFA World Cup
**Stack:** Elixir 1.17+ / Phoenix 1.7 / Phoenix LiveView 1.0 / PostgreSQL 16
**Data Provider:** API-Football v3 (api-sports.io)
**Target Launch:** v1 in 2 weeks (backend-only, no UI design yet)
**Monetization:** None for v1
**Document version:** 1.0 — May 2026

---

## Table of Contents

1. [Locked Decisions Summary](#1-locked-decisions-summary)
2. [Scope and Non-Goals for v1](#2-scope-and-non-goals-for-v1)
3. [Constraints from API-Football](#3-constraints-from-api-football)
4. [System Architecture](#4-system-architecture)
5. [Domain Model and Schemas](#5-domain-model-and-schemas)
6. [Backend Contexts](#6-backend-contexts)
7. [GenServers and Processes](#7-genservers-and-processes)
8. [Oban Workers](#8-oban-workers)
9. [Authentication and Notifications](#9-authentication-and-notifications)
10. [Scoring Engine — Detailed Rules](#10-scoring-engine--detailed-rules)
11. [Key Code Examples](#11-key-code-examples)
12. [Testing Strategy](#12-testing-strategy)
13. [Two-Week Execution Plan](#13-two-week-execution-plan)
14. [Day-by-Day Breakdown](#14-day-by-day-breakdown)
15. [Risk Register](#15-risk-register)
16. [Post-v1 Roadmap](#16-post-v1-roadmap)
17. [Frontend Plan — Overview](#17-frontend-plan--overview)
18. [Frontend Design System](#18-frontend-design-system)
19. [LiveView Architecture](#19-liveview-architecture)
20. [The Five Pages — Detailed Specs](#20-the-five-pages--detailed-specs)
21. [Frontend Day-by-Day Breakdown](#21-frontend-day-by-day-breakdown)
22. [Frontend Risk Register](#22-frontend-risk-register)

---

## 1. Locked Decisions Summary

These decisions are now fixed for v1 based on the requirements gathering session:

| Decision area              | v1 choice                                                                  |
| -------------------------- | -------------------------------------------------------------------------- |
| Data provider              | API-Football v3 (`https://v3.football.api-sports.io`)                      |
| Tournament scope           | FIFA World Cup only                                                        |
| Monetization               | None in v1; revisit after launch                                           |
| Authentication             | Google Sign-In (primary), email/password as fallback                       |
| Notifications              | Web push on mobile + opt-in WhatsApp (kickoff and final whistle)           |
| Scoring (group stage)      | 5 pts exact score, 3 pts correct outcome, 0 pts incorrect                  |
| Scoring (knockout)         | 2× multiplier on the above (10 / 6 / 0)                                    |
| Bonus predictions          | +10 pts for top scorer, +10 pts for group winner                           |
| Groups                     | Invite-only by code, no public discovery in v1                             |
| Prediction edits           | Allowed up to 15 minutes before kickoff                                    |
| Frontend                   | Deferred — build backend only, design provided after v1 backend complete   |
| Deployment                 | Decide on launch (local + staging on Fly.io free tier during development)  |
| Team size                  | Solo developer                                                             |

---

## 2. Scope and Non-Goals for v1

### In scope

- World Cup fixture sync from API-Football
- User signup, login (Google + email)
- Match predictions with 15-minute lock window
- Bonus predictions (top scorer, group winners) — locked at tournament kickoff
- Private invite-only groups with shareable codes
- Per-group leaderboards and a global leaderboard
- Real-time score updates during live matches
- Real-time leaderboard updates as matches finish
- Notification dispatch on match start and match end
- A complete REST/Phoenix.Channel/LiveSocket-ready API surface for the future frontend

### Explicitly out of scope for v1

- Visual design system (waiting on user-provided designs)
- Payments and premium features
- Other tournaments (Liga, Libertadores, Champions League)
- Public groups, group discovery, group chat
- Native mobile apps (web app only, mobile-first responsive)
- Advanced statistics dashboards
- Multi-language support beyond Spanish (Argentina audience primary)

---

## 3. Constraints from API-Football

The free tier of API-Football has hard constraints that shape the architecture:

- **100 requests per day on the free tier**, resetting at 00:00 UTC
- **Pro tier ($19/month)** raises this to 7,500 requests/day — strongly recommended once the World Cup starts
- All endpoints are `GET` only, no webhooks. **Push notifications must be simulated by polling on the backend and broadcasting via PubSub.**
- Authentication via `x-apisports-key` header
- Rate-limit headers on every response: `x-ratelimit-requests-remaining`, `X-RateLimit-Remaining` (per-minute)
- The `/status` endpoint does not count against quota and should be used for health checks

### Endpoint usage plan

| Endpoint                          | Frequency                          | Daily cost estimate          |
| --------------------------------- | ---------------------------------- | ---------------------------- |
| `/leagues?id=1&season=2026`       | Once on setup                      | ~1 request                   |
| `/fixtures?league=1&season=2026`  | Once daily at 04:00 UTC            | ~1 request                   |
| `/fixtures?id=X` (per live match) | Every 30s during live matches only | ~120/match × concurrent      |
| `/fixtures/events?fixture=X`      | Every 60s during live matches only | ~60/match × concurrent       |
| `/players/topscorers`             | Once daily                         | ~1 request                   |
| `/status`                         | Hourly health check                | Free, doesn't count          |

**Conclusion on tier:** During group stage (often 4 matches per day with up to 2 concurrent), free tier 100 req/day is exhausted in roughly 25 minutes of live polling. **The Pro tier ($19/month) must be active before the first match kicks off.** Plan a budget line item.

### Defensive measures

- Cache all non-live data in PostgreSQL with TTLs
- Single centralized poller (one GenServer) that fan-outs via PubSub — never let LiveViews call the external API
- Honor 429 responses with exponential backoff
- Read rate-limit headers and pause polling when `x-ratelimit-requests-remaining` drops below a safety threshold

---

## 4. System Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│              Future Frontend (LiveView, deferred to post-v1)           │
└────────────────────────────────────────┬───────────────────────────────┘
                                         │ WebSocket (LiveView)
                                         │ + JSON API endpoints
┌────────────────────────────────────────▼───────────────────────────────┐
│                          Phoenix Endpoint                              │
│  ┌──────────────────┐  ┌────────────────────┐  ┌────────────────────┐ │
│  │  Auth Pipeline   │  │   JSON API         │  │  LiveView mount    │ │
│  │  (Google OAuth)  │  │   /api/v1/*        │  │   (post-v1)        │ │
│  └──────────────────┘  └────────────────────┘  └────────────────────┘ │
└────────────────────────────────────────┬───────────────────────────────┘
                                         │
                              ┌──────────▼──────────┐
                              │  Context Layer      │
                              │  (Business Logic)   │
                              └──────────┬──────────┘
                                         │
        ┌────────────────────────────────┼────────────────────────────┐
        │                                │                            │
        ▼                                ▼                            ▼
┌───────────────┐              ┌──────────────────┐         ┌────────────────┐
│   Postgres    │              │  Phoenix PubSub  │         │  Oban Queues   │
│   (Ecto)      │              │   (real-time)    │         │ (background)   │
└───────────────┘              └────────┬─────────┘         └────────┬───────┘
                                        │                            │
                              ┌─────────┴────────┐         ┌─────────┴────────┐
                              │   GenServers     │         │     Workers      │
                              │ ┌──────────────┐ │         │ ┌──────────────┐ │
                              │ │ MatchPoller  │ │         │ │FixtureSync   │ │
                              │ │ MatchLocker  │ │         │ │PointsCalc    │ │
                              │ │ ScoreEngine  │ │         │ │Notification  │ │
                              │ │ RateLimiter  │ │         │ │TopScorerSync │ │
                              │ └──────────────┘ │         │ └──────────────┘ │
                              └──────────────────┘         └──────────────────┘
                                        │                            │
                                        └────────────┬───────────────┘
                                                     │
                                          ┌──────────▼──────────┐
                                          │   API-Football      │
                                          │   (external HTTP)   │
                                          └─────────────────────┘
```

### Why this shape

The single most important architectural decision is centralizing all external API access behind one rate-limited GenServer. With 100 daily requests on the free tier (or even 7,500 on Pro), letting every LiveView fetch its own match data would burn the quota in minutes. The `MatchPoller` is the only process that talks to API-Football. Everything else subscribes to PubSub topics it broadcasts.

Phoenix PubSub becomes the central nervous system: match updates fan out to all connected clients via `"match:#{id}"` topics, and leaderboard recalculations broadcast on `"group:#{id}"` topics. This keeps the API quota usage flat regardless of how many users are watching.

---

## 5. Domain Model and Schemas

### Entity relationship overview

```
User ────┬──< Membership >──── Group
         │
         ├──< Prediction >──── Match ────> Team (home/away)
         │                       │
         │                       └──── Tournament ──── Stage
         │
         └──< BonusPrediction >──── Tournament
```

### Schema definitions

**`Prode.Accounts.User`**

```elixir
defmodule Prode.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :hashed_password, :string, redact: true
    field :display_name, :string
    field :google_uid, :string
    field :avatar_url, :string
    field :phone_number, :string          # for WhatsApp
    field :whatsapp_opt_in, :boolean, default: false
    field :timezone, :string, default: "America/Argentina/Buenos_Aires"
    field :confirmed_at, :utc_datetime

    has_many :predictions, Prode.Predictions.Prediction
    has_many :bonus_predictions, Prode.Predictions.BonusPrediction
    has_many :memberships, Prode.Groups.Membership
    has_many :groups, through: [:memberships, :group]

    timestamps()
  end
end
```

**`Prode.Tournaments.Tournament`**

```elixir
schema "tournaments" do
  field :name, :string                      # "FIFA World Cup 2026"
  field :external_id, :integer              # API-Football league ID
  field :season, :integer                   # 2026
  field :starts_at, :utc_datetime
  field :ends_at, :utc_datetime
  field :bonus_predictions_lock_at, :utc_datetime  # tournament kickoff
  field :status, Ecto.Enum, values: [:upcoming, :in_progress, :finished]

  has_many :matches, Prode.Matches.Match
  has_many :stages, Prode.Tournaments.Stage

  timestamps()
end
```

**`Prode.Tournaments.Stage`**

```elixir
schema "stages" do
  field :name, :string                      # "Group A", "Round of 16", "Final"
  field :kind, Ecto.Enum, values: [:group, :round_of_32, :round_of_16, :quarter, :semi, :third_place, :final]
  field :points_multiplier, :float, default: 1.0  # 2.0 for knockout

  belongs_to :tournament, Prode.Tournaments.Tournament
  has_many :matches, Prode.Matches.Match

  timestamps()
end
```

**`Prode.Matches.Match`**

```elixir
schema "matches" do
  field :external_id, :integer              # API-Football fixture ID
  field :kickoff_at, :utc_datetime
  field :status, Ecto.Enum, values: [
    :scheduled, :live, :halftime, :finished,
    :postponed, :cancelled, :awaiting_penalties
  ]
  field :home_score, :integer
  field :away_score, :integer
  field :elapsed_minutes, :integer          # for live display
  field :prediction_lock_at, :utc_datetime  # kickoff - 15 min
  field :locked, :boolean, default: false
  field :venue, :string

  belongs_to :tournament, Prode.Tournaments.Tournament
  belongs_to :stage, Prode.Tournaments.Stage
  belongs_to :home_team, Prode.Tournaments.Team
  belongs_to :away_team, Prode.Tournaments.Team
  has_many :predictions, Prode.Predictions.Prediction

  timestamps()
end
```

**`Prode.Predictions.Prediction`**

```elixir
schema "predictions" do
  field :home_score, :integer
  field :away_score, :integer
  field :points_awarded, :integer, default: 0
  field :calculated_at, :utc_datetime
  field :edit_count, :integer, default: 0

  belongs_to :user, Prode.Accounts.User
  belongs_to :match, Prode.Matches.Match

  timestamps()
end
```

Constraints in migration:

- Unique index on `[:user_id, :match_id]`
- Check constraint: `home_score >= 0 AND home_score < 30`
- Check constraint: `away_score >= 0 AND away_score < 30`
- Foreign key with `on_delete: :restrict` for match — we never want to lose prediction history

**`Prode.Predictions.BonusPrediction`**

```elixir
schema "bonus_predictions" do
  field :kind, Ecto.Enum, values: [:top_scorer, :group_winner]
  field :payload, :map      # %{"group" => "A", "team_id" => 123} or %{"player_id" => 456}
  field :points_awarded, :integer, default: 0
  field :calculated_at, :utc_datetime

  belongs_to :user, Prode.Accounts.User
  belongs_to :tournament, Prode.Tournaments.Tournament

  timestamps()
end
```

**`Prode.Groups.Group`**

```elixir
schema "groups" do
  field :name, :string
  field :description, :string
  field :invite_code, :string               # unique 6-char alphanumeric
  field :max_members, :integer, default: 50

  belongs_to :owner, Prode.Accounts.User
  belongs_to :tournament, Prode.Tournaments.Tournament
  has_many :memberships, Prode.Groups.Membership
  has_many :members, through: [:memberships, :user]

  timestamps()
end
```

**`Prode.Groups.Membership`**

```elixir
schema "memberships" do
  field :role, Ecto.Enum, values: [:member, :admin], default: :member
  field :joined_at, :utc_datetime

  belongs_to :user, Prode.Accounts.User
  belongs_to :group, Prode.Groups.Group

  timestamps()
end
```

---

## 6. Backend Contexts

The application is organized into seven bounded contexts, each owning its own schemas and exposing a public API to the rest of the system. No context reaches across boundaries to another's schemas directly.

### `Prode.Accounts`

Handles users, sessions, Google OAuth flow, and password reset. Public functions: `register_user/1`, `authenticate_by_password/2`, `authenticate_by_google/1`, `update_user/2`, `update_whatsapp_preferences/2`.

### `Prode.Tournaments`

Manages tournament metadata, stages, and teams. Public functions: `get_tournament!/1`, `list_active_tournaments/0`, `create_tournament/1`, `list_stages/1`, `upsert_team/1`.

### `Prode.Matches`

The match lifecycle: scheduled → live → finished. Public functions: `get_match!/1`, `list_upcoming_matches/1`, `list_live_matches/0`, `update_match_from_api/2`, `mark_match_locked/1`.

### `Prode.Predictions`

Where the business value lives. Public functions: `upsert_prediction/1`, `get_user_prediction/2`, `list_user_predictions/2`, `lock_predictions_for_match/1`, `submit_bonus_prediction/1`.

The locking logic deserves special attention. It enforces the rule at three layers:

1. **UI layer** (when frontend exists): disable the form 15 min before kickoff
2. **Changeset validation:** reject predictions if `match.locked == true` or `now > match.prediction_lock_at`
3. **Database transaction:** `SELECT … FOR UPDATE` on the match row, re-check lock, then insert

### `Prode.Scoring`

Pure calculation logic, deliberately isolated for testability. Public functions: `calculate_match_points/2`, `calculate_bonus_points/2`, `apply_stage_multiplier/3`, `rebuild_user_total/2`.

### `Prode.Groups`

Group management and invite codes. Public functions: `create_group/2`, `join_by_invite_code/2`, `list_user_groups/1`, `leaderboard_for_group/2`, `global_leaderboard/1`.

### `Prode.Notifications`

Dispatch layer for web push and WhatsApp. Public functions: `notify_match_start/1`, `notify_match_end/1`, `notify_prediction_locked/2`, `dispatch/3`.

---

## 7. GenServers and Processes

### `Prode.Matches.MatchPoller`

A single named GenServer that polls API-Football on an adaptive schedule. Only one instance runs in the cluster at a time, enforced via `:global` registration so that scaling horizontally doesn't multiply API calls.

Polling logic:

- **No live matches:** poll fixture list once per hour
- **Match within 1 hour of kickoff:** check status every 5 minutes
- **One or more live matches:** poll each live fixture every 30 seconds; poll events every 60 seconds
- **Rate-limit guard:** read response headers; if `x-ratelimit-requests-remaining < 200`, slow polling to once per 5 minutes regardless

On every state change (score change, status transition), it broadcasts:

- `Phoenix.PubSub.broadcast(Prode.PubSub, "match:#{id}", {:match_updated, match})`
- On status `:finished`: also enqueues a `PointsCalculator` Oban job

### `Prode.Predictions.MatchLockerSupervisor` + `MatchLocker`

A `DynamicSupervisor` that spawns one `MatchLocker` per upcoming match. Each locker is just a process that sleeps until `match.prediction_lock_at` (kickoff − 15 min) and then runs the locking transaction.

This approach is more reliable than scheduling an Oban job because the OTP scheduler is microsecond-precise and survives Oban queue backlogs.

### `Prode.External.RateLimiter`

A token-bucket GenServer wrapping all calls to API-Football. Refills tokens based on the per-minute and per-day limits read from the most recent response. Other modules call `RateLimiter.request(fn -> Req.get(…) end)` and get either the response or `{:error, :rate_limited}`.

### `Prode.Scoring.Engine`

Not strictly a GenServer — it's a stateless module used by Oban workers — but worth listing. Contains the pure calculation functions and is the only piece of code that knows the scoring rules.

---

## 8. Oban Workers

Oban handles all deferred work. Queues are configured with appropriate concurrency limits:

```elixir
config :prode, Oban,
  repo: Prode.Repo,
  queues: [
    default: 10,
    scoring: 5,
    notifications: 20,
    external_api: 3,    # serialized via RateLimiter regardless
    sync: 2
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron, crontab: [
      {"0 4 * * *", Prode.Workers.FixtureSyncWorker},
      {"0 5 * * *", Prode.Workers.TopScorerSyncWorker},
      {"*/15 * * * *", Prode.Workers.NotificationSweep}
    ]}
  ]
```

| Worker                              | Trigger                         | Purpose                                                |
| ----------------------------------- | ------------------------------- | ------------------------------------------------------ |
| `FixtureSyncWorker`                 | Daily 04:00 UTC + on demand     | Pull full fixture list, upsert matches                 |
| `PointsCalculator`                  | When match transitions to `:finished` | Calculate points for all predictions on a match  |
| `BonusPointsCalculator`             | At tournament end               | Calculate top scorer and group winner bonuses          |
| `NotificationDispatcher`            | Match start/end + scheduled     | Send push and WhatsApp notifications                   |
| `NotificationSweep`                 | Every 15 min                    | Find matches starting in next 2 hours, enqueue reminders |
| `TopScorerSyncWorker`               | Daily during tournament         | Refresh top scorer data for live bonus calc            |
| `GoogleAccountSync`                 | On user login                   | Refresh profile picture, display name from Google      |

### Why Oban-backed Cron vs Quantum or :timer

Oban's cron plugin uses the same Postgres-backed queue as everything else, which means job execution survives application restarts and gives full observability through the Oban dashboard. `:timer.send_interval` would lose schedule on restart.

---

## 9. Authentication and Notifications

### Authentication

Two paths, unified into the same `users` table:

**Google Sign-In (primary):** `ueberauth` + `ueberauth_google` strategy. The user clicks "Sign in with Google", goes through the OAuth dance, and on callback we either find them by `google_uid` or create a new user with the email and avatar from Google.

**Email/password (fallback):** Generated by `mix phx.gen.auth`, untouched. Useful for users without Google accounts and for development.

```elixir
# config/config.exs
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [
      default_scope: "email profile",
      prompt: "select_account"
    ]}
  ]

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
```

### Notifications

**Web push** uses the W3C Push API with a VAPID key pair, implemented via the `web_push_elixir` library. Browsers register a subscription endpoint, which we store per user. Notifications fire on:

- Match kickoff (only for users who have predicted the match or whose group has)
- Match end (with point delta)
- Group ranking change ≥ 2 positions

**WhatsApp** via the Meta Cloud API (free up to a generous monthly limit for service messages). The opt-in flow:

1. User enters phone number in settings
2. We send a verification code via WhatsApp
3. User enters code; we mark `whatsapp_opt_in: true`

WhatsApp templates must be pre-approved by Meta. Plan templates: `match_starting`, `match_finished_with_points`, `weekly_summary`.

### Notification dispatch logic

```elixir
defmodule Prode.Notifications do
  def notify_match_start(%Match{} = match) do
    match
    |> Predictions.users_with_predictions_for_match()
    |> Enum.each(fn user ->
      %{user_id: user.id, match_id: match.id, kind: "match_start"}
      |> Prode.Workers.NotificationDispatcher.new()
      |> Oban.insert()
    end)
  end
end
```

The worker picks the channels (push, WhatsApp, or both) based on user preferences and dispatches in parallel.

---

## 10. Scoring Engine — Detailed Rules

The locked scoring system for v1:

### Per-match scoring

| Outcome                                              | Group stage points | Knockout points |
| ---------------------------------------------------- | ------------------ | --------------- |
| Exact score (e.g., predicted 2-1, actual 2-1)        | 5                  | 10              |
| Correct outcome, wrong score (predicted 2-1, actual 3-1) | 3              | 6               |
| Incorrect outcome (predicted 2-1, actual 1-2)        | 0                  | 0               |

The "correct outcome" rule means: home win, away win, or draw matches the actual result, even if the exact numbers don't. A 2-1 prediction for a 5-0 actual is still 3 points because both predicted a home win.

### Bonus predictions

Made before the tournament starts (locked at `tournament.bonus_predictions_lock_at`):

- **Top scorer:** Player who scores the most goals across the entire tournament. **+10 points** if correct.
- **Group winner:** For each group (A through H), predict who finishes first. **+10 points per correct group.**

Top scorer ties (multiple players tied with the same goal count) award the bonus to anyone who picked any of them.

### Implementation

```elixir
defmodule Prode.Scoring.Engine do
  alias Prode.Matches.Match
  alias Prode.Predictions.Prediction
  alias Prode.Tournaments.Stage

  @group_stage_points %{exact: 5, outcome: 3, miss: 0}
  @knockout_multiplier 2.0
  @bonus_points 10

  def calculate_match_points(%Prediction{} = prediction, %Match{} = match) do
    base = base_points(prediction, match)
    multiplier = stage_multiplier(match.stage)
    round(base * multiplier)
  end

  defp base_points(p, m) when is_nil(m.home_score) or is_nil(m.away_score), do: 0

  defp base_points(p, m) do
    cond do
      exact_match?(p, m) -> @group_stage_points.exact
      same_outcome?(p, m) -> @group_stage_points.outcome
      true -> @group_stage_points.miss
    end
  end

  defp exact_match?(p, m), do: p.home_score == m.home_score and p.away_score == m.away_score

  defp same_outcome?(p, m), do: outcome(p.home_score, p.away_score) == outcome(m.home_score, m.away_score)

  defp outcome(h, a) when h > a, do: :home
  defp outcome(h, a) when h < a, do: :away
  defp outcome(_, _), do: :draw

  defp stage_multiplier(%Stage{kind: :group}), do: 1.0
  defp stage_multiplier(%Stage{points_multiplier: mult}) when not is_nil(mult), do: mult
  defp stage_multiplier(_), do: @knockout_multiplier

  def calculate_bonus_points(:top_scorer, %{predicted_player_id: pid, actual_top_scorer_ids: actuals}) do
    if pid in actuals, do: @bonus_points, else: 0
  end

  def calculate_bonus_points(:group_winner, %{predicted_team_id: tid, actual_winner_id: actual}) do
    if tid == actual, do: @bonus_points, else: 0
  end
end
```

### Idempotency

The `PointsCalculator` worker uses `calculated_at` to skip already-processed predictions. If a match score is corrected after the fact (rare but possible), the worker can be re-enqueued and will recalculate cleanly.

---

## 11. Key Code Examples

### Prediction submission with race-safe locking

```elixir
defmodule Prode.Predictions do
  alias Prode.{Repo, Matches.Match, Predictions.Prediction}
  import Ecto.Query

  def upsert_prediction(%{user_id: uid, match_id: mid} = attrs) do
    Repo.transaction(fn ->
      # Lock the match row to prevent races with MatchLocker
      match =
        from(m in Match, where: m.id == ^mid, lock: "FOR UPDATE")
        |> Repo.one!()

      cond do
        match.locked ->
          Repo.rollback({:error, :match_locked})

        DateTime.compare(DateTime.utc_now(), match.prediction_lock_at) != :lt ->
          Repo.rollback({:error, :too_late})

        true ->
          existing = Repo.get_by(Prediction, user_id: uid, match_id: mid)
          attrs = if existing, do: Map.put(attrs, :edit_count, existing.edit_count + 1), else: attrs

          %Prediction{}
          |> Prediction.changeset(attrs)
          |> Repo.insert(
            on_conflict: {:replace, [:home_score, :away_score, :edit_count, :updated_at]},
            conflict_target: [:user_id, :match_id]
          )
          |> case do
            {:ok, pred} ->
              Phoenix.PubSub.broadcast(
                Prode.PubSub,
                "user:#{uid}",
                {:prediction_saved, pred}
              )
              pred

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
      end
    end)
  end
end
```

### Match poller core loop

```elixir
defmodule Prode.Matches.MatchPoller do
  use GenServer
  alias Prode.External.ApiFootball
  alias Prode.Matches

  @poll_interval_idle :timer.hours(1)
  @poll_interval_imminent :timer.minutes(5)
  @poll_interval_live :timer.seconds(30)

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: {:global, __MODULE__})

  def init(_state) do
    schedule_poll(:initial)
    {:ok, %{last_poll: nil}}
  end

  def handle_info(:poll, state) do
    live_matches = Matches.list_live_matches()
    imminent_matches = Matches.list_matches_starting_within(:timer.hours(1))

    Enum.each(live_matches, &refresh_match/1)
    Enum.each(imminent_matches, &refresh_match/1)

    next_interval = compute_next_interval(live_matches, imminent_matches)
    schedule_poll(next_interval)
    {:noreply, %{state | last_poll: DateTime.utc_now()}}
  end

  defp refresh_match(match) do
    case ApiFootball.get_fixture(match.external_id) do
      {:ok, data} ->
        case Matches.update_match_from_api(match, data) do
          {:ok, updated} ->
            Phoenix.PubSub.broadcast(Prode.PubSub, "match:#{updated.id}", {:match_updated, updated})

            if match.status != :finished and updated.status == :finished do
              %{match_id: updated.id}
              |> Prode.Workers.PointsCalculator.new()
              |> Oban.insert()
            end
          _ -> :ok
        end

      {:error, :rate_limited} ->
        :ok  # back off, next tick will try again
    end
  end

  defp compute_next_interval([], []), do: @poll_interval_idle
  defp compute_next_interval([], _imminent), do: @poll_interval_imminent
  defp compute_next_interval(_live, _), do: @poll_interval_live

  defp schedule_poll(:initial), do: Process.send_after(self(), :poll, :timer.seconds(5))
  defp schedule_poll(interval), do: Process.send_after(self(), :poll, interval)
end
```

### Points calculator worker

```elixir
defmodule Prode.Workers.PointsCalculator do
  use Oban.Worker, queue: :scoring, max_attempts: 5

  alias Prode.{Repo, Matches, Predictions, Scoring.Engine, Groups}
  import Ecto.Query

  def perform(%Oban.Job{args: %{"match_id" => match_id}}) do
    match = Matches.get_match!(match_id) |> Repo.preload(:stage)

    if match.status == :finished do
      predictions =
        from(p in Predictions.Prediction,
          where: p.match_id == ^match_id,
          where: is_nil(p.calculated_at)
        )
        |> Repo.all()

      Enum.each(predictions, fn pred ->
        points = Engine.calculate_match_points(pred, match)

        pred
        |> Ecto.Changeset.change(%{
          points_awarded: points,
          calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update!()
      end)

      # Broadcast to all groups this match's predictors belong to
      affected_user_ids = Enum.map(predictions, & &1.user_id)
      affected_groups = Groups.list_groups_for_users(affected_user_ids)

      Enum.each(affected_groups, fn group ->
        Phoenix.PubSub.broadcast(Prode.PubSub, "group:#{group.id}", {:leaderboard_updated, group.id})
      end)

      :ok
    else
      {:snooze, 60}  # match not actually finished, try later
    end
  end
end
```

### Leaderboard query (efficient, paginated)

```elixir
defmodule Prode.Groups do
  import Ecto.Query
  alias Prode.{Repo, Predictions.Prediction, Predictions.BonusPrediction, Groups.Membership}

  def leaderboard_for_group(group_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    member_ids_query =
      from m in Membership,
        where: m.group_id == ^group_id,
        select: m.user_id

    match_points =
      from p in Prediction,
        where: p.user_id in subquery(member_ids_query),
        group_by: p.user_id,
        select: %{user_id: p.user_id, points: sum(p.points_awarded)}

    bonus_points =
      from bp in BonusPrediction,
        where: bp.user_id in subquery(member_ids_query),
        group_by: bp.user_id,
        select: %{user_id: bp.user_id, points: sum(bp.points_awarded)}

    # Combine with a CTE for performance on large groups
    Repo.query!("""
    WITH match_pts AS (#{Repo.to_sql(:all, match_points) |> elem(0)}),
         bonus_pts AS (#{Repo.to_sql(:all, bonus_points) |> elem(0)})
    SELECT
      u.id, u.display_name, u.avatar_url,
      COALESCE(m.points, 0) + COALESCE(b.points, 0) AS total
    FROM users u
    LEFT JOIN match_pts m ON m.user_id = u.id
    LEFT JOIN bonus_pts b ON b.user_id = u.id
    WHERE u.id IN (SELECT user_id FROM memberships WHERE group_id = $1)
    ORDER BY total DESC
    LIMIT $2 OFFSET $3
    """, [group_id, limit, offset])
  end
end
```

---

## 12. Testing Strategy

### Test pyramid

```
        ┌──────────────────────┐
        │   Load Tests (k6)    │   5%   - Pre-launch verification
        ├──────────────────────┤
        │  Integration Tests   │   20%  - Full prediction flow, OAuth callback
        ├──────────────────────┤
        │     Unit Tests       │   75%  - Scoring, changesets, contexts
        └──────────────────────┘
```

### Unit tests

**Scoring engine** gets exhaustive table-driven tests covering every permutation:

```elixir
defmodule Prode.Scoring.EngineTest do
  use ExUnit.Case, async: true
  alias Prode.Scoring.Engine
  alias Prode.Matches.Match
  alias Prode.Predictions.Prediction
  alias Prode.Tournaments.Stage

  @group_stage %Stage{kind: :group, points_multiplier: 1.0}
  @knockout %Stage{kind: :quarter, points_multiplier: 2.0}

  describe "calculate_match_points/2 — group stage" do
    test "exact match awards 5 points" do
      pred = %Prediction{home_score: 2, away_score: 1}
      match = %Match{home_score: 2, away_score: 1, stage: @group_stage}
      assert Engine.calculate_match_points(pred, match) == 5
    end

    test "correct outcome wrong score awards 3 points" do
      pred = %Prediction{home_score: 2, away_score: 1}
      match = %Match{home_score: 3, away_score: 0, stage: @group_stage}
      assert Engine.calculate_match_points(pred, match) == 3
    end

    test "wrong outcome awards 0 points" do
      pred = %Prediction{home_score: 2, away_score: 1}
      match = %Match{home_score: 0, away_score: 1, stage: @group_stage}
      assert Engine.calculate_match_points(pred, match) == 0
    end

    test "draw prediction matching draw outcome awards 3 if not exact" do
      pred = %Prediction{home_score: 1, away_score: 1}
      match = %Match{home_score: 2, away_score: 2, stage: @group_stage}
      assert Engine.calculate_match_points(pred, match) == 3
    end
  end

  describe "calculate_match_points/2 — knockout 2x multiplier" do
    test "exact match in quarter awards 10" do
      pred = %Prediction{home_score: 1, away_score: 0}
      match = %Match{home_score: 1, away_score: 0, stage: @knockout}
      assert Engine.calculate_match_points(pred, match) == 10
    end

    test "correct outcome in quarter awards 6" do
      pred = %Prediction{home_score: 2, away_score: 1}
      match = %Match{home_score: 4, away_score: 1, stage: @knockout}
      assert Engine.calculate_match_points(pred, match) == 6
    end
  end

  describe "calculate_match_points/2 — edge cases" do
    test "unfinished match (nil scores) awards 0" do
      pred = %Prediction{home_score: 2, away_score: 1}
      match = %Match{home_score: nil, away_score: nil, stage: @group_stage}
      assert Engine.calculate_match_points(pred, match) == 0
    end
  end
end
```

### Integration tests

**Prediction flow** uses `Ecto.Adapters.SQL.Sandbox` with concurrent mode to verify the locking transaction holds under race conditions:

```elixir
test "concurrent submission and lock racing rejects late prediction" do
  match = insert(:match, prediction_lock_at: DateTime.add(DateTime.utc_now(), -1, :second))
  user = insert(:user)

  result = Predictions.upsert_prediction(%{
    user_id: user.id,
    match_id: match.id,
    home_score: 2,
    away_score: 1
  })

  assert {:error, :too_late} = result
end
```

### External API mocking

`SportsDataClient` defined as a behaviour. Tests use `Mox`; integration runs use `Bypass` with recorded fixtures from the real API.

```elixir
defmodule Prode.External.SportsDataClient do
  @callback get_fixture(integer()) :: {:ok, map()} | {:error, term()}
  @callback list_fixtures(map()) :: {:ok, [map()]} | {:error, term()}
end
```

### Load tests (pre-launch only)

`k6` script simulates the Argentina vs Brazil scenario:

- 20,000 concurrent users
- 8,000 prediction submissions in the final 10 minutes before kickoff
- 50,000 leaderboard polls after final whistle within 5 minutes

Acceptance criteria:

- p99 prediction submission latency < 300ms
- Zero predictions accepted after `match.prediction_lock_at`
- Leaderboard updates broadcast within 2 seconds of `PointsCalculator` completing
- Database connection pool never saturates above 80%

---

## 13. Two-Week Execution Plan

The 2-week target requires aggressive scope discipline. The plan below ships a working backend (no UI yet) by end of week 2. The "shippable" form is a documented JSON API plus an admin LiveDashboard view for operational monitoring.

### Week 1 — Foundation and core loop

| Day | Focus                                                                              |
| --- | ---------------------------------------------------------------------------------- |
| 1   | Project scaffold, deployment pipeline, Google OAuth                                |
| 2   | API-Football client + RateLimiter + Bypass test fixtures                           |
| 3   | Tournaments + Stages + Teams schemas and contexts                                  |
| 4   | Matches schema, FixtureSyncWorker, MatchPoller                                     |
| 5   | Predictions schema and context with three-layer locking                            |
| 6   | Scoring engine with full unit test coverage                                        |
| 7   | PointsCalculator worker + idempotency tests; buffer for spillover                  |

### Week 2 — Social, notifications, polish

| Day | Focus                                                                              |
| --- | ---------------------------------------------------------------------------------- |
| 8   | Groups + Memberships + invite codes; leaderboard queries                           |
| 9   | Bonus predictions (top scorer + group winners) with lock logic                     |
| 10  | Notifications context, web push setup, WhatsApp opt-in flow                        |
| 11  | NotificationDispatcher worker, NotificationSweep cron, dispatch logic              |
| 12  | JSON API endpoints, OpenAPI/Swagger spec, Phoenix.Channel setup for future LV      |
| 13  | End-to-end integration tests, load test setup with k6                              |
| 14  | Bug fixes, observability (Telemetry), documentation, deploy to staging             |

### What's not in the 2-week build

- LiveView UI modules (deferred until designs arrive)
- Native mobile app
- Payments
- Tournaments beyond World Cup
- Advanced analytics

---

## 14. Day-by-Day Breakdown

### Day 1 — Foundation

- `mix phx.new prode --live --binary-id`
- Add to `mix.exs`: `oban`, `req`, `ueberauth`, `ueberauth_google`, `bcrypt_elixir`, `bypass`, `mox`, `ex_machina`, `excoveralls`, `credo`, `dialyxir`
- Set up `.tool-versions` (Elixir 1.17, OTP 27, Node 20)
- Initialize Git, set up GitHub repo with branch protection
- GitHub Actions workflow: `mix format --check`, `mix credo --strict`, `mix test`
- Run `mix phx.gen.auth` for email/password baseline
- Configure `ueberauth_google` strategy, add OAuth callback controller
- Add Tailwind (since the future frontend will need it) but no design yet
- Deploy "Hello, Prode" page to Fly.io staging
- Set up Postgres on Fly Postgres or Neon free tier

**End-of-day deliverable:** Public URL where a user can sign in with Google and see their profile.

### Day 2 — External API client

- Define `Prode.External.SportsDataClient` behaviour
- Implement `Prode.External.ApiFootball` using `Req` with `x-apisports-key` header
- Implement `Prode.External.RateLimiter` GenServer with token-bucket logic
- Write Mox-based test implementation
- Record real API responses for fixture list, single fixture, top scorers (use `Bypass` to replay them in tests)
- Add `Prode.External.RateLimiter` to application supervision tree
- Manually verify free-tier quota tracking by hitting `/status`

**End-of-day deliverable:** `iex> ApiFootball.list_fixtures(league: 1, season: 2026)` returns real data and respects rate limits.

### Day 3 — Tournament domain

- Create migrations for `tournaments`, `stages`, `teams`
- Define schemas with associations
- Build `Prode.Tournaments` context with `get_tournament!/1`, `list_active_tournaments/0`, etc.
- Seed the World Cup tournament record and stage records (Group A-H, R16, QF, SF, 3rd, Final)
- Multiplier on stages: 1.0 for `:group`, 2.0 for all knockout stages
- Write context tests with factories

**End-of-day deliverable:** World Cup tournament exists in the database with all 8 group stages and knockout stages seeded.

### Day 4 — Matches and sync

- Migration for `matches` with all needed fields including `prediction_lock_at`
- `Prode.Matches` context
- `Prode.Workers.FixtureSyncWorker` that pulls fixtures from API-Football and upserts matches
- Run it manually to populate matches
- `Prode.Matches.MatchPoller` GenServer with adaptive polling
- PubSub broadcasts on match updates
- Verify `MatchPoller` doesn't exceed quota in dry-run

**End-of-day deliverable:** Database has all 64 World Cup matches with correct kickoffs and lock times.

### Day 5 — Predictions

- Migration for `predictions` with unique constraint and check constraints
- `Prode.Predictions.Prediction` schema with `changeset/2` enforcing lock at validation level
- `Prode.Predictions.upsert_prediction/1` with `SELECT … FOR UPDATE` transaction
- `Prode.Predictions.MatchLockerSupervisor` (DynamicSupervisor) + `MatchLocker` GenServer
- On `FixtureSyncWorker` completion, start a `MatchLocker` for each upcoming match
- Test: late prediction is rejected; on-time prediction succeeds; edit before lock works

**End-of-day deliverable:** `Predictions.upsert_prediction/1` correctly enforces the 15-minute lock window.

### Day 6 — Scoring engine

- `Prode.Scoring.Engine` module with all the formulas from section 10
- Exhaustive unit tests (every outcome × stage combination)
- Test idempotency: re-running calculation produces same result

**End-of-day deliverable:** 100% test coverage on scoring engine, all scenarios verified.

### Day 7 — Points calculator and recovery time

- `Prode.Workers.PointsCalculator` worker
- Hook it up: when `MatchPoller` sees status transition to `:finished`, enqueue the job
- Idempotency check on `calculated_at`
- Broadcast to affected groups on completion
- **Spillover buffer:** anything from days 1-6 that ran long gets caught up here
- End-of-week retrospective: what's behind, what's at risk

**End-of-day deliverable:** Simulated finished match (manual fixture status update in DB) triggers point calculation and group leaderboard broadcasts.

### Day 8 — Groups

- Migrations for `groups`, `memberships`
- Invite code generation (6-char alphanumeric, unique)
- `Prode.Groups` context with `create_group`, `join_by_invite_code`, etc.
- Leaderboard query (the CTE approach from section 11)
- Test: 10,000 fake users in a group, leaderboard query under 200ms

**End-of-day deliverable:** Two users can create groups, share codes, join each other's groups, and see leaderboards.

### Day 9 — Bonus predictions

- Migration for `bonus_predictions`
- Schema and context functions
- Lock at `tournament.bonus_predictions_lock_at` (tournament kickoff)
- `Prode.Workers.BonusPointsCalculator` (runs at tournament end)
- `Prode.Workers.TopScorerSyncWorker` (daily during tournament)

**End-of-day deliverable:** Users can submit top scorer and group winner predictions, locked at tournament start.

### Day 10 — Notification infrastructure

- Add `web_push_elixir` dependency
- Generate VAPID keys, store in env vars
- Migration for `push_subscriptions` table (one user can have multiple devices)
- WhatsApp Cloud API client (also via `Req`)
- WhatsApp template registration walkthrough (Meta Business setup is a manual side quest)
- Phone verification flow (send code, verify code, mark opted in)

**End-of-day deliverable:** Manual `iex> Notifications.send_test(user, :push)` and `:whatsapp` both deliver.

### Day 11 — Notification dispatch

- `Prode.Workers.NotificationDispatcher` worker
- `Prode.Workers.NotificationSweep` cron worker that finds upcoming matches and enqueues dispatch jobs
- Hook into `MatchPoller`: on status `:live`, dispatch match-start notifications; on `:finished`, dispatch match-end with points
- Test full flow end to end

**End-of-day deliverable:** Test match transitioning to live sends real push notification to a phone.

### Day 12 — API surface

- Plug-based JSON API at `/api/v1/*` using `Phoenix.Controller`
- Endpoints: `/auth/google`, `/tournaments`, `/matches`, `/matches/:id/predict`, `/groups`, `/groups/:id/leaderboard`, `/users/me`
- OpenAPI spec generated via `open_api_spex`
- Set up `Phoenix.Channel` topics matching PubSub topics, ready for the future frontend to subscribe
- Bearer token authentication via `Plug.Conn` and session tokens

**End-of-day deliverable:** Full Postman/Insomnia collection of working endpoints; channels join with auth.

### Day 13 — Integration and load testing

- End-to-end test scenarios: signup → join group → predict → match finishes → see leaderboard update
- `k6` script for the Argentina vs Brazil load profile
- Run load test against staging, capture metrics
- Identify and fix top 3 bottlenecks
- Add database indexes where the explain plan shows full table scans

**End-of-day deliverable:** Load test report with metrics meeting acceptance criteria (or documented gaps).

### Day 14 — Observability, docs, deploy

- `Telemetry` instrumentation for key business events (predictions submitted per minute, points calculated per match, notification dispatch latency)
- Phoenix LiveDashboard configured with custom metrics
- `README.md` with setup instructions, architecture overview
- `RUNBOOK.md` for operational scenarios (rate limit hit, match data wrong, user can't login)
- Tag release `v0.1.0-backend`
- Deploy to staging with Pro-tier API-Football key
- Manual smoke test of full flow on staging

**End-of-day deliverable:** Tagged release, staging environment running, ready to plug in frontend designs.

---

## 15. Risk Register

| Risk                                                | Likelihood | Impact   | Mitigation                                                                          |
| --------------------------------------------------- | ---------- | -------- | ----------------------------------------------------------------------------------- |
| API-Football free tier exhausted in testing         | High       | Medium   | Use Bypass with recorded fixtures for 95% of testing; reserve real API for staging  |
| WhatsApp template approval delays                   | High       | Low      | Submit templates Day 1; have email fallback ready                                   |
| Google OAuth setup snags                            | Medium     | Low      | Pre-create OAuth credentials and test locally on Day 1                              |
| Two-week timeline slips                             | High       | Medium   | Day 7 buffer; cut bonus predictions or WhatsApp to email-only if needed             |
| API-Football coverage gaps for World Cup specifics  | Medium     | High     | Verify endpoint coverage Day 2 with real World Cup season ID                       |
| Concurrent prediction race conditions               | Medium     | High     | Three-layer locking + concurrent integration tests                                  |
| Notification spam complaints                        | Medium     | Medium   | Hard cap: max 1 push per user per match, max 3 WhatsApp per user per day            |
| Pro-tier API-Football payment delays                | Low        | Critical | Activate Pro tier 2 weeks before tournament starts                                  |

---

## 16. Post-v1 Roadmap

In rough priority order, what comes after the 2-week backend:

1. **Frontend integration** (1-2 weeks) — Plug the user-provided designs into LiveView modules
2. **Friend invites via WhatsApp** (3 days) — Deep-link invite codes that prefill the join flow
3. **In-app group chat** (1 week) — Phoenix Channels for per-group messaging
4. **Advanced statistics** (1 week) — Hit rates, streak tracking, head-to-head against group members
5. **Additional tournaments** (1-2 weeks per tournament) — Liga Profesional, Copa Libertadores, Premier League
6. **Payments and premium tier** (2-3 weeks) — MercadoPago integration, premium-only group features
7. **Native push via Capacitor or React Native wrapper** (2-3 weeks) — If web push proves insufficient
8. **AI-powered prediction suggestions** (2 weeks) — Use API-Football's `/predictions` endpoint as a baseline, layer LLM commentary

---

## Appendix A — Dependencies

```elixir
defp deps do
  [
    # Core framework
    {:phoenix, "~> 1.7.14"},
    {:phoenix_ecto, "~> 4.5"},
    {:phoenix_html, "~> 4.1"},
    {:phoenix_live_view, "~> 1.0"},
    {:phoenix_live_dashboard, "~> 0.8"},

    # Database
    {:ecto_sql, "~> 3.11"},
    {:postgrex, ">= 0.0.0"},

    # Background jobs
    {:oban, "~> 2.18"},

    # HTTP
    {:req, "~> 0.5"},
    {:bandit, "~> 1.5"},

    # Authentication
    {:bcrypt_elixir, "~> 3.0"},
    {:ueberauth, "~> 0.10"},
    {:ueberauth_google, "~> 0.12"},

    # Notifications
    {:web_push_elixir, "~> 0.3"},
    {:swoosh, "~> 1.16"},

    # Observability
    {:telemetry_metrics, "~> 1.0"},
    {:telemetry_poller, "~> 1.1"},

    # API documentation
    {:open_api_spex, "~> 3.19"},

    # Testing
    {:ex_machina, "~> 2.7", only: :test},
    {:mox, "~> 1.1", only: :test},
    {:bypass, "~> 2.1", only: :test},
    {:excoveralls, "~> 0.18", only: :test},

    # Code quality
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev], runtime: false},

    # Utilities
    {:gettext, "~> 0.24"},
    {:jason, "~> 1.4"},
    {:tzdata, "~> 1.1"}  # Timezone DB for Argentina time
  ]
end
```

## Appendix B — Environment Variables

```bash
# API-Football
API_FOOTBALL_KEY=your_key_here

# Google OAuth
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...

# Web Push (VAPID)
VAPID_PUBLIC_KEY=...
VAPID_PRIVATE_KEY=...
VAPID_SUBJECT=mailto:admin@prode.app

# WhatsApp Cloud API
WHATSAPP_PHONE_NUMBER_ID=...
WHATSAPP_ACCESS_TOKEN=...
WHATSAPP_BUSINESS_ACCOUNT_ID=...

# Database
DATABASE_URL=postgres://...

# Phoenix
SECRET_KEY_BASE=...  # generate with mix phx.gen.secret
PHX_HOST=prode.app
PORT=4000
```

## Appendix C — Where to Start (Concrete First Steps)

If you sit down right now, in this order:

1. Create an API-Football account at `dashboard.api-football.com/register` and get the free-tier key. Test it with `curl -H "x-apisports-key: YOUR_KEY" https://v3.football.api-sports.io/status` and verify you see your account info.
2. Confirm the World Cup 2026 league ID by calling `https://v3.football.api-sports.io/leagues?search=world` and inspecting the response.
3. Create a Google Cloud project, enable the Google+ API (or Identity Platform), and generate OAuth 2.0 credentials for `http://localhost:4000/auth/google/callback` and your eventual production callback URL.
4. Sign up for a Meta Business account if you don't have one, and start the WhatsApp Cloud API onboarding — template approval takes 24-48 hours and is the longest pole in the schedule.
5. Run `mix phx.new prode --live --binary-id` and commit the initial scaffold. From there, follow Day 1 of the breakdown above.

The first commit should land within an hour of starting. The first deployed "Hello, Prode" should land within four hours. If either of those slips significantly, the 2-week timeline is already at risk and scope needs to be trimmed.

---

*End of backend document — frontend plan continues below.*

---

## 17. Frontend Plan — Overview

**Status:** Backend complete (Days 1-14). Frontend begins Day 15.

**Design inspiration:** `docs/prode-master_mock.html` — a mobile-first football prediction app with 5-tab bottom nav, match cards, a bottom-sheet prediction entry UI, and a podium leaderboard. We build our own implementation inspired by this UX; we do not copy CSS or HTML verbatim. No ads. No premium/"PLUS" tier in v1.

**End-of-frontend deliverable:** A user can sign in on a phone browser, submit predictions for all World Cup matches, watch live scores update in real time, and see their position in a group leaderboard — all through a polished Spanish-language mobile-first UI.

### Technology decisions

| Decision | Choice | Rationale |
|---|---|---|
| UI layer | Phoenix LiveView 1.1 | Already in stack; avoids a separate JS build step and SPA complexity |
| Styling | Tailwind CSS v4 (bundled with Phoenix 1.8) | Utility-first, purges unused CSS, good mobile-first support |
| Micro-interactions | Alpine.js (CDN, ~10 KB) | Bottom sheet open/close, accordion, tab transitions — too simple to warrant a full JS framework |
| Icons | Heroicons (already in Phoenix) + custom SVG for flags/trophy | Minimal bundle addition |
| Fonts | Google Fonts CDN — Barlow Condensed 600/700/800, Inter 400/500/600/700 | Match the mock's typographic hierarchy |
| Real-time | Phoenix LiveView PubSub (already wired in backend) | No extra tooling; handles leaderboard and score updates |
| Mobile viewport | `<meta name="viewport" content="width=device-width, initial-scale=1.0">` | Portrait-locked PWA feel |
| No SPA | LiveView navigate/patch for tab switches | Standard LiveView navigation, no React Router |

### What we skip from the mock

- Ad banners (all banner slots removed)
- "PLUS" premium card in Más tab
- Pre-roll interstitial popup
- Any payment or upgrade CTAs

---

## 18. Frontend Design System

All values below go into `assets/css/app.css` as Tailwind CSS custom properties and utility classes.

### Color palette

```css
:root {
  --color-red:       #e8202a;   /* primary — CTAs, header, active tab */
  --color-red-dark:  #c11820;   /* hover state */
  --color-red-soft:  #fdecec;   /* background tint for prediction cells */
  --color-red-tint:  #fff5f5;   /* hover bg on cards */

  --color-bg:        #f5f6f8;   /* app background */
  --color-card:      #ffffff;   /* card surfaces */

  --color-ink:       #1a1a1a;   /* primary text */
  --color-ink-2:     #2d2d2d;   /* secondary text */
  --color-muted:     #8a8f98;   /* labels, timestamps */
  --color-muted-2:   #b8bcc4;   /* placeholders, disabled */

  --color-line:      #e6e8ec;   /* dividers, borders */
  --color-line-soft: #eef0f3;   /* subtle separators */

  --color-green:     #1fb866;   /* live indicator, saved badge */
  --color-green-soft:#e6f7ee;   /* saved card glow */

  --color-gold:      #e0a800;   /* leaderboard #1 podium */
  --color-silver:    #9ba0ab;   /* leaderboard #2 podium */
  --color-bronze:    #c46f35;   /* leaderboard #3 podium */

  --color-gold-soft: #fff7d6;
}
```

Tailwind config (`tailwind.config.js`) maps these as semantic aliases so we can write `bg-brand`, `text-brand`, `border-brand` etc.

### Typography

```
Barlow Condensed — headings, scores, stage labels, team codes
  700 → section titles ("FASE DE GRUPOS"), leaderboard ranks
  800 → large score display in bottom sheet stepper

Inter — body copy, labels, timestamps, button text
  400 → descriptions, muted text
  500 → body labels
  600 → names, prediction counts
  700 → totals, points
```

Utility classes to add:
- `.font-heading` → `font-family: 'Barlow Condensed'; font-weight: 700; letter-spacing: 1.5px; text-transform: uppercase;`
- `.font-score` → `font-family: 'Barlow Condensed'; font-weight: 800; font-size: 2.25rem;`

### Spacing and shape

- Card border-radius: `14px` (`rounded-[14px]`)
- Bottom sheet border-radius top corners: `24px`
- Button border-radius: `12px`
- Standard card padding: `16px 18px`
- Standard page horizontal padding: `16px`

### Shadows

```css
.shadow-card  { box-shadow: 0 1px 3px rgba(0,0,0,.05); }
.shadow-sheet { box-shadow: 0 -8px 40px rgba(0,0,0,.15); }
.shadow-header{ box-shadow: 0 2px 12px rgba(232,32,42,.25); }
```

### Motion

- Card tap feedback: `scale(0.99)` on `:active`, `transition: transform 200ms ease`
- Bottom sheet entry: `translateY(100%)` → `translateY(0)`, `transition: transform 350ms cubic-bezier(0.34, 1.56, 0.64, 1)` (spring)
- Progress bar fill: `transition: width 500ms cubic-bezier(0.34, 1.56, 0.64, 1)`
- Tab switch: fade via Alpine.js `x-transition`
- Live dot pulse: `@keyframes pulse` CSS animation

### Component library (Phoenix function components)

Define in `lib/prode_web/components/ui_components.ex`:

| Component | Description |
|---|---|
| `<.match_card>` | Match card with team flags, score cells, status badge |
| `<.score_cell>` | Individual prediction score cell (dashed if empty, colored if filled, locked if past) |
| `<.team_badge>` | Flag emoji + 3-letter code + full name |
| `<.prediction_sheet>` | Bottom sheet wrapper with Alpine.js open/close |
| `<.score_stepper>` | +/- stepper with large Barlow Condensed number display |
| `<.leaderboard_row>` | Rank + avatar initial + name + points, with "YO" badge |
| `<.podium>` | Gold/silver/bronze top-3 display |
| `<.tournament_card>` | Gradient banner card with status badge and stats row |
| `<.tab_bar>` | Fixed bottom nav with 5 tabs, active state |
| `<.live_dot>` | Pulsing green indicator for live matches |
| `<.section_heading>` | Barlow Condensed uppercase section title |
| `<.avatar_initial>` | Colored circle with first letter of display_name |
| `<.progress_bar>` | Animated prediction completion bar |
| `<.round_selector>` | Date/round selector with prev/next arrows |
| `<.flash_banner>` | Success/error flash messages |

---

## 19. LiveView Architecture

### Router layout

```elixir
# lib/prode_web/router.ex (additions)

live_session :app,
  on_mount: [ProdeWeb.UserAuth, ProdeWeb.LiveHelpers],
  layout: {ProdeWeb.Layouts, :app} do

  live "/",               ProdeWeb.PronósticosLive,  :index
  live "/posiciones",     ProdeWeb.PosicionesLive,    :index
  live "/torneos",        ProdeWeb.TorneosLive,       :index
  live "/fixture",        ProdeWeb.FixtureLive,       :index
  live "/mas",            ProdeWeb.MasLive,           :index
end
```

All five routes share one `live_session` so the socket is mounted once and the user stays authenticated across tab switches. Navigation between tabs uses `<.link navigate={~p"/posiciones"}>` — LiveView replaces the page content without a full reload.

### App layout (`lib/prode_web/components/layouts/app.html.heex`)

```
┌─────────────────────────┐
│  Status bar (red bg)    │  44px, fixed
│  Header (red bg)        │  62px, fixed: brand logo + current tournament name
├─────────────────────────┤
│                         │
│  Page content (flex:1)  │  scrollable inner area
│  (rendered @inner_content│
│   from the active LV)   │
│                         │
├─────────────────────────┤
│  Bottom tab bar         │  64px, fixed
│  [Pronósticos|Posiciones│
│   |Torneos|Fixture|Más] │
└─────────────────────────┘
```

The tab bar uses standard Phoenix `<.link navigate>` links, not JavaScript. The active tab is highlighted in red; inactive tabs are muted grey. Icons from Heroicons (mini variant).

### `ProdeWeb.LiveHelpers` on_mount

An `on_mount` hook that assigns shared socket data all LiveViews need:
- `current_user` (already provided by UserAuth)
- `active_tournament` — the current/upcoming World Cup tournament
- `user_groups` — groups the user belongs to (for the Posiciones tab toggle)
- `current_path` — for active tab detection in the tab bar

### PubSub subscriptions by LiveView

| LiveView | Subscribes to | Handles |
|---|---|---|
| `PronósticosLive` | `"match:#{id}"` for visible matches | Score updates, lock state |
| `PosicionesLive` | `"group:#{group.id}"` | Leaderboard refresh on `{:leaderboard_updated, _}` |
| `FixtureLive` | `"match:#{id}"` for all today/tomorrow matches | Live status, score, elapsed time |
| `TorneosLive` | `"tournament:#{id}"` | Status transitions |
| `MasLive` | `"user:#{user.id}"` | Profile updates (WhatsApp verification) |

### State management pattern

Each LiveView holds its domain state in socket assigns. No global shared state. When a PubSub message arrives, the LiveView re-fetches only the affected record and updates the assign — it does not re-fetch the whole page.

Example for `FixtureLive`:

```elixir
def handle_info({:match_updated, match}, socket) do
  matches = Enum.map(socket.assigns.matches, fn m ->
    if m.id == match.id, do: match, else: m
  end)
  {:noreply, assign(socket, matches: matches)}
end
```

### Bottom sheet pattern

The prediction entry bottom sheet is an Alpine.js component. LiveView handles the data; Alpine handles the animation.

```html
<!-- prode_components.ex render -->
<div x-data="{ open: false }" x-on:open-sheet.window="open = true">
  <!-- Match card trigger -->
  <div phx-click={JS.dispatch("open-sheet")} ...>
    <.match_card />
  </div>

  <!-- Sheet backdrop -->
  <div x-show="open" x-transition:enter="ease-out duration-200"
       x-on:click="open = false"
       class="fixed inset-0 bg-black/40 z-40" />

  <!-- Sheet itself -->
  <div x-show="open"
       x-transition:enter="transition ease-[cubic-bezier(0.34,1.56,0.64,1)] duration-350"
       x-transition:enter-start="translate-y-full"
       x-transition:enter-end="translate-y-0"
       class="fixed bottom-0 left-0 right-0 bg-white rounded-t-3xl z-50 pb-safe">
    <%= render_slot(@inner_block) %>
  </div>
</div>
```

The `phx-submit` on the score form inside the sheet calls `handle_event("submit_prediction", ...)` in the LiveView. On success, the LiveView sends a JS command to close the sheet and updates the match card's score cells in place.

---

## 20. The Five Pages — Detailed Specs

### Page 1 — Pronósticos (default, route `/`)

**Purpose:** Submit and review predictions for upcoming matches.

**Socket assigns:**
- `matches` — list of matches for the selected round/day, preloaded with home_team, away_team, stage
- `predictions` — map of `match_id => prediction` for the current user (nil if no prediction yet)
- `selected_round` — currently displayed round (e.g., "Grupo A", "Octavos")
- `rounds` — list of all rounds with available matches
- `sheet_match` — match currently open in the bottom sheet (nil when closed)
- `sheet_home` / `sheet_away` — current stepper values (integers)

**UI structure:**
```
┌──────────────────────────────────────┐
│ Round selector  [←  Grupo A  →]      │  white card, 54px
│ Progress bar  "3 de 8 predichos"     │  labels + red fill bar
│                                      │
│ FASE DE GRUPOS                       │  section heading
│ ┌────────────────────────────────┐   │
│ │ 🇦🇷 ARG   [2] — [1]   🇧🇷 BRA │   │  match card, saved border
│ │ Hoy 20:00 · Estadio Lusail     │   │
│ └────────────────────────────────┘   │
│ ┌────────────────────────────────┐   │
│ │ 🇩🇪 GER   [ ] — [ ]   🇫🇷 FRA │   │  match card, empty dashes
│ │ Mañana 17:00 · MetLife          │   │
│ └────────────────────────────────┘   │
│ ...                                  │
└──────────────────────────────────────┘
```

**Score cells:**
- Empty (no prediction): dashed border, muted bg
- Filled: white bg, ink number, green left border
- Locked match (past lock time): shows actual score if available; grey bg; lock icon overlay
- Live match: green pulsing border, actual score shown

**Bottom sheet (prediction entry):**
```
┌────────────────────────────────────┐
│  ─────  (drag handle)              │
│  ARG vs BRA · Hoy 20:00            │  match info row
│                                    │
│  Predicciones populares            │  grey label
│  [████░░░] 2-1 · 34%               │  most-predicted line
│  [██░░░░░] 1-0 · 18%               │
│                                    │
│  Tu predicción                     │
│  [−] [  2  ] — [  1  ] [+]         │  Barlow Condensed score stepper
│       ARG           BRA            │
│                                    │
│  [   Guardar predicción   ]        │  red full-width button
└────────────────────────────────────┘
```

The popular-predictions row shows the top 2 most submitted predictions for that match (query: `GROUP BY home_score, away_score ORDER BY count DESC LIMIT 2`). Only show if ≥5 total predictions exist (avoid influencing early predictions).

**Events:**
- `"open_sheet"` — sets `sheet_match`, initializes stepper from existing prediction or 0-0
- `"inc_home"` / `"dec_home"` / `"inc_away"` / `"dec_away"` — update `sheet_home`/`sheet_away` (min 0, max 20)
- `"submit_prediction"` — calls `Predictions.upsert_prediction/1`; on `:ok` updates match card in assigns and closes sheet; on `{:error, :match_locked}` shows flash
- `"prev_round"` / `"next_round"` — changes `selected_round` and reloads `matches`

---

### Page 2 — Posiciones (route `/posiciones`)

**Purpose:** Group leaderboard and global ranking.

**Socket assigns:**
- `active_group` — currently selected group (first of user's groups by default)
- `user_groups` — list of user's groups for the toggle
- `leaderboard` — list of `%{id, display_name, avatar_url, total}` rows (paginated, first 50)
- `user_rank` — current user's rank in the active group
- `total_members` — count of members in the active group

**UI structure:**
```
┌────────────────────────────────────┐
│  [Mis Grupos ▼]  [Global]          │  toggle + group picker
│                                    │
│  PODIO                             │
│     [2] Silver    [1] Gold         │  podium — top 3 visually
│                [3] Bronze          │
│                                    │
│  CLASIFICACIÓN COMPLETA            │
│  1  [JM]  Juan M.       1,240 pts  │
│  2  [AP]  Ana P.        1,115 pts  │
│  3  [LC]  Luis C.       1,080 pts  │  ...
│ 12  [YO]  Vos            840 pts   │  current user row, red bg
└────────────────────────────────────┘
```

Avatar initials are colored using a hash of the user's id mapped to 8 pastel colors (same color is stable across page reloads).

**PubSub:** subscribes to `"group:#{active_group.id}"` on mount. On `{:leaderboard_updated, group_id}` matching the active group, re-fetches leaderboard with a 500ms debounce (avoids hammering DB when many matches finish together).

**Events:**
- `"switch_group"` — changes `active_group`, re-subscribes to new group topic, reloads leaderboard
- `"load_more"` — loads next 50 rows (infinite scroll via `phx-hook="InfiniteScroll"` + tiny JS hook)

---

### Page 3 — Torneos (route `/torneos`)

**Purpose:** Browse tournaments, view stats, pick which tournament's predictions to enter.

**Socket assigns:**
- `tournaments` — list of active/upcoming tournaments (v1: only World Cup)
- `user_stats` — map of `tournament_id => %{predictions_made, points_total, group_rank}`

**UI structure:**
```
┌────────────────────────────────────┐
│  TORNEOS ACTIVOS                   │
│ ┌────────────────────────────────┐ │
│ │ [gradient banner - blue]       │ │
│ │  🏆  FIFA World Cup 2026        │ │
│ │  EN CURSO                      │ │  badge
│ │ ─────────────────────────────  │ │
│ │  42 predichos  · 1,240 pts     │ │  user stats row
│ │  Tu grupo: Los Pibes — 3° de 8 │ │
│ └────────────────────────────────┘ │
│                                    │
│  PRÓXIMOS TORNEOS                  │
│  (empty if none)                   │
└────────────────────────────────────┘
```

Each tournament card links to `/torneos/:id` (a detail LiveView showing stages with their group tables — v2 feature). In v1, the card is informational only; tapping it navigates to the Pronósticos tab filtered to that tournament.

Tournament card gradient colors (Tailwind `from-*` / `to-*`):
- World Cup → `from-blue-700 to-indigo-900`
- Copa América (future) → `from-green-700 to-teal-900`
- Liga (future) → `from-violet-700 to-purple-900`

Status badges:
- `:in_progress` → green pill "EN CURSO"
- `:upcoming` → yellow pill "PRÓXIMO · starts in N days"
- `:finished` → grey pill "FINALIZADO"

---

### Page 4 — Fixture (route `/fixture`)

**Purpose:** Browse all matches grouped by day — with live scores.

**Socket assigns:**
- `days` — list of `%{date: ~D[], matches: [...]}` structs, covering -3 days to +7 days from today
- `scroll_to_today` — boolean, true on first mount (JS hook scrolls to today's section)

**UI structure:**
```
┌────────────────────────────────────┐
│  MARTES 10 JUN                     │  section heading, sticky
│  ┌──────────────────────────────┐  │
│  │ 🟢 VIVO 67'  ARG 2-1 BRA    │  │  live row, green dot
│  └──────────────────────────────┘  │
│  ┌──────────────────────────────┐  │
│  │ 20:00  GER — FRA             │  │  upcoming row
│  └──────────────────────────────┘  │
│                                    │
│  MIÉRCOLES 11 JUN                  │
│  ┌──────────────────────────────┐  │
│  │ 17:00  ESP — POR             │  │
│  └──────────────────────────────┘  │
└────────────────────────────────────┘
```

Each match row shows:
- Time (or "FIN" if finished) — left column
- Team flags + codes — center
- Score (actual if finished/live, dash if upcoming) — right
- If live: green pulsing dot + elapsed minutes

**PubSub:** subscribes to `"match:#{m.id}"` for every match on mount. When a match update arrives, replaces the match in the `days` assigns by date group.

**Performance:** subscribing to potentially 64 match topics is fine — PubSub subscriptions are cheap. We unsubscribe on `terminate/2`.

---

### Page 5 — Más (route `/mas`)

**Purpose:** User profile, settings, sign out. No ads. No premium.

**Socket assigns:**
- `current_user` (from LiveHelpers)
- `changeset` — for WhatsApp opt-in form
- `whatsapp_state` — one of `:idle`, `:code_sent`, `:verified`

**UI structure:**
```
┌────────────────────────────────────┐
│  [Avatar]  Juan Pablo Maletti      │  profile card, red accent
│            juanpi@gmail.com        │
│            Google Sign-In badge    │
│                                    │
│  NOTIFICACIONES                    │  section
│  Push notifications   [toggle]     │
│  WhatsApp             [toggle]     │
│  └─ phone: +54 9 ...  [change]     │  conditional, if opted in
│                                    │
│  PREFERENCIAS                      │
│  Zona horaria  América/Bs.As.  [>] │
│  Idioma        Español         [>] │  (v1: read-only)
│                                    │
│  [  Cerrar sesión  ]               │  red outlined button
└────────────────────────────────────┘
```

WhatsApp opt-in flow (inline in this page):
1. Toggle → phone number input appears
2. User enters number → tap "Enviar código"
3. LiveView calls `Accounts.send_whatsapp_verification/1` → shows 6-digit input
4. User enters code → LiveView calls `Accounts.verify_whatsapp_code/2`
5. On success: toggle shows "verified", phone shown with checkmark

Push notifications toggle calls a JS hook (`PushSubscriptionHook`) that calls `navigator.serviceWorker.register`, then requests permission, then does a `pushManager.subscribe`, then `phx.push("register_push_subscription", {subscription: ...})` to the LiveView.

**Events:**
- `"toggle_push"` — calls `Notifications.upsert_push_subscription/2` or `delete_push_subscription/1`
- `"send_whatsapp_code"` — triggers `Accounts.send_whatsapp_verification/1`
- `"verify_code"` — triggers `Accounts.verify_whatsapp_code/2`
- `"sign_out"` — redirect to `~p"/users/log_out"` (GET, existing gen.auth route)

---

## 21. Frontend Day-by-Day Breakdown

### Day 15 — Design system + layout shell

- Add Google Fonts import to `assets/css/app.css`
- Configure Tailwind with custom color palette, font families, border-radius utilities
- Add `shadow-card`, `shadow-sheet`, `font-heading`, `font-score` custom utilities
- Build the app layout: red header + fixed bottom tab bar (5 tabs)
- Tab bar active state: red icon + label; inactive: muted grey
- Create `lib/prode_web/components/ui_components.ex` with placeholder slot-based components
- Implement `ProdeWeb.LiveHelpers` on_mount
- Wire up all 5 routes and create skeleton LiveView files (mount returns bare assigns, render returns "coming soon" text)
- Verify tab switching works in browser (no full page reload)

**End-of-day deliverable:** Chrome dev tools mobile viewport shows the app shell with working tab navigation.

---

### Day 16 — Match card + round selector

- Implement `<.match_card>` component
  - Team flags (use regional indicator Unicode emoji — e.g., 🇦🇷 from team record `flag_emoji` field if we add it, or CSS flags sprite)
  - Score cells: empty dashes vs filled numbers vs locked actual score
  - Status badges: VIVO, FIN, lock icon
- Implement `<.round_selector>` component (prev/next arrows + round label)
- Implement `<.progress_bar>` component
- Implement `<.section_heading>` component
- Build `PronósticosLive` mount/render: loads matches for first available round, loads user's predictions
- Real data visible in the browser: actual World Cup matches with correct team names

**End-of-day deliverable:** The Pronósticos page shows real match cards with correct data. No prediction submission yet.

---

### Day 17 — Bottom sheet + prediction submission

- Add Alpine.js to `assets/vendor/` (download, add to `app.js` import)
- Implement `<.prediction_sheet>` with Alpine-driven open/close animation
- Implement `<.score_stepper>` — +/- buttons with Barlow Condensed number display
- Wire `phx-click` on match cards to open sheet via `phx-value-match-id`
- Implement `PronósticosLive.handle_event("open_sheet", ...)` — sets `sheet_match` assign
- Implement stepper events: `inc_home`, `dec_home`, `inc_away`, `dec_away`
- Implement `submit_prediction` event — calls `Predictions.upsert_prediction/1`
  - On success: update `predictions` assign, update match card to show saved cells, close sheet via JS push
  - On `{:error, :match_locked}`: flash "El partido ya no acepta pronósticos"
  - On `{:error, :too_late}`: flash "Tiempo de cierre superado"
- Show popular predictions bar inside sheet (top 2 scored predictions for match)

**End-of-day deliverable:** Full prediction submission flow works end to end on mobile browser.

---

### Day 18 — Leaderboard (Posiciones)

- Implement `<.avatar_initial>` component with stable color hash
- Implement `<.podium>` component (gold/silver/bronze top 3 with size difference)
- Implement `<.leaderboard_row>` component with "YO" badge for current user
- Build `PosicionesLive` — mounts with first group's leaderboard, subscribes to PubSub
- Group switcher dropdown (if user has multiple groups)
- PubSub handler: on `{:leaderboard_updated, id}` reload leaderboard data
- "YO" row: if current user is outside top 10, pin their row at bottom of list as sticky
- Load more rows (infinite scroll via `phx-hook` JS hook that watches scroll position)

**End-of-day deliverable:** Leaderboard shows real data, updates within 2 seconds of a simulated match finish.

---

### Day 19 — Fixture + live indicators

- Implement `<.live_dot>` component (CSS keyframe pulse animation)
- Build `FixtureLive` — groups matches by calendar date, subscribes to all match PubSub topics
- Day headings sticky within scroll area
- Match rows: time | teams | score | live indicator
- Handle `{:match_updated, match}` — update the specific match in assigns without full reload
- Scroll-to-today on first mount (JS hook: `document.getElementById("today").scrollIntoView()`)
- Elapsed minutes update for live matches

**End-of-day deliverable:** Fixture page shows all World Cup matches; simulated live match shows pulsing indicator and updates score in real time.

---

### Day 20 — Torneos + Más

**Torneos:**
- Build `TorneosLive` — loads tournaments with user stats
- Implement `<.tournament_card>` with gradient banner, status badge, stats row
- Tap on card navigates to Pronósticos filtered to that tournament (v1: single World Cup, so this is mostly UI polish)

**Más / Profile:**
- Build `MasLive` with profile card, notification settings, sign-out
- Push notification toggle: JS hook (`PushSubscriptionHook`) wires up `navigator.serviceWorker` + `pushManager.subscribe`, calls LiveView on success
- WhatsApp opt-in form (phone input → send code → verify) using existing backend

**End-of-day deliverable:** All 5 tabs have real content. User can sign out.

---

### Day 21 — Polish + mobile testing

- Fix layout issues on iPhone SE (375px) and Pixel 5 (393px) — the two test targets
- Keyboard avoidance: when bottom sheet opens and user taps stepper, ensure keyboard (if any) doesn't cover the sheet — test on iOS Safari
- Add `pb-safe` padding (env(safe-area-inset-bottom)) to tab bar and sheet for notch devices
- PWA manifest: `manifest.json` with theme color `#e8202a`, icons, `display: standalone`, `orientation: portrait`
- Service worker: basic offline cache for app shell (not match data — that's always live)
- Add `<meta name="theme-color" content="#e8202a">` to HTML head
- Test dark mode: use `prefers-color-scheme: dark` media query for card surfaces (optional but nice)
- Run `mix credo --strict` and fix any warnings

**End-of-day deliverable:** App feels like a native app when added to home screen. No layout regressions on both test viewports.

---

### Day 22 — LiveView tests + accessibility

- Write LiveView tests using `Phoenix.LiveViewTest` for critical paths:
  - Prediction submission flow (open sheet → adjust scores → submit → card updates)
  - Leaderboard receives PubSub broadcast and updates
  - Locked match shows lock overlay and rejects late prediction
  - Sign-out redirects to login
- Accessibility pass:
  - All interactive elements have `aria-label` or visible text
  - Color contrast: ink on card bg passes WCAG AA (checked: `#1a1a1a` on `#ffffff` = 18.1:1 ✓)
  - Score cells have `role="group"` and `aria-label="Pronóstico: 2-1"`
  - Bottom sheet has `role="dialog"`, `aria-modal="true"`, focus trap
- Run full test suite: `mix test`

**End-of-day deliverable:** `mix test` passes with LiveView integration tests. No accessibility blockers on axe-core audit.

---

### Day 23 (Buffer / Stretch) — Bonus predictions UI

If Days 15-22 finish on schedule, build the bonus predictions UI:

- New tab or modal accessible from Torneos page: "Bonus Predictions"
- Top scorer picker: searchable player list from `TopScorerSyncWorker` cache
- Group winner picker: 8 dropdowns (one per group A-H) with team options
- Lock countdown: shows time remaining until `tournament.bonus_predictions_lock_at`
- After lock: shows submitted picks read-only with points awarded (if tournament ended)

---

## 22. Frontend Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Alpine.js sheet animation jank on low-end Android | Medium | Low | Test on Moto G4-class device; fallback to instant show/hide if animation stutters |
| iOS Safari safe-area insets missing | Medium | Medium | Use `env(safe-area-inset-bottom)` in CSS; test on physical iPhone or BrowserStack |
| Push notification permission UX — users deny | High | Medium | Explain value before requesting; notification is opt-in; app works fine without it |
| Service worker caching stale LiveView HTML | Low | High | Cache only static assets, not `/_live/` paths; version the cache key |
| 64 PubSub subscriptions on FixtureLive | Low | Low | PubSub subscriptions are in-process ETS lookups; tested at 10k topics, it's fine |
| Flag emoji rendering on Windows | Medium | Low | Most modern browsers render Unicode regional indicators; fallback to team short code text |
| Leaderboard flash on PubSub update (whole list re-renders) | Medium | Low | Use `phx-update="stream"` for list items so LiveView sends minimal patches |
| WhatsApp template approval delay blocking push opt-in | High | Low | Push notification works without WhatsApp; WhatsApp opt-in is opt-in; not a blocker |
| Keyboard + bottom sheet overlap on iOS | Medium | Medium | Use `visualViewport` API hook to shift sheet up when keyboard appears |

---

*End of document.*
