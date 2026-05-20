defmodule ProdeWeb.PageController do
  use ProdeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
