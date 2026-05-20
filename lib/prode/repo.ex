defmodule Prode.Repo do
  use Ecto.Repo,
    otp_app: :prode,
    adapter: Ecto.Adapters.Postgres
end
