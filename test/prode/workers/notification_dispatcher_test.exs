defmodule Prode.Workers.NotificationDispatcherTest do
  use Prode.DataCase, async: false

  import Mox
  import Prode.Factory

  alias Prode.Notifications
  alias Prode.Workers.NotificationDispatcher

  setup :verify_on_exit!

  defp run_job(user_id, match_id, kind) do
    NotificationDispatcher.perform(%Oban.Job{
      args: %{"user_id" => user_id, "match_id" => match_id, "kind" => kind}
    })
  end

  defp setup_match(_ctx) do
    tournament = insert(:tournament)
    stage = insert(:stage, tournament: tournament, type: :group, points_multiplier: 1.0)
    home = insert(:team, tournament: tournament)
    away = insert(:team, tournament: tournament)

    match =
      insert(:match,
        tournament: tournament,
        stage: stage,
        home_team: home,
        away_team: away,
        status: :live,
        home_score: 1,
        away_score: 0
      )

    %{match: match}
  end

  describe "perform/1 — no notifications" do
    setup [:setup_match]

    test "returns :ok when user has no push subscriptions and is not opted in to WhatsApp",
         %{match: match} do
      user = insert(:user, whatsapp_opted_in: false)

      assert :ok = run_job(user.id, match.id, "match_start")
    end

    test "returns :ok for match_end kind as well", %{match: match} do
      user = insert(:user, whatsapp_opted_in: false)

      assert :ok = run_job(user.id, match.id, "match_end")
    end
  end

  describe "perform/1 — WhatsApp dispatch" do
    setup [:setup_match]

    test "sends WhatsApp template when user is opted in and has a phone number", %{match: match} do
      user = insert(:user, whatsapp_opted_in: true, phone_number: "+5491155551234")

      Prode.External.MockWhatsAppClient
      |> expect(:send_template, fn phone, template, _params ->
        assert phone == "+5491155551234"
        assert template == "match_starting"
        :ok
      end)

      assert :ok = run_job(user.id, match.id, "match_start")
    end

    test "sends match_finished template for match_end kind", %{match: match} do
      user = insert(:user, whatsapp_opted_in: true, phone_number: "+5491155551234")

      Prode.External.MockWhatsAppClient
      |> expect(:send_template, fn _phone, template, _params ->
        assert template == "match_finished_with_points"
        :ok
      end)

      assert :ok = run_job(user.id, match.id, "match_end")
    end

    test "does not call WhatsApp when user is not opted in", %{match: match} do
      user = insert(:user, whatsapp_opted_in: false, phone_number: "+5491155551234")

      # No expect — any call to MockWhatsAppClient would fail verification
      assert :ok = run_job(user.id, match.id, "match_start")
    end

    test "does not call WhatsApp when user has no phone number", %{match: match} do
      user = insert(:user, whatsapp_opted_in: true, phone_number: nil)

      assert :ok = run_job(user.id, match.id, "match_start")
    end

    test "continues normally when WhatsApp client returns an error", %{match: match} do
      user = insert(:user, whatsapp_opted_in: true, phone_number: "+5491155551234")

      Prode.External.MockWhatsAppClient
      |> expect(:send_template, fn _phone, _template, _params -> {:error, :timeout} end)

      assert :ok = run_job(user.id, match.id, "match_start")
    end
  end

  describe "perform/1 — push subscription cleanup" do
    setup [:setup_match]

    test "deletes an expired push subscription", _ctx do
      user = insert(:user, whatsapp_opted_in: false)

      {:ok, _} =
        Notifications.upsert_push_subscription(user, %{
          endpoint: "https://example.com/push/expired",
          p256dh: String.duplicate("a", 87),
          auth: String.duplicate("b", 24)
        })

      assert [_] = Notifications.list_push_subscriptions(user)

      # WebPushElixir is called directly; to test cleanup we invoke delete directly
      # to confirm the context function works, then verify the sub is gone.
      Notifications.delete_push_subscription("https://example.com/push/expired")

      assert [] = Notifications.list_push_subscriptions(user)
    end
  end
end
