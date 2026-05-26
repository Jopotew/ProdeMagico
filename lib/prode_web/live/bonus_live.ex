defmodule ProdeWeb.BonusLive do
  use ProdeWeb, :live_view

  alias Prode.{Predictions, Tournaments}

  @groups ~w(A B C D E F G H)

  @impl true
  def mount(%{"tournament_id" => tournament_id}, _session, socket) do
    user = socket.assigns.current_scope.user
    tournament = Tournaments.get_tournament!(tournament_id)
    teams = Tournaments.list_teams(tournament_id)

    teams_by_group =
      teams
      |> Enum.filter(& &1.group)
      |> Enum.group_by(& &1.group)

    bonus_map = Predictions.list_bonus_predictions_map(user.id, tournament_id)
    locked = bonus_predictions_locked?(tournament)

    if connected?(socket) && !locked, do: schedule_tick()

    top_scorer_name =
      case Map.get(bonus_map, :top_scorer) do
        %{payload: %{"player_name" => name}} -> name
        _ -> ""
      end

    {:ok,
     socket
     |> assign(:tab, :torneos)
     |> assign(:tournament, tournament)
     |> assign(:groups, @groups)
     |> assign(:teams_by_group, teams_by_group)
     |> assign(:bonus_map, bonus_map)
     |> assign(:locked, locked)
     |> assign(:saved_groups, MapSet.new())
     |> assign(:top_scorer_input, top_scorer_name)
     |> assign(:top_scorer_saved, false)
     |> assign(:countdown, countdown_text(tournament))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-4">
      <div class="px-4 pt-3 pb-2 flex items-center gap-2">
        <.link navigate={~p"/torneos"} class="text-brand">
          <.icon name="hero-arrow-left" class="size-5" />
        </.link>
        <h1 class="font-semibold text-ink text-base">Pronósticos bonus</h1>
      </div>

      <%= cond do %>
        <% @locked -> %>
          <div class="mx-4 mb-4 bg-orange-50 border border-orange-200 rounded-xl px-4 py-3 flex items-center gap-2">
            <.icon name="hero-lock-closed" class="size-4 text-orange-500 flex-shrink-0" />
            <p class="text-xs text-orange-700">Los bonus se bloquearon al inicio del torneo.</p>
          </div>
        <% @countdown -> %>
          <div class="mx-4 mb-4 bg-blue-50 border border-blue-200 rounded-xl px-4 py-3 flex items-center gap-2">
            <.icon name="hero-clock" class="size-4 text-blue-500 flex-shrink-0" />
            <p class="text-xs text-blue-700">Se bloquean en <span class="font-semibold tabular-nums">{@countdown}</span></p>
          </div>
        <% true -> %>
      <% end %>

      <.section_heading class="px-4">Campeón de grupo</.section_heading>
      <p class="px-4 text-xs text-muted mb-3">Seleccioná el equipo que pasará primero en cada grupo.</p>

      <div class="mx-4 bg-white rounded-[14px] overflow-hidden divide-y divide-divider">
        <%= for group <- @groups do %>
          <% teams = Map.get(@teams_by_group, group, []) %>
          <% saved = group in @saved_groups %>
          <% current_id = group_winner_team_id(@bonus_map, group) %>
          <div class="px-4 py-3">
            <div class="flex items-center justify-between gap-3">
              <span class="text-sm font-semibold text-ink w-6">
                {group}
              </span>
              <%= if @locked or Enum.empty?(teams) do %>
                <span class="flex-1 text-sm text-muted truncate">
                  <%= if current_id do %>
                    {team_name(teams, current_id)}
                  <% else %>
                    —
                  <% end %>
                </span>
              <% else %>
                <select
                  id={"group-winner-#{group}"}
                  name={"group_winner_#{group}"}
                  phx-change="pick_group_winner"
                  phx-value-group={group}
                  class="flex-1 text-sm border border-divider rounded-lg px-3 py-1.5 focus:outline-none focus:border-brand bg-white text-ink"
                >
                  <option value="">Elegir equipo…</option>
                  <%= for team <- teams do %>
                    <option value={team.api_football_id || team.id} selected={current_id && to_string(current_id) == to_string(team.api_football_id || team.id)}>
                      {team.code} — {team.name}
                    </option>
                  <% end %>
                </select>
                <%= if saved do %>
                  <.icon name="hero-check-circle" class="size-4 text-live flex-shrink-0" />
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <.section_heading class="px-4 mt-6">Goleador del torneo</.section_heading>
      <p class="px-4 text-xs text-muted mb-3">Escribí el nombre del jugador que crees que será el máximo goleador.</p>

      <div class="mx-4 bg-white rounded-[14px] overflow-hidden">
        <div class="px-4 py-3">
          <%= if @locked do %>
            <span class="text-sm text-muted">
              <%= if @top_scorer_input != "" do %>
                {@top_scorer_input}
              <% else %>
                —
              <% end %>
            </span>
          <% else %>
            <form phx-submit="save_top_scorer" class="flex items-center gap-2">
              <input
                id="top-scorer-input"
                name="player_name"
                type="text"
                value={@top_scorer_input}
                placeholder="Ej: Lionel Messi"
                phx-change="update_top_scorer_input"
                class="flex-1 text-sm border border-divider rounded-lg px-3 py-1.5 focus:outline-none focus:border-brand bg-white text-ink"
              />
              <button
                type="submit"
                class="text-sm font-medium text-white bg-brand rounded-lg px-3 py-1.5 flex-shrink-0"
              >
                Guardar
              </button>
              <%= if @top_scorer_saved do %>
                <.icon name="hero-check-circle" class="size-4 text-live flex-shrink-0" />
              <% end %>
            </form>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("pick_group_winner", %{"group" => _group, "value" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("pick_group_winner", %{"group" => group, "value" => team_id_str}, socket) do
    if socket.assigns.locked do
      {:noreply, put_flash(socket, :error, "Los bonus están bloqueados.")}
    else
      user = socket.assigns.current_scope.user
      team_id = String.to_integer(team_id_str)

      attrs = %{
        user_id: user.id,
        tournament_id: socket.assigns.tournament.id,
        kind: :group_winner,
        payload: %{"group" => group, "team_id" => team_id}
      }

      case Predictions.submit_bonus_prediction(attrs) do
        {:ok, bp} ->
          {:noreply,
           socket
           |> update(:saved_groups, &MapSet.put(&1, group))
           |> update(:bonus_map, &Map.put(&1, {:group_winner, group}, bp))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "No se pudo guardar el pronóstico.")}
      end
    end
  end

  def handle_event("update_top_scorer_input", %{"player_name" => name}, socket) do
    {:noreply, assign(socket, :top_scorer_input, name)}
  end

  def handle_event("save_top_scorer", %{"player_name" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("save_top_scorer", %{"player_name" => name}, socket) do
    if socket.assigns.locked do
      {:noreply, put_flash(socket, :error, "Los bonus están bloqueados.")}
    else
      user = socket.assigns.current_scope.user

      attrs = %{
        user_id: user.id,
        tournament_id: socket.assigns.tournament.id,
        kind: :top_scorer,
        payload: %{"player_name" => String.trim(name)}
      }

      case Predictions.submit_bonus_prediction(attrs) do
        {:ok, bp} ->
          {:noreply,
           socket
           |> assign(:top_scorer_saved, true)
           |> assign(:top_scorer_input, String.trim(name))
           |> update(:bonus_map, &Map.put(&1, :top_scorer, bp))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "No se pudo guardar el pronóstico.")}
      end
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    tournament = socket.assigns.tournament
    locked = bonus_predictions_locked?(tournament)

    if locked do
      {:noreply, socket |> assign(:locked, true) |> assign(:countdown, nil)}
    else
      schedule_tick()
      {:noreply, assign(socket, :countdown, countdown_text(tournament))}
    end
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, 1_000)

  defp bonus_predictions_locked?(%{bonus_predictions_lock_at: nil}), do: false

  defp bonus_predictions_locked?(%{bonus_predictions_lock_at: lock_at}),
    do: DateTime.after?(DateTime.utc_now(), lock_at)

  defp countdown_text(%{bonus_predictions_lock_at: nil}), do: nil

  defp countdown_text(%{bonus_predictions_lock_at: lock_at}) do
    diff = DateTime.diff(lock_at, DateTime.utc_now())

    if diff <= 0 do
      nil
    else
      days = div(diff, 86_400)
      hours = rem(diff, 86_400) |> div(3_600)
      minutes = rem(diff, 3_600) |> div(60)
      seconds = rem(diff, 60)

      cond do
        days > 0 -> "#{days}d #{hours}h #{minutes}m"
        hours > 0 -> "#{hours}h #{minutes}m #{seconds}s"
        true -> "#{minutes}m #{seconds}s"
      end
    end
  end

  defp group_winner_team_id(bonus_map, group) do
    case Map.get(bonus_map, {:group_winner, group}) do
      %{payload: %{"team_id" => team_id}} -> team_id
      _ -> nil
    end
  end

  defp team_name(teams, team_id) do
    team_id_str = to_string(team_id)

    Enum.find_value(teams, "—", fn t ->
      if to_string(t.api_football_id || t.id) == team_id_str, do: t.name
    end)
  end
end
