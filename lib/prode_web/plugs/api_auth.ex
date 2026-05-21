defmodule ProdeWeb.Plugs.ApiAuth do
  @moduledoc """
  Extracts and validates the Bearer token from the Authorization header.
  Assigns `:current_user` if valid; halts with 401 otherwise.
  """

  import Plug.Conn

  alias Prode.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {user, _token} <- Accounts.get_user_by_session_token(token) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, ~s({"error":"unauthorized"}))
        |> halt()
    end
  end
end
