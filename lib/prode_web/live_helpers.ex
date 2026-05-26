defmodule ProdeWeb.LiveHelpers do
  @moduledoc """
  on_mount hook that assigns shared data every app LiveView needs:
  active_tournament, user_groups, and an initial tab value.
  """

  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    tournament = Prode.Tournaments.get_current_tournament()

    user_groups =
      case socket.assigns[:current_scope] do
        %{user: user} when not is_nil(user) -> Prode.Groups.list_user_groups(user)
        _ -> []
      end

    socket =
      socket
      |> assign(:active_tournament, tournament)
      |> assign(:user_groups, user_groups)
      |> assign(:tab, nil)

    {:cont, socket}
  end
end
