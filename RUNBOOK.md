# Prode — Operational Runbook

Operational reference for common incidents and maintenance tasks.

---

## API-Football rate limit hit

**Symptom:** `[warning] API-Football daily quota low: N requests remaining` in logs. Workers start returning `{:error, :rate_limited}`.

**Action:**
1. Check current quota: `iex> Prode.External.RateLimiter.acquire()` — if it returns `{:error, :rate_limited}` the bucket is empty.
2. The `RateLimiter` backs off automatically when remaining < 200. No manual intervention needed during normal operation.
3. If the free tier (100 req/day) is exhausted, wait for midnight UTC reset or upgrade to the Pro tier ($19/mo) on `dashboard.api-football.com`.
4. To manually drain the Oban `external_api` queue and stop all API calls: `Oban.pause_queue(:external_api)`. Resume with `Oban.resume_queue(:external_api)`.

---

## Match scores are wrong or delayed

**Symptom:** A match finished but scores show nil or the wrong values in the app.

**Action:**
1. Trigger an immediate sync: `iex> Prode.Matches.MatchPoller.poll_now()`
2. Alternatively, manually enqueue the sync worker:
   ```elixir
   %{} |> Prode.Workers.FixtureSyncWorker.new() |> Oban.insert()
   ```
3. Check the Oban job results in `oban_jobs` table for any failures:
   ```sql
   SELECT id, state, errors, attempted_at FROM oban_jobs
   WHERE worker = 'Elixir.Prode.Workers.FixtureSyncWorker'
   ORDER BY attempted_at DESC LIMIT 5;
   ```
4. If a match score was manually corrected, re-enqueue `PointsCalculator` to recalculate. It is idempotent and will skip already-calculated predictions, so first reset the `calculated_at` field:
   ```sql
   UPDATE predictions SET calculated_at = NULL, points_awarded = NULL
   WHERE match_id = '<match-uuid>';
   ```
   Then:
   ```elixir
   %{"match_id" => "<match-uuid>"} |> Prode.Workers.PointsCalculator.new() |> Oban.insert()
   ```

---

## User can't sign in with Google

**Symptom:** OAuth callback returns an error or redirects to login with a flash message.

**Action:**
1. Verify `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` env vars are set correctly.
2. Check that `http://localhost:4000/auth/google/callback` (dev) or the production URL is in the **Authorized redirect URIs** in Google Cloud Console.
3. Check the application logs for the raw error from Ueberauth:
   ```
   grep "ueberauth_failure" logs/app.log
   ```
4. If the user exists with a different Google account, their `google_uid` in the database may conflict. Look up by email: `Prode.Accounts.get_user_by_email("user@example.com")`.

---

## Points were not calculated after a match

**Symptom:** Match shows `status: :finished` but predictions still have `points_awarded: nil`.

**Action:**
1. Check if a `PointsCalculator` job was created:
   ```sql
   SELECT id, state, args, errors FROM oban_jobs
   WHERE worker = 'Elixir.Prode.Workers.PointsCalculator'
     AND args->>'match_id' = '<match-uuid>'
   ORDER BY inserted_at DESC LIMIT 3;
   ```
2. If the job is in `retryable` or `discarded` state, inspect the `errors` column for the root cause.
3. To manually trigger calculation:
   ```elixir
   %{"match_id" => "<match-uuid>"} |> Prode.Workers.PointsCalculator.new() |> Oban.insert()
   ```
4. If the job ran but `snooze`d (match was not `:finished` at run time), confirm the match status in DB:
   ```sql
   SELECT id, status, home_score, away_score FROM matches WHERE id = '<match-uuid>';
   ```

---

## Notifications not being delivered

**Symptom:** Users report they're not receiving push notifications or WhatsApp messages.

**Web push:**
1. Verify VAPID keys are set: `Application.get_env(:web_push_elixir, :vapid_public_key)`.
2. Check `NotificationDispatcher` job states in Oban.
3. Subscription endpoints with HTTP 410 responses are automatically cleaned up. A user who cleared their browser will need to re-subscribe via `POST /api/v1/users/me/push-subscription`.

**WhatsApp:**
1. Verify `WHATSAPP_PHONE_NUMBER_ID` and `WHATSAPP_ACCESS_TOKEN` are set.
2. Check the Meta Business account for template approval status — unapproved templates return HTTP 400.
3. Confirm the user has `whatsapp_opted_in: true` and a non-nil `phone_number`.
4. The daily cap is 3 messages per user per day. Check sent count:
   ```sql
   SELECT count(*) FROM oban_jobs
   WHERE worker = 'Elixir.Prode.Workers.NotificationDispatcher'
     AND args->>'user_id' = '<user-uuid>'
     AND args->>'channel' = 'whatsapp'
     AND state = 'completed'
     AND attempted_at >= now() - interval '1 day';
   ```

---

## Database connection pool exhausted

**Symptom:** `[error] checkout timeout` in logs; requests start timing out.

**Action:**
1. Identify long-running queries:
   ```sql
   SELECT pid, now() - query_start AS duration, query
   FROM pg_stat_activity
   WHERE state = 'active' AND now() - query_start > interval '5 seconds'
   ORDER BY duration DESC;
   ```
2. Kill blocking queries if safe: `SELECT pg_terminate_backend(<pid>);`
3. Check the pool size in config. Default is 10; increase `POOL_SIZE` env var and restart.
4. If Oban workers are holding connections, pause a queue: `Oban.pause_queue(:scoring)`.

---

## Oban job queue backlog

**Symptom:** Jobs are accumulating; scoring or notifications are delayed.

**Quick stats:**
```sql
SELECT queue, state, count(*) FROM oban_jobs
GROUP BY queue, state ORDER BY queue, state;
```

**To drain a specific queue:**
```elixir
Oban.drain_queue(queue: :scoring)
```

**To cancel all retryable jobs for a worker:**
```elixir
Oban.cancel_all_jobs(worker: Prode.Workers.NotificationDispatcher)
```

---

## Manually seeding / re-seeding tournament data

```bash
mix run priv/repo/seeds.exs
```

The seed is idempotent — it uses `on_conflict: :nothing` so it's safe to re-run.

---

## Deploying to staging (Fly.io)

```bash
flyctl deploy
flyctl logs -a prode-staging        # tail logs
flyctl ssh console -a prode-staging # remote IEx console
```

Run migrations on deploy (automatically handled by the release config). To run manually:
```bash
flyctl ssh console -a prode-staging
/app/bin/prode eval "Prode.Release.migrate()"
```
