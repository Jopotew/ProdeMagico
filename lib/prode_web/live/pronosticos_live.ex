defmodule ProdeWeb.PronosticosLive do
  use ProdeWeb, :live_view

  alias Prode.{Matches, Predictions}
  alias ProdeWeb.UIComponents

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    tournament = socket.assigns.active_tournament

    {rounds, selected_round, matches, predictions} =
      if tournament do
        rounds = Matches.list_rounds_for_tournament(tournament.id)
        first_round = List.first(rounds)
        matches = if first_round, do: Matches.list_matches_by_round(tournament.id, first_round), else: []
        match_ids = Enum.map(matches, & &1.id)
        preds = Predictions.list_predictions_map_for_matches(user.id, match_ids)

        if connected?(socket) do
          subscribe_matches(matches)
          Phoenix.PubSub.subscribe(Prode.PubSub, "tournament:#{tournament.id}:fixtures_updated")
        end

        {rounds, first_round, matches, preds}
      else
        {[], nil, [], %{}}
      end

    {:ok,
     socket
     |> assign(:tab, :pronosticos)
     |> assign(:rounds, rounds)
     |> assign(:selected_round, selected_round)
     |> assign(:matches, matches)
     |> assign(:predictions, predictions)
     |> assign(:sheet_match, nil)
     |> assign(:sheet_home, 0)
     |> assign(:sheet_away, 0)
     |> assign(:popular, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-4">
      <%!-- Round selector --%>
      <%= if @selected_round do %>
        <div class="mx-4 mt-3 bg-white rounded-[14px] shadow-card flex items-center h-14 overflow-hidden">
          <button
            phx-click="prev_round"
            disabled={round_index(@rounds, @selected_round) == 0}
            class={[
              "w-12 h-full flex items-center justify-center transition-colors",
              if(round_index(@rounds, @selected_round) == 0,
                do: "text-muted-2 cursor-not-allowed",
                else: "text-brand hover:bg-brand-soft"
              )
            ]}
            aria-label="Ronda anterior"
          >
            <.icon name="hero-chevron-left" class="size-5" />
          </button>

          <div class="flex-1 border-x border-divider h-full flex items-center justify-center gap-2">
            <.icon name="hero-calendar" class="size-3.5 text-muted" />
            <span class="text-sm font-semibold text-ink text-center leading-tight">
              {format_round(@selected_round)}
            </span>
          </div>

          <button
            phx-click="next_round"
            disabled={round_index(@rounds, @selected_round) >= length(@rounds) - 1}
            class={[
              "w-12 h-full flex items-center justify-center transition-colors",
              if(round_index(@rounds, @selected_round) >= length(@rounds) - 1,
                do: "text-muted-2 cursor-not-allowed",
                else: "text-brand hover:bg-brand-soft"
              )
            ]}
            aria-label="Ronda siguiente"
          >
            <.icon name="hero-chevron-right" class="size-5" />
          </button>
        </div>

        <%!-- Progress bar --%>
        <.prediction_progress
          done={Enum.count(@matches, fn m -> Map.has_key?(@predictions, m.id) end)}
          total={length(@matches)}
        />
      <% end %>

      <%!-- Match list --%>
      <div class="px-4">
        <%= if Enum.empty?(@matches) do %>
          <div class="text-center py-16 text-muted">
            <.icon name="hero-calendar" class="size-10 mx-auto mb-3 text-muted-2" />
            <p class="text-sm">No hay partidos disponibles.</p>
          </div>
        <% else %>
          <.section_heading>{format_round(@selected_round)}</.section_heading>
          <%= for match <- @matches do %>
            <.match_card
              match={match}
              prediction={Map.get(@predictions, match.id)}
              on_click={UIComponents.open_sheet_js(match.id)}
            />
          <% end %>
        <% end %>
      </div>

      <%!-- Prediction sheet backdrop --%>
      <div
        id="sheet-backdrop"
        class="fixed inset-0 bg-black/40 z-40"
        style="display: none"
        phx-click={UIComponents.close_sheet_js()}
        aria-hidden="true"
      />

      <%!-- Prediction sheet --%>
      <div
        id="prediction-sheet"
        class="fixed bottom-0 left-0 right-0 max-w-md mx-auto bg-white rounded-t-3xl z-50 shadow-sheet pb-safe"
        style="display: none"
        role="dialog"
        aria-modal="true"
        aria-label="Ingresar pronóstico"
      >
        <%= if @sheet_match do %>
          <%!-- Drag handle --%>
          <div class="flex justify-center pt-3 pb-1">
            <div class="w-10 h-1 rounded-full bg-muted-2" />
          </div>

          <%!-- Match info --%>
          <div class="px-5 pt-2 pb-3 border-b border-divider">
            <p class="text-center text-sm font-semibold text-ink">
              {@sheet_match.home_team.code} vs {@sheet_match.away_team.code}
            </p>
            <p class="text-center text-xs text-muted mt-0.5">
              {UIComponents.format_kickoff(@sheet_match.kickoff_at)}
              · {format_round(@sheet_match.round)}
            </p>
          </div>

          <%!-- Popular predictions --%>
          <%= if length(@popular) > 0 do %>
            <div class="px-5 pt-3 pb-2">
              <p class="text-[11px] text-muted font-semibold uppercase tracking-wide mb-2">
                Predicciones populares
              </p>
              <%= for pop <- @popular do %>
                <div class="flex items-center gap-2 mb-1.5">
                  <span class="text-xs font-semibold text-ink-2 w-8 text-right tabular-nums">
                    {pop.home_score}–{pop.away_score}
                  </span>
                  <div class="flex-1 h-1.5 bg-divider rounded-full overflow-hidden">
                    <div class="h-full bg-brand rounded-full" style={"width: #{pop.pct}%"} />
                  </div>
                  <span class="text-[11px] text-muted w-7 tabular-nums">{pop.pct}%</span>
                </div>
              <% end %>
            </div>
          <% end %>

          <%!-- Score steppers --%>
          <div class="px-5 py-5">
            <p class="text-[11px] text-muted font-semibold uppercase tracking-wide text-center mb-4">
              Tu pronóstico
            </p>
            <div class="flex items-center justify-center gap-8">
              <.score_stepper
                value={@sheet_home}
                team_name={@sheet_match.home_team.code}
                inc_event="inc_home"
                dec_event="dec_home"
              />
              <span class="font-score text-3xl text-muted-2 mt-2">—</span>
              <.score_stepper
                value={@sheet_away}
                team_name={@sheet_match.away_team.code}
                inc_event="inc_away"
                dec_event="dec_away"
              />
            </div>
          </div>

          <%!-- Submit button --%>
          <div class="px-5 pb-5">
            <button
              phx-click="submit_prediction"
              class="w-full py-3.5 bg-brand text-white font-semibold rounded-xl text-sm active:scale-[0.98] transition-transform phx-submit-loading:opacity-60"
            >
              Guardar pronóstico
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ── Events ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("prev_round", _params, socket) do
    navigate_round(socket, -1)
  end

  def handle_event("next_round", _params, socket) do
    navigate_round(socket, +1)
  end

  def handle_event("open_sheet", %{"match_id" => match_id}, socket) do
    match = Enum.find(socket.assigns.matches, &(&1.id == match_id))

    if match && !match.locked && match.status not in [:finished] do
      pred = Map.get(socket.assigns.predictions, match_id)
      popular = Predictions.popular_predictions_for_match(match_id)

      {:noreply,
       socket
       |> assign(:sheet_match, match)
       |> assign(:sheet_home, (pred && pred.home_score) || 0)
       |> assign(:sheet_away, (pred && pred.away_score) || 0)
       |> assign(:popular, popular)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_sheet", _params, socket) do
    {:noreply, assign(socket, :sheet_match, nil)}
  end

  def handle_event("inc_home", _params, socket),
    do: {:noreply, assign(socket, :sheet_home, min(socket.assigns.sheet_home + 1, 20))}

  def handle_event("dec_home", _params, socket),
    do: {:noreply, assign(socket, :sheet_home, max(socket.assigns.sheet_home - 1, 0))}

  def handle_event("inc_away", _params, socket),
    do: {:noreply, assign(socket, :sheet_away, min(socket.assigns.sheet_away + 1, 20))}

  def handle_event("dec_away", _params, socket),
    do: {:noreply, assign(socket, :sheet_away, max(socket.assigns.sheet_away - 1, 0))}

  def handle_event("submit_prediction", _params, socket) do
    user = socket.assigns.current_scope.user
    match = socket.assigns.sheet_match

    if match do
      attrs = %{
        user_id: user.id,
        match_id: match.id,
        home_score: socket.assigns.sheet_home,
        away_score: socket.assigns.sheet_away
      }

      case Predictions.upsert_prediction(attrs) do
        {:ok, pred} ->
          predictions = Map.put(socket.assigns.predictions, match.id, pred)

          {:noreply,
           socket
           |> assign(:predictions, predictions)
           |> assign(:sheet_match, nil)
           |> push_event("close-sheet", %{})
           |> put_flash(:info, "¡Pronóstico guardado!")}

        {:error, :match_locked} ->
          {:noreply,
           socket
           |> assign(:sheet_match, nil)
           |> push_event("close-sheet", %{})
           |> put_flash(:error, "El partido ya no acepta pronósticos.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "No se pudo guardar el pronóstico.")}
      end
    else
      {:noreply, socket}
    end
  end

  # ── PubSub ────────────────────────────────────────────────────────────

  @impl true
  def handle_info(:fixtures_updated, socket) do
    user = socket.assigns.current_scope.user
    tournament = socket.assigns.active_tournament
    rounds = Matches.list_rounds_for_tournament(tournament.id)
    selected_round = socket.assigns.selected_round || List.first(rounds)
    matches = if selected_round, do: Matches.list_matches_by_round(tournament.id, selected_round), else: []
    match_ids = Enum.map(matches, & &1.id)
    predictions = Predictions.list_predictions_map_for_matches(user.id, match_ids)
    subscribe_matches(matches)

    {:noreply,
     socket
     |> assign(:rounds, rounds)
     |> assign(:selected_round, selected_round)
     |> assign(:matches, matches)
     |> assign(:predictions, predictions)}
  end

  def handle_info({:match_updated, updated_match}, socket) do
    matches =
      Enum.map(socket.assigns.matches, fn m ->
        if m.id == updated_match.id, do: Map.merge(m, Map.take(updated_match, [:status, :home_score, :away_score, :locked])), else: m
      end)

    sheet_match =
      cond do
        is_nil(socket.assigns.sheet_match) ->
          nil

        socket.assigns.sheet_match.id == updated_match.id && updated_match.locked ->
          nil

        socket.assigns.sheet_match.id == updated_match.id ->
          Map.merge(socket.assigns.sheet_match, Map.take(updated_match, [:status, :locked]))

        true ->
          socket.assigns.sheet_match
      end

    {:noreply, socket |> assign(:matches, matches) |> assign(:sheet_match, sheet_match)}
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp navigate_round(socket, direction) do
    rounds = socket.assigns.rounds
    current = socket.assigns.selected_round
    idx = Enum.find_index(rounds, &(&1 == current)) || 0
    new_idx = max(0, min(idx + direction, length(rounds) - 1))
    new_round = Enum.at(rounds, new_idx)

    if new_round != current, do: load_round(socket, new_round), else: {:noreply, socket}
  end

  defp load_round(socket, round) do
    user = socket.assigns.current_scope.user
    tournament = socket.assigns.active_tournament

    Enum.each(socket.assigns.matches, fn m ->
      Phoenix.PubSub.unsubscribe(Prode.PubSub, "match:#{m.id}")
    end)

    matches = Matches.list_matches_by_round(tournament.id, round)
    match_ids = Enum.map(matches, & &1.id)
    predictions = Predictions.list_predictions_map_for_matches(user.id, match_ids)

    if connected?(socket), do: subscribe_matches(matches)

    {:noreply,
     socket
     |> assign(:selected_round, round)
     |> assign(:matches, matches)
     |> assign(:predictions, predictions)
     |> assign(:sheet_match, nil)}
  end

  defp subscribe_matches(matches) do
    Enum.each(matches, fn m -> Phoenix.PubSub.subscribe(Prode.PubSub, "match:#{m.id}") end)
  end

  defp round_index(rounds, round), do: Enum.find_index(rounds, &(&1 == round)) || 0

  defp format_round(nil), do: ""

  defp format_round(round) do
    round
    |> String.replace("Group Stage", "Fase de Grupos")
    |> String.replace("Round of 16", "Octavos de Final")
    |> String.replace("Quarter-finals", "Cuartos de Final")
    |> String.replace("Semi-finals", "Semifinales")
    |> String.replace("3rd Place Final", "3er y 4to Puesto")
    |> String.replace("Final", "Final")
    |> String.replace(" - ", " · ")
  end
end
