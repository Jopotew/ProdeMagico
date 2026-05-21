defmodule Prode.Workers.NotificationDispatcher do
  @moduledoc """
  Sends a push notification and/or WhatsApp message to a single user for a match event.
  Enforces caps: max 1 push per user per match, max 3 WhatsApp per user per day.
  Args: %{"user_id" => id, "match_id" => id, "kind" => "match_start"|"match_end"}
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3,
    unique: [fields: [:args], period: 300]

  require Logger

  alias Prode.Accounts
  alias Prode.Matches
  alias Prode.Notifications
  alias Prode.Notifications.PushSubscription

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "match_id" => match_id, "kind" => kind}}) do
    user = Accounts.get_user!(user_id)
    match = Matches.get_match!(match_id) |> Prode.Repo.preload([:home_team, :away_team])

    payload = build_payload(kind, match)

    subscriptions = Notifications.list_push_subscriptions(user)

    Enum.each(subscriptions, fn sub ->
      send_push(sub, payload)
    end)

    if user.whatsapp_opted_in and not is_nil(user.phone_number) and Notifications.under_whatsapp_cap?(user) do
      send_whatsapp(user, kind, match)
    end

    :ok
  end

  defp build_payload("match_start", match) do
    %{
      title: "¡Partido comenzando!",
      body: "#{match.home_team.name} vs #{match.away_team.name} acaba de comenzar.",
      data: %{match_id: match.id}
    }
  end

  defp build_payload("match_end", match) do
    %{
      title: "Partido terminado",
      body: "#{match.home_team.name} #{match.home_score} - #{match.away_score} #{match.away_team.name}",
      data: %{match_id: match.id}
    }
  end

  defp send_push(%PushSubscription{} = sub, payload) do
    subscription =
      Jason.encode!(%{
        "endpoint" => sub.endpoint,
        "keys" => %{"p256dh" => sub.p256dh, "auth" => sub.auth}
      })

    case WebPushElixir.send_notification(subscription, Jason.encode!(payload)) do
      {:ok, _response} ->
        :ok

      {:error, :expired} ->
        Notifications.delete_push_subscription(sub.endpoint)

      {:error, reason} ->
        Logger.warning("Push send failed for #{sub.endpoint}: #{inspect(reason)}")
    end
  end

  defp send_whatsapp(user, kind, match) do
    template = whatsapp_template(kind)
    client = Application.get_env(:prode, :whatsapp_client, Prode.External.WhatsApp)

    case client.send_template(user.phone_number, template, whatsapp_params(kind, match)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("WhatsApp send failed for user #{user.id}: #{inspect(reason)}")
    end
  end

  defp whatsapp_template("match_start"), do: "match_starting"
  defp whatsapp_template("match_end"), do: "match_finished_with_points"

  defp whatsapp_params("match_start", match), do: [match.home_team.name, match.away_team.name]
  defp whatsapp_params("match_end", match), do: ["#{match.home_score}", "#{match.away_score}"]
end
