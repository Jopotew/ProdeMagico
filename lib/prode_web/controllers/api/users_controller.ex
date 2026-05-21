defmodule ProdeWeb.Api.UsersController do
  use ProdeWeb, :controller

  alias Prode.Predictions

  def me(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      data: %{
        id: user.id,
        email: user.email,
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        phone_number: user.phone_number,
        whatsapp_opted_in: user.whatsapp_opted_in
      }
    })
  end

  def predictions(conn, _params) do
    user = conn.assigns.current_user
    preds = Predictions.list_predictions_for_user(user.id)

    json(conn, %{
      data:
        Enum.map(preds, fn p ->
          %{
            id: p.id,
            match_id: p.match_id,
            home_score: p.home_score,
            away_score: p.away_score,
            points_awarded: p.points_awarded,
            calculated_at: p.calculated_at
          }
        end)
    })
  end

  def push_subscription(conn, params) do
    user = conn.assigns.current_user

    attrs = %{
      endpoint: params["endpoint"],
      p256dh: params["p256dh"],
      auth: params["auth"]
    }

    case Prode.Notifications.upsert_push_subscription(user, attrs) do
      {:ok, _sub} -> send_resp(conn, 204, "")
      {:error, changeset} -> conn |> put_status(422) |> json(%{error: format_errors(changeset)})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
