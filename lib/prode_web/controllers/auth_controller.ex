defmodule ProdeWeb.AuthController do
  use ProdeWeb, :controller

  plug Ueberauth

  alias Prode.Accounts
  alias ProdeWeb.UserAuth

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    attrs = %{
      email: auth.info.email,
      google_uid: auth.uid,
      display_name: auth.info.name,
      avatar_url: auth.info.image
    }

    case Accounts.authenticate_by_google(attrs) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Sesión iniciada con Google.")
        |> UserAuth.log_in_user(user)

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "No se pudo autenticar. Intenta nuevamente.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Google rechazó la autenticación.")
    |> redirect(to: ~p"/users/log-in")
  end
end
