defmodule ProdeWeb.UIComponents do
  @moduledoc """
  Reusable UI components for the Prode mobile app.
  All components follow the Phoenix function component convention.
  """

  use Phoenix.Component
  alias Phoenix.LiveView.JS

  # ── Formatting helpers ───────────────────────────────────────────────

  @doc false
  def format_kickoff(nil), do: ""

  def format_kickoff(%DateTime{} = dt) do
    # Argentina is UTC-3 with no DST
    local = DateTime.add(dt, -3 * 3600, :second)
    Calendar.strftime(local, "%-d/%-m %H:%M")
  end

  @doc false
  def flag_emoji(code) when is_binary(code) do
    flags = %{
      "ARG" => "🇦🇷", "BRA" => "🇧🇷", "URU" => "🇺🇾", "COL" => "🇨🇴",
      "CHI" => "🇨🇱", "PER" => "🇵🇪", "VEN" => "🇻🇪", "ECU" => "🇪🇨",
      "PAR" => "🇵🇾", "BOL" => "🇧🇴",
      "GER" => "🇩🇪", "FRA" => "🇫🇷", "ESP" => "🇪🇸", "ENG" => "🏴󠁧󠁢󠁥󠁮󠁧󠁿",
      "POR" => "🇵🇹", "ITA" => "🇮🇹", "BEL" => "🇧🇪", "NED" => "🇳🇱",
      "CRO" => "🇭🇷", "SUI" => "🇨🇭", "DEN" => "🇩🇰", "POL" => "🇵🇱",
      "SRB" => "🇷🇸", "AUT" => "🇦🇹", "UKR" => "🇺🇦", "TUR" => "🇹🇷",
      "SCO" => "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "WAL" => "🏴󠁧󠁢󠁷󠁬󠁳󠁿", "GRE" => "🇬🇷", "ROU" => "🇷🇴",
      "USA" => "🇺🇸", "MEX" => "🇲🇽", "CAN" => "🇨🇦", "CRC" => "🇨🇷",
      "HON" => "🇭🇳", "PAN" => "🇵🇦", "JAM" => "🇯🇲",
      "JPN" => "🇯🇵", "KOR" => "🇰🇷", "AUS" => "🇦🇺", "IRN" => "🇮🇷",
      "SAU" => "🇸🇦", "QAT" => "🇶🇦", "CHN" => "🇨🇳", "MOR" => "🇲🇦",
      "MAR" => "🇲🇦", "SEN" => "🇸🇳", "EGY" => "🇪🇬", "NGA" => "🇳🇬",
      "CMR" => "🇨🇲", "GHA" => "🇬🇭"
    }

    Map.get(flags, String.upcase(code), "🏳️")
  end

  def flag_emoji(_), do: "🏳️"

  # ── Section heading ──────────────────────────────────────────────────

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def section_heading(assigns) do
    ~H"""
    <h2 class={["font-heading text-[15px] tracking-widest uppercase text-ink mx-1 mb-3 mt-4", @class]}>
      {render_slot(@inner_block)}
    </h2>
    """
  end

  # ── Match card ───────────────────────────────────────────────────────

  attr :match, :map, required: true
  attr :prediction, :map, default: nil
  attr :on_click, :any, default: nil

  def match_card(assigns) do
    assigns =
      assign(assigns,
        clickable: assigns.match.status == :scheduled and not assigns.match.locked,
        home_flag: flag_emoji(assigns.match.home_team.code),
        away_flag: flag_emoji(assigns.match.away_team.code)
      )

    ~H"""
    <div
      class={[
        "bg-white rounded-[14px] shadow-card px-4 py-3 mb-3 select-none",
        if(@clickable, do: "cursor-pointer active:scale-[0.99] transition-transform", else: ""),
        if(saved?(@prediction) and @match.status == :scheduled,
          do: "ring-1 ring-live",
          else: ""
        )
      ]}
      phx-click={@clickable && @on_click}
      role={@clickable && "button"}
      tabindex={@clickable && "0"}
      aria-label={@clickable && "Pronosticar #{@match.home_team.code} vs #{@match.away_team.code}"}
    >
      <%!-- Teams row --%>
      <div class="flex items-center gap-2">
        <%!-- Home team --%>
        <div class="flex-1 flex items-center gap-1.5 min-w-0">
          <span class="text-xl leading-none">{@home_flag}</span>
          <span class="font-heading text-[13px] tracking-wide text-ink truncate">
            {@match.home_team.code}
          </span>
        </div>

        <%!-- Score cells --%>
        <div
          class="flex items-center gap-1.5"
          role="group"
          aria-label={score_group_label(@match, @prediction)}
        >
          <.score_cell
            value={home_display(@match, @prediction)}
            variant={cell_variant(@match, @prediction, :home)}
          />
          <span class="text-muted-2 font-bold text-sm" aria-hidden="true">—</span>
          <.score_cell
            value={away_display(@match, @prediction)}
            variant={cell_variant(@match, @prediction, :away)}
          />
        </div>

        <%!-- Away team --%>
        <div class="flex-1 flex items-center gap-1.5 min-w-0 justify-end">
          <span class="font-heading text-[13px] tracking-wide text-ink truncate">
            {@match.away_team.code}
          </span>
          <span class="text-xl leading-none">{@away_flag}</span>
        </div>
      </div>

      <%!-- Meta row --%>
      <div class="flex items-center justify-between mt-2">
        <span class="text-[11px] text-muted">{format_kickoff(@match.kickoff_at)}</span>
        <.match_badge match={@match} prediction={@prediction} />
      </div>

      <%!-- Prediction row — only shown for finished matches with a saved prediction --%>
      <%= if @match.status == :finished and saved?(@prediction) do %>
        <% outcome = pred_outcome(@match, @prediction) %>
        <div class="mt-2 pt-2 border-t border-divider flex items-center justify-between">
          <span class="text-[11px] text-muted">Tu pronóstico</span>
          <div class="flex items-center gap-2">
            <span class={["text-[12px] font-semibold tabular-nums", pred_score_color(outcome)]}>
              {@prediction.home_score}–{@prediction.away_score}
            </span>
            <span class={["text-[10px] font-semibold px-1.5 py-0.5 rounded-full", pill_class(outcome)]}>
              {pill_text(@prediction.points_awarded, outcome)}
            </span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # outcome relative to the actual result
  defp pred_outcome(_match, %{points_awarded: nil}), do: :pending
  defp pred_outcome(_match, %{points_awarded: 0}), do: :miss

  defp pred_outcome(match, pred) do
    if pred.home_score == match.home_score and pred.away_score == match.away_score,
      do: :exact,
      else: :outcome
  end

  defp pill_class(:exact), do: "bg-green-100 text-green-700"
  defp pill_class(:outcome), do: "bg-amber-100 text-amber-700"
  defp pill_class(:miss), do: "bg-red-100 text-red-500"
  defp pill_class(:pending), do: "bg-gray-100 text-muted"

  defp pill_text(pts, :exact), do: "+#{pts} pts ★"
  defp pill_text(pts, :outcome) when not is_nil(pts), do: "+#{pts} pts"
  defp pill_text(_, :outcome), do: "✓"
  defp pill_text(_, :miss), do: "0 pts"
  defp pill_text(_, :pending), do: "—"

  defp pred_score_color(:exact), do: "text-green-600"
  defp pred_score_color(:outcome), do: "text-amber-600"
  defp pred_score_color(:miss), do: "text-red-400"
  defp pred_score_color(_), do: "text-ink-2"

  # ── Score cell ────────────────────────────────────────────────────────

  attr :value, :integer, default: nil
  attr :variant, :atom, default: :empty

  def score_cell(assigns) do
    ~H"""
    <div class={["w-9 h-9 rounded-lg flex items-center justify-center font-score text-base", cell_bg(@variant)]}>
      <%= if not is_nil(@value) do %>
        {@value}
      <% else %>
        <span class="text-muted-2 text-sm">-</span>
      <% end %>
    </div>
    """
  end

  defp cell_bg(:finished), do: "bg-gray-100 text-ink-2"
  defp cell_bg(:live), do: "bg-live-soft text-live border border-live"
  defp cell_bg(:saved), do: "bg-white text-ink border-l-2 border-brand shadow-sm"
  defp cell_bg(:empty), do: "bg-gray-50 border border-dashed border-muted-2 text-muted-2"

  defp cell_variant(match, prediction, side) do
    cond do
      match.status == :finished -> :finished
      match.status == :live -> :live
      saved?(prediction) and not is_nil(score_from_pred(prediction, side)) -> :saved
      true -> :empty
    end
  end

  defp home_display(%{status: s, home_score: score}, _pred) when s in [:live, :finished],
    do: score

  defp home_display(_match, pred), do: score_from_pred(pred, :home)

  defp away_display(%{status: s, away_score: score}, _pred) when s in [:live, :finished],
    do: score

  defp away_display(_match, pred), do: score_from_pred(pred, :away)

  defp score_from_pred(nil, _), do: nil
  defp score_from_pred(pred, :home), do: pred.home_score
  defp score_from_pred(pred, :away), do: pred.away_score

  defp saved?(nil), do: false
  defp saved?(pred), do: not is_nil(pred.home_score) and not is_nil(pred.away_score)

  defp score_group_label(%{status: s, home_score: h, away_score: a}, _pred)
       when s in [:live, :finished] and not is_nil(h),
       do: "Resultado: #{h}-#{a}"

  defp score_group_label(_match, pred) when not is_nil(pred) and pred.home_score != nil,
    do: "Pronóstico: #{pred.home_score}-#{pred.away_score}"

  defp score_group_label(_match, _pred), do: "Sin pronóstico"

  # ── Match status badge ────────────────────────────────────────────────

  attr :match, :map, required: true
  attr :prediction, :map, default: nil

  def match_badge(assigns) do
    ~H"""
    <span class={["text-[10px] font-semibold px-1.5 py-0.5 rounded-full uppercase tracking-wide", badge_class(@match)]}>
      {badge_text(@match, @prediction)}
    </span>
    """
  end

  defp badge_class(%{status: :live}), do: "bg-live-soft text-live"
  defp badge_class(%{status: :finished}), do: "bg-gray-100 text-muted"
  defp badge_class(%{locked: true}), do: "bg-brand-soft text-brand"
  defp badge_class(%{status: :postponed}), do: "bg-gray-100 text-muted"
  defp badge_class(_), do: "bg-transparent text-transparent"

  defp badge_text(%{status: :live}, _), do: "VIVO"
  defp badge_text(%{status: :finished}, nil), do: "FIN"

  defp badge_text(%{status: :finished}, pred) do
    if saved?(pred), do: "FIN · ✓", else: "FIN"
  end

  defp badge_text(%{locked: true}, _), do: "CERRADO"
  defp badge_text(%{status: :postponed}, _), do: "POSTERGADO"
  defp badge_text(_, _), do: ""

  # ── Live dot ──────────────────────────────────────────────────────────

  def live_dot(assigns) do
    ~H"""
    <span class="inline-block size-2 rounded-full bg-live animate-live" aria-label="En vivo" />
    """
  end

  # ── Avatar initial ────────────────────────────────────────────────────

  attr :name, :string, required: true
  attr :size, :string, default: "size-9"
  attr :highlight, :boolean, default: false

  def avatar_initial(assigns) do
    assigns = assign(assigns, :color, avatar_color(assigns.name))

    ~H"""
    <div class={[
      @size, "rounded-full flex items-center justify-center font-score text-sm text-white flex-shrink-0",
      if(@highlight, do: "ring-2 ring-brand ring-offset-1", else: ""),
      @color
    ]}>
      {String.first(@name) |> String.upcase()}
    </div>
    """
  end

  @avatar_colors ~w(
    bg-blue-500 bg-purple-500 bg-green-600 bg-orange-500
    bg-pink-500 bg-teal-500 bg-indigo-500 bg-amber-500
  )

  defp avatar_color(name) do
    idx = :erlang.phash2(name, length(@avatar_colors))
    Enum.at(@avatar_colors, idx)
  end

  # ── Leaderboard row ───────────────────────────────────────────────────

  attr :id, :string, default: nil
  attr :rank, :integer, required: true
  attr :name, :string, required: true
  attr :total, :integer, required: true
  attr :is_me, :boolean, default: false

  def leaderboard_row(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "flex items-center gap-3 px-4 py-3 border-b border-divider",
        if(@is_me, do: "bg-brand-soft", else: "bg-white")
      ]}
    >
      <span class={["w-6 text-center font-score text-sm", rank_color(@rank, @is_me)]}>
        {@rank}
      </span>
      <.avatar_initial name={@name} highlight={@is_me} />
      <span class={[
        "flex-1 text-sm min-w-0 truncate",
        if(@is_me, do: "font-semibold text-brand", else: "font-medium text-ink")
      ]}>
        {@name}
        <span :if={@is_me} class="ml-1 text-[10px] font-semibold bg-brand text-white px-1 py-0.5 rounded-full uppercase">
          YO
        </span>
      </span>
      <span class="font-score text-sm text-ink tabular-nums">{@total} pts</span>
    </div>
    """
  end

  defp rank_color(1, _), do: "text-gold"
  defp rank_color(2, _), do: "text-silver"
  defp rank_color(3, _), do: "text-bronze"
  defp rank_color(_, true), do: "text-brand"
  defp rank_color(_, _), do: "text-muted"

  # ── Podium (top 3) ────────────────────────────────────────────────────

  attr :rows, :list, required: true

  def podium(assigns) do
    assigns =
      assign(assigns,
        first: Enum.at(assigns.rows, 0),
        second: Enum.at(assigns.rows, 1),
        third: Enum.at(assigns.rows, 2)
      )

    ~H"""
    <div class="flex items-end justify-center gap-3 px-4 pt-4 pb-2">
      <%!-- 2nd place --%>
      <.podium_column row={@second} rank={2} height="h-20" color="bg-silver" />
      <%!-- 1st place --%>
      <.podium_column row={@first} rank={1} height="h-28" color="bg-gold" />
      <%!-- 3rd place --%>
      <.podium_column row={@third} rank={3} height="h-16" color="bg-bronze" />
    </div>
    """
  end

  attr :row, :map, default: nil
  attr :rank, :integer, required: true
  attr :height, :string, required: true
  attr :color, :string, required: true

  defp podium_column(%{row: nil} = assigns) do
    ~H"""
    <div class="flex-1" />
    """
  end

  defp podium_column(assigns) do
    ~H"""
    <div class="flex-1 flex flex-col items-center gap-1">
      <.avatar_initial name={@row.display_name || "?"} size="size-10" />
      <span class="text-[11px] font-medium text-ink-2 text-center leading-tight truncate w-full text-center">
        {short_name(@row.display_name)}
      </span>
      <span class="text-[11px] font-semibold text-muted">{@row.total} pts</span>
      <div class={["w-full rounded-t-lg flex items-center justify-center", @height, @color]}>
        <span class="font-score text-xl text-white">{@rank}</span>
      </div>
    </div>
    """
  end

  defp short_name(nil), do: "—"
  defp short_name(name), do: name |> String.split() |> List.first() |> String.slice(0, 10)

  # ── Tournament card ───────────────────────────────────────────────────

  attr :tournament, :map, required: true
  attr :stats, :map, default: %{}
  attr :bonus_url, :string, default: nil

  def tournament_card(assigns) do
    ~H"""
    <div class="bg-white rounded-[14px] shadow-card overflow-hidden mb-4">
      <%!-- Gradient banner --%>
      <div class="h-24 bg-gradient-to-br from-blue-700 to-indigo-900 flex items-end px-4 pb-3 relative">
        <div class="absolute inset-0 opacity-20 bg-[url('data:image/svg+xml,%3Csvg...')] bg-repeat" />
        <div>
          <div class="text-white/60 text-[10px] font-semibold uppercase tracking-widest mb-0.5">
            Temporada {@tournament.season}
          </div>
          <div class="text-white font-heading text-xl tracking-wide">{@tournament.name}</div>
        </div>
        <.tournament_status_badge status={@tournament.status} />
      </div>
      <%!-- Stats row --%>
      <div class="flex divide-x divide-divider">
        <div class="flex-1 text-center py-3">
          <div class="font-score text-lg text-ink">{Map.get(@stats, :predictions_made, 0)}</div>
          <div class="text-[10px] text-muted uppercase tracking-wide">Pronóst.</div>
        </div>
        <div class="flex-1 text-center py-3">
          <div class="font-score text-lg text-ink">{Map.get(@stats, :points_total, 0)}</div>
          <div class="text-[10px] text-muted uppercase tracking-wide">Puntos</div>
        </div>
        <div class="flex-1 text-center py-3">
          <div class="font-score text-lg text-ink">
            {Map.get(@stats, :group_rank, "—")}
          </div>
          <div class="text-[10px] text-muted uppercase tracking-wide">Posición</div>
        </div>
      </div>
      <%!-- Bonus predictions link --%>
      <%= if @bonus_url do %>
        <div class="border-t border-divider px-4 py-2.5">
          <.link
            navigate={@bonus_url}
            class="flex items-center justify-between text-sm text-brand font-medium"
          >
            <span>★ Pronósticos bonus</span>
            <span class="text-muted-2">›</span>
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp tournament_status_badge(assigns) do
    ~H"""
    <span class={["absolute top-3 right-3 text-[10px] font-bold px-2 py-1 rounded-full uppercase tracking-wide", status_badge_class(@status)]}>
      {status_badge_text(@status)}
    </span>
    """
  end

  defp status_badge_class(:active), do: "bg-live text-white"
  defp status_badge_class(:upcoming), do: "bg-white/20 text-white"
  defp status_badge_class(:finished), do: "bg-black/30 text-white/80"

  defp status_badge_text(:active), do: "En curso"
  defp status_badge_text(:upcoming), do: "Próximo"
  defp status_badge_text(:finished), do: "Finalizado"

  # ── Fixture row (simpler than match_card, read-only) ──────────────────

  attr :match, :map, required: true

  def fixture_row(assigns) do
    assigns =
      assign(assigns,
        home_flag: flag_emoji(assigns.match.home_team.code),
        away_flag: flag_emoji(assigns.match.away_team.code)
      )

    ~H"""
    <div class="flex items-center gap-3 px-4 py-3 border-b border-divider bg-white">
      <%!-- Time / status --%>
      <div class="w-14 flex-shrink-0 text-center">
        <%= cond do %>
          <% @match.status == :live -> %>
            <div class="flex flex-col items-center gap-0.5">
              <.live_dot />
              <span class="text-[10px] font-semibold text-live">VIVO</span>
            </div>
          <% @match.status == :finished -> %>
            <span class="text-[11px] font-semibold text-muted uppercase">FIN</span>
          <% true -> %>
            <span class="text-[13px] font-medium text-ink-2">
              {time_only(@match.kickoff_at)}
            </span>
        <% end %>
      </div>

      <%!-- Match --%>
      <div class="flex-1 flex items-center gap-2">
        <span class="text-lg leading-none">{@home_flag}</span>
        <span class="font-heading text-[13px] text-ink">{@match.home_team.code}</span>
        <span class="text-muted-2 font-bold text-xs mx-1">vs</span>
        <span class="font-heading text-[13px] text-ink">{@match.away_team.code}</span>
        <span class="text-lg leading-none">{@away_flag}</span>
      </div>

      <%!-- Score --%>
      <div class="flex-shrink-0 w-16 text-right">
        <%= if @match.status in [:live, :finished] and not is_nil(@match.home_score) do %>
          <span class="font-score text-sm text-ink">
            {@match.home_score}–{@match.away_score}
          </span>
        <% else %>
          <span class="text-muted-2 text-sm">—</span>
        <% end %>
      </div>
    </div>
    """
  end

  defp time_only(nil), do: "—"

  defp time_only(%DateTime{} = dt) do
    local = DateTime.add(dt, -3 * 3600, :second)
    Calendar.strftime(local, "%H:%M")
  end

  # ── Progress bar ──────────────────────────────────────────────────────

  attr :done, :integer, required: true
  attr :total, :integer, required: true

  def prediction_progress(assigns) do
    assigns =
      assign(assigns,
        pct: if(assigns.total > 0, do: round(assigns.done * 100 / assigns.total), else: 0)
      )

    ~H"""
    <div class="px-4 pt-4 pb-2">
      <div class="flex justify-between items-baseline mb-2">
        <span class="text-sm font-medium text-ink-2">Tus pronósticos</span>
        <span class="text-sm font-semibold text-ink tabular-nums">{@done}/{@total}</span>
      </div>
      <div class="h-1 bg-divider rounded-full overflow-hidden">
        <div
          class="h-full bg-brand rounded-full transition-[width] duration-500"
          style={"width: #{@pct}%"}
        />
      </div>
    </div>
    """
  end

  # ── Score stepper (prediction entry) ─────────────────────────────────

  attr :value, :integer, required: true
  attr :team_name, :string, required: true
  attr :inc_event, :string, required: true
  attr :dec_event, :string, required: true

  def score_stepper(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <button
        phx-click={@inc_event}
        class="size-10 rounded-full bg-brand text-white flex items-center justify-center text-xl font-bold active:scale-95 transition-transform"
        aria-label={"Aumentar #{@team_name}"}
      >
        +
      </button>
      <span class="font-score text-5xl text-ink w-14 text-center tabular-nums leading-none py-1">
        {@value}
      </span>
      <button
        phx-click={@dec_event}
        class={[
          "size-10 rounded-full flex items-center justify-center text-xl font-bold active:scale-95 transition-transform",
          if(@value > 0, do: "bg-gray-100 text-ink", else: "bg-gray-50 text-muted-2 cursor-not-allowed")
        ]}
        disabled={@value == 0}
        aria-label={"Disminuir #{@team_name}"}
      >
        −
      </button>
      <span class="text-[11px] text-muted font-medium mt-0.5">{@team_name}</span>
    </div>
    """
  end

  # ── JS helpers for prediction sheet ──────────────────────────────────

  def open_sheet_js(match_id) do
    JS.push("open_sheet", value: %{match_id: match_id})
    |> JS.show(
      to: "#sheet-backdrop",
      transition: {"transition-opacity duration-200", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "#prediction-sheet",
      transition: {
        "transition-transform duration-300 ease-out",
        "translate-y-full",
        "translate-y-0"
      }
    )
  end

  def close_sheet_js do
    JS.push("close_sheet")
    |> JS.hide(
      to: "#sheet-backdrop",
      transition: {"transition-opacity duration-150", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "#prediction-sheet",
      transition: {
        "transition-transform duration-200 ease-in",
        "translate-y-0",
        "translate-y-full"
      }
    )
  end
end
