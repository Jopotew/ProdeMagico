defmodule ProdeWeb.FixtureLive do
  use ProdeWeb, :live_view

  alias Prode.Matches

  @impl true
  def mount(_params, _session, socket) do
    tournament = socket.assigns.active_tournament

    days =
      if tournament do
        matches = Matches.list_all_matches_with_teams(tournament.id)

        if connected?(socket) do
          subscribe_matches(matches)
          Phoenix.PubSub.subscribe(Prode.PubSub, "tournament:#{tournament.id}:fixtures_updated")
        end

        group_by_day(matches)
      else
        []
      end

    {:ok,
     socket
     |> assign(:tab, :fixture)
     |> assign(:days, days)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-4">
      <%= if Enum.empty?(@days) do %>
        <div class="text-center py-16 text-muted">
          <.icon name="hero-calendar" class="size-10 mx-auto mb-3 text-muted-2" />
          <p class="text-sm">No hay fixture disponible.</p>
        </div>
      <% else %>
        <%= for {date, matches} <- @days do %>
          <%!-- Day heading --%>
          <div
            id={"fixture-day-#{Date.to_iso8601(date)}"}
            phx-hook={if today?(date), do: "ScrollToToday", else: nil}
            class={[
              "px-4 py-2 bg-app-bg border-b border-divider sticky top-0 z-10",
              if(today?(date), do: "bg-brand-soft", else: "")
            ]}
          >
            <span class={["text-xs font-semibold uppercase tracking-widest",
              if(today?(date), do: "text-brand", else: "text-muted")]}>
              {format_day(date)}
            </span>
          </div>

          <%!-- Match rows --%>
          <%= for match <- matches do %>
            <.fixture_row match={match} />
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  # ── PubSub ────────────────────────────────────────────────────────────

  @impl true
  def handle_info(:fixtures_updated, socket) do
    tournament = socket.assigns.active_tournament
    matches = Matches.list_all_matches_with_teams(tournament.id)
    subscribe_matches(matches)
    {:noreply, assign(socket, :days, group_by_day(matches))}
  end

  def handle_info({:match_updated, updated_match}, socket) do
    days = Enum.map(socket.assigns.days, fn {date, matches} ->
      {date, Enum.map(matches, &maybe_update_match(&1, updated_match))}
    end)

    {:noreply, assign(socket, :days, days)}
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp subscribe_matches(matches) do
    Enum.each(matches, fn m -> Phoenix.PubSub.subscribe(Prode.PubSub, "match:#{m.id}") end)
  end

  defp maybe_update_match(%{id: id} = match, %{id: id} = updated) do
    Map.merge(match, Map.take(updated, [:status, :home_score, :away_score, :locked]))
  end

  defp maybe_update_match(match, _updated), do: match

  defp group_by_day(matches) do
    matches
    |> Enum.group_by(fn m ->
      dt_local = DateTime.add(m.kickoff_at, -3 * 3600, :second)
      DateTime.to_date(dt_local)
    end)
    |> Enum.sort_by(fn {date, _} -> Date.to_erl(date) end)
  end

  defp today?(date), do: date == Date.utc_today()

  defp format_day(date) do
    days = ~w(lunes martes miércoles jueves viernes sábado domingo)
    day_name = Enum.at(days, Date.day_of_week(date) - 1, "")
    month_names = ~w(ene feb mar abr may jun jul ago sep oct nov dic)
    month_name = Enum.at(month_names, date.month - 1, "")

    if today?(date) do
      "Hoy · #{day_name} #{date.day} #{month_name}"
    else
      "#{String.capitalize(day_name)} #{date.day} #{month_name}"
    end
  end
end
