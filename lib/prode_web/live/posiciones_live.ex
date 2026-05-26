defmodule ProdeWeb.PosicionesLive do
  use ProdeWeb, :live_view

  alias Prode.Groups

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    groups = socket.assigns.user_groups
    active_group = List.first(groups)

    {lb, my_rank} =
      if active_group do
        rows = Groups.leaderboard_for_group(active_group.id, limit: @page_size)
        rank = find_rank(rows, user.id)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(Prode.PubSub, "group:#{active_group.id}")
        end

        {rows, rank}
      else
        {[], nil}
      end

    top3 = Enum.take(lb, 3)
    stream_rows = ranked_stream_rows(lb, socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:tab, :posiciones)
     |> assign(:active_group, active_group)
     |> assign(:leaderboard, lb)
     |> assign(:top3, top3)
     |> assign(:my_rank, my_rank)
     |> assign(:page_size, @page_size)
     |> assign(:offset, @page_size)
     |> assign(:has_more, length(lb) == @page_size)
     |> stream(:leaderboard_rows, stream_rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-4">
      <%!-- Group selector --%>
      <%= if length(@user_groups) > 1 do %>
        <div class="flex gap-2 px-4 pt-3 pb-2 overflow-x-auto">
          <%= for group <- @user_groups do %>
            <button
              phx-click="switch_group"
              phx-value-group_id={group.id}
              class={[
                "flex-shrink-0 px-3 py-1.5 rounded-full text-sm font-medium transition-colors",
                if(@active_group && @active_group.id == group.id,
                  do: "bg-brand text-white",
                  else: "bg-white text-ink border border-divider"
                )
              ]}
            >
              {group.name}
            </button>
          <% end %>
        </div>
      <% end %>

      <%= cond do %>
        <% is_nil(@active_group) -> %>
          <div class="text-center py-16 px-8">
            <.icon name="hero-user-group" class="size-10 mx-auto mb-3 text-muted-2" />
            <p class="text-sm font-medium text-ink-2 mb-1">No estás en ningún grupo</p>
            <p class="text-xs text-muted">
              Creá o uníte a un grupo desde la sección Más para ver las posiciones.
            </p>
          </div>

        <% Enum.empty?(@leaderboard) -> %>
          <div class="text-center py-16 text-muted">
            <.icon name="hero-trophy" class="size-10 mx-auto mb-3 text-muted-2" />
            <p class="text-sm">Nadie ha pronosticado todavía.</p>
          </div>

        <% true -> %>
          <%!-- Podium --%>
          <.podium rows={@top3} />

          <%!-- Full ranking --%>
          <.section_heading class="px-4">Clasificación</.section_heading>

          <div id="leaderboard-list" class="bg-white rounded-t-[14px] overflow-hidden mx-4" phx-update="stream">
            <%= for {dom_id, row} <- @streams.leaderboard_rows do %>
              <.leaderboard_row
                id={dom_id}
                rank={row.rank}
                name={row.display_name}
                total={row.total}
                is_me={row.is_me}
              />
            <% end %>
          </div>

          <%= if @has_more do %>
            <div id="leaderboard-sentinel" phx-hook="InfiniteScroll" class="h-4 mx-4" />
          <% end %>

          <%!-- Sticky "me" row if outside top list --%>
          <%= if @my_rank && @my_rank > @page_size do %>
            <% me = find_my_row(@leaderboard, @current_scope) %>
            <%= if me do %>
              <div class="sticky bottom-16 mx-4">
                <.leaderboard_row
                  rank={@my_rank}
                  name={me.display_name || "Vos"}
                  total={me.total || 0}
                  is_me={true}
                />
              </div>
            <% end %>
          <% end %>
      <% end %>
    </div>
    """
  end

  # ── Events ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("switch_group", %{"group_id" => group_id}, socket) do
    user = socket.assigns.current_scope.user
    new_group = Enum.find(socket.assigns.user_groups, &(&1.id == group_id))

    if new_group do
      if socket.assigns.active_group do
        Phoenix.PubSub.unsubscribe(Prode.PubSub, "group:#{socket.assigns.active_group.id}")
      end

      Phoenix.PubSub.subscribe(Prode.PubSub, "group:#{new_group.id}")
      lb = Groups.leaderboard_for_group(new_group.id, limit: @page_size)
      rank = find_rank(lb, user.id)
      stream_rows = ranked_stream_rows(lb, socket.assigns.current_scope)

      {:noreply,
       socket
       |> assign(:active_group, new_group)
       |> assign(:leaderboard, lb)
       |> assign(:top3, Enum.take(lb, 3))
       |> assign(:my_rank, rank)
       |> assign(:offset, @page_size)
       |> assign(:has_more, length(lb) == @page_size)
       |> stream(:leaderboard_rows, stream_rows, reset: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("load_more", _params, socket) do
    %{active_group: group, leaderboard: current_lb, offset: offset} = socket.assigns

    if group do
      new_rows = Groups.leaderboard_for_group(group.id, limit: @page_size, offset: offset)
      all_lb = current_lb ++ new_rows
      new_stream_rows = ranked_stream_rows(new_rows, socket.assigns.current_scope, offset)

      socket =
        Enum.reduce(new_stream_rows, socket, fn row, acc ->
          stream_insert(acc, :leaderboard_rows, row, at: -1)
        end)

      {:noreply,
       socket
       |> assign(:leaderboard, all_lb)
       |> assign(:offset, offset + @page_size)
       |> assign(:has_more, length(new_rows) == @page_size)}
    else
      {:noreply, socket}
    end
  end

  # ── PubSub ────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:leaderboard_updated, group_id}, socket) do
    if socket.assigns.active_group && socket.assigns.active_group.id == group_id do
      user = socket.assigns.current_scope.user
      loaded_count = max(length(socket.assigns.leaderboard), @page_size)
      lb = Groups.leaderboard_for_group(group_id, limit: loaded_count)
      rank = find_rank(lb, user.id)
      stream_rows = ranked_stream_rows(lb, socket.assigns.current_scope)

      {:noreply,
       socket
       |> assign(:leaderboard, lb)
       |> assign(:top3, Enum.take(lb, 3))
       |> assign(:my_rank, rank)
       |> assign(:offset, loaded_count)
       |> assign(:has_more, length(lb) == loaded_count)
       |> stream(:leaderboard_rows, stream_rows, reset: true)}
    else
      {:noreply, socket}
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp ranked_stream_rows(rows, current_scope, base_offset \\ 0) do
    Enum.with_index(rows, base_offset + 1)
    |> Enum.map(fn {row, rank} ->
      %{
        id: "lb-#{normalize_uuid(row.id)}",
        rank: rank,
        display_name: row.display_name || "Jugador",
        total: row.total || 0,
        is_me: my_row?(row, current_scope)
      }
    end)
  end

  defp find_rank(leaderboard, user_id) do
    user_id_str = to_string(user_id)

    case Enum.find_index(leaderboard, fn row -> normalize_uuid(row.id) == user_id_str end) do
      nil -> nil
      idx -> idx + 1
    end
  end

  defp find_my_row(leaderboard, current_scope) do
    user_id = to_string(current_scope.user.id)
    Enum.find(leaderboard, fn row -> normalize_uuid(row.id) == user_id end)
  end

  defp my_row?(row, current_scope) do
    normalize_uuid(row.id) == to_string(current_scope.user.id)
  end

  # Postgrex returns UUID columns as 16-byte binaries in raw SQL queries
  defp normalize_uuid(<<_::128>> = bin) do
    case Ecto.UUID.load(bin) do
      {:ok, str} -> str
      _ -> to_string(bin)
    end
  end

  defp normalize_uuid(other), do: to_string(other)
end
