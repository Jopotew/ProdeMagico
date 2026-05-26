defmodule ProdeWeb.TorneosLive do
  use ProdeWeb, :live_view

  import Ecto.Query, warn: false

  alias Prode.Predictions.Prediction
  alias Prode.{Repo, Tournaments}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    tournaments = Tournaments.list_active_tournaments()

    stats =
      Map.new(tournaments, fn t ->
        count =
          Repo.aggregate(
            from(p in Prediction, where: p.user_id == ^user.id),
            :count
          )

        total_pts =
          Repo.one(
            from(p in Prediction,
              where: p.user_id == ^user.id,
              select: coalesce(sum(p.points_awarded), 0)
            )
          ) || 0

        {t.id, %{predictions_made: count, points_total: total_pts}}
      end)

    {:ok,
     socket
     |> assign(:tab, :torneos)
     |> assign(:tournaments, tournaments)
     |> assign(:stats, stats)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 pb-4">
      <%= if Enum.empty?(@tournaments) do %>
        <div class="text-center py-16">
          <.icon name="hero-globe-alt" class="size-10 mx-auto mb-3 text-muted-2" />
          <p class="text-sm text-muted">No hay torneos activos.</p>
        </div>
      <% else %>
        <.section_heading>Torneos activos</.section_heading>
        <%= for tournament <- @tournaments do %>
          <.tournament_card
            tournament={tournament}
            stats={Map.get(@stats, tournament.id, %{})}
            bonus_url={~p"/torneos/#{tournament.id}/bonus"}
          />
        <% end %>
      <% end %>

      <%!-- Upcoming (not in list_active but may have status :upcoming) --%>
    </div>
    """
  end
end
