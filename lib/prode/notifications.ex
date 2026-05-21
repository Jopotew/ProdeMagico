defmodule Prode.Notifications do
  @moduledoc """
  Context for managing push subscriptions and dispatching notifications.
  Notification dispatch (push + WhatsApp) goes through Oban workers.
  """

  import Ecto.Query, warn: false

  alias Prode.Accounts.User
  alias Prode.Matches.Match
  alias Prode.Notifications.PushSubscription
  alias Prode.Predictions
  alias Prode.Repo

  # ── Push subscription management ────────────────────────────────────────────

  @doc "Registers or updates a push subscription for a user."
  def upsert_push_subscription(%User{} = user, attrs) do
    %PushSubscription{}
    |> PushSubscription.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert(
      on_conflict: {:replace, [:p256dh, :auth, :updated_at]},
      conflict_target: :endpoint,
      returning: true
    )
  end

  @doc "Removes a push subscription by endpoint."
  def delete_push_subscription(endpoint) when is_binary(endpoint) do
    Repo.delete_all(from s in PushSubscription, where: s.endpoint == ^endpoint)
    :ok
  end

  @doc "Returns all push subscriptions for a user."
  def list_push_subscriptions(%User{id: user_id}) do
    Repo.all(from s in PushSubscription, where: s.user_id == ^user_id)
  end

  # ── Notification triggers ────────────────────────────────────────────────────

  @doc "Enqueues match-start notification jobs for all users who predicted this match."
  def notify_match_start(%Match{} = match) do
    user_ids = Predictions.user_ids_with_predictions_for_match(match.id)

    Enum.each(user_ids, fn uid ->
      %{user_id: uid, match_id: match.id, kind: "match_start"}
      |> Prode.Workers.NotificationDispatcher.new()
      |> Oban.insert()
    end)
  end

  @doc "Enqueues match-end notification jobs for all users who predicted this match."
  def notify_match_end(%Match{} = match) do
    user_ids = Predictions.user_ids_with_predictions_for_match(match.id)

    Enum.each(user_ids, fn uid ->
      %{user_id: uid, match_id: match.id, kind: "match_end"}
      |> Prode.Workers.NotificationDispatcher.new()
      |> Oban.insert()
    end)
  end

  # ── WhatsApp daily cap ───────────────────────────────────────────────────────

  @whatsapp_daily_cap 3

  @doc "Returns true if the user has not yet hit their WhatsApp daily cap."
  def under_whatsapp_cap?(%User{id: user_id}) do
    today_start = DateTime.utc_now() |> DateTime.truncate(:second) |> Map.put(:hour, 0) |> Map.put(:minute, 0) |> Map.put(:second, 0)

    sent_today =
      Repo.one(
        from j in Oban.Job,
          where: j.worker == "Prode.Workers.NotificationDispatcher",
          where: fragment("?->>'user_id' = ?", j.args, ^user_id),
          where: fragment("?->>'channel' = ?", j.args, "whatsapp"),
          where: j.state == "completed",
          where: j.attempted_at >= ^today_start,
          select: count(j.id)
      )

    sent_today < @whatsapp_daily_cap
  end
end
