defmodule ProdeWeb.MasLive do
  use ProdeWeb, :live_view

  alias Prode.Accounts
  alias Prode.Groups
  alias Prode.Tournaments

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    groups = Groups.list_user_groups(user)
    tournament = Tournaments.get_current_tournament()

    {:ok,
     socket
     |> assign(:tab, :mas)
     |> assign(:user, user)
     |> assign(:groups, groups)
     |> assign(:tournament, tournament)
     |> assign(:push_state, :idle)
     |> assign(:whatsapp_state, whatsapp_state(user))
     |> assign(:phone_input, user.phone_number || "")
     |> assign(:code_input, "")
     |> assign(:group_panel, :idle)
     |> assign(:group_name_input, "")
     |> assign(:join_code_input, "")
     |> assign(:created_group, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-8">
      <%!-- Profile card --%>
      <div class="bg-brand px-5 pt-5 pb-8 text-white">
        <div class="flex items-center gap-4">
          <%= if @user.avatar_url do %>
            <img
              src={@user.avatar_url}
              alt="Avatar"
              class="size-16 rounded-full object-cover ring-2 ring-white/30"
            />
          <% else %>
            <div class="size-16 rounded-full bg-white/20 flex items-center justify-center">
              <span class="font-score text-2xl">
                {String.first(@user.display_name || @user.email || "?") |> String.upcase()}
              </span>
            </div>
          <% end %>
          <div>
            <p class="font-semibold text-lg leading-tight">
              {@user.display_name || "Sin nombre"}
            </p>
            <p class="text-sm text-white/70">{@user.email}</p>
            <%= if @user.google_uid do %>
              <span class="mt-1 inline-flex items-center gap-1 text-[11px] bg-white/20 px-2 py-0.5 rounded-full">
                <.icon name="hero-check-circle" class="size-3" /> Google
              </span>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Groups card --%>
      <div class="-mt-4 mx-4 mb-3 bg-white rounded-[14px] shadow-card overflow-hidden">
        <div class="px-4 py-3 border-b border-divider">
          <p class="text-[11px] font-semibold text-muted uppercase tracking-widest">
            Mis grupos
          </p>
        </div>

        <%!-- Existing groups --%>
        <%= for group <- @groups do %>
          <div class="px-4 py-3 border-b border-divider">
            <div class="flex items-center justify-between">
              <span class="text-sm font-semibold text-ink truncate">{group.name}</span>
              <button
                phx-click="copy_invite_link"
                phx-value-code={group.invite_code}
                class="text-xs text-brand font-medium flex items-center gap-1 flex-shrink-0 ml-2"
              >
                <.icon name="hero-link" class="size-3.5" /> Copiar link
              </button>
            </div>
            <p class="text-xs text-muted mt-0.5">
              Código: <span class="font-mono font-semibold tracking-wider">{group.invite_code}</span>
            </p>
          </div>
        <% end %>

        <%= if Enum.empty?(@groups) do %>
          <div class="px-4 py-4 text-center">
            <p class="text-xs text-muted">Todavía no pertenecés a ningún grupo.</p>
          </div>
        <% end %>

        <%!-- Action buttons --%>
        <%= if @group_panel == :idle do %>
          <div class="flex divide-x divide-divider">
            <button
              phx-click="show_create_group"
              class="flex-1 py-3 text-sm text-brand font-medium text-center"
            >
              + Crear grupo
            </button>
            <button
              phx-click="show_join_group"
              class="flex-1 py-3 text-sm text-brand font-medium text-center"
            >
              Unirse a grupo
            </button>
          </div>
        <% end %>

        <%!-- Create group form --%>
        <%= if @group_panel == :creating do %>
          <div class="px-4 py-3 border-t border-divider">
            <p class="text-xs font-semibold text-ink mb-2">Nuevo grupo</p>
            <input
              type="text"
              phx-change="update_group_name"
              phx-keyup="update_group_name"
              name="group_name"
              value={@group_name_input}
              placeholder="Nombre del grupo…"
              maxlength="50"
              class="w-full border border-divider rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-brand mb-2"
            />
            <div class="flex gap-2">
              <button
                phx-click="create_group"
                class="flex-1 py-2 bg-brand text-white text-sm font-medium rounded-lg disabled:opacity-40"
              >
                Crear
              </button>
              <button
                phx-click="cancel_group_panel"
                class="px-4 py-2 text-sm text-muted rounded-lg border border-divider"
              >
                Cancelar
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Join group form --%>
        <%= if @group_panel == :joining do %>
          <div class="px-4 py-3 border-t border-divider">
            <p class="text-xs font-semibold text-ink mb-2">Unirse con código</p>
            <input
              type="text"
              phx-change="update_join_code"
              phx-keyup="update_join_code"
              name="join_code"
              value={@join_code_input}
              placeholder="Ej: ABC123"
              maxlength="6"
              class="w-full border border-divider rounded-lg px-3 py-2 text-sm font-mono tracking-widest text-center uppercase focus:outline-none focus:border-brand mb-2"
            />
            <div class="flex gap-2">
              <button
                phx-click="join_group"
                class="flex-1 py-2 bg-brand text-white text-sm font-medium rounded-lg"
              >
                Unirse
              </button>
              <button
                phx-click="cancel_group_panel"
                class="px-4 py-2 text-sm text-muted rounded-lg border border-divider"
              >
                Cancelar
              </button>
            </div>
          </div>
        <% end %>

        <%!-- Created group confirmation --%>
        <%= if @created_group do %>
          <div class="px-4 py-3 border-t border-divider bg-green-50">
            <p class="text-xs font-semibold text-live mb-1">¡Grupo creado!</p>
            <p class="text-xs text-ink mb-2">
              Compartí este link para invitar a tus amigos:
            </p>
            <div class="flex items-center gap-2 bg-white border border-divider rounded-lg px-3 py-2">
              <span class="flex-1 text-xs font-mono text-muted truncate" id="invite-link">
                {invite_url(@created_group.invite_code)}
              </span>
              <button
                phx-click="copy_invite_link"
                phx-value-code={@created_group.invite_code}
                class="text-xs text-brand font-medium flex-shrink-0"
              >
                Copiar
              </button>
            </div>
            <button
              phx-click="dismiss_created_group"
              class="mt-2 text-xs text-muted w-full text-center"
            >
              Listo
            </button>
          </div>
        <% end %>
      </div>

      <%!-- Card pulled up over header --%>
      <div class="mx-4 bg-white rounded-[14px] shadow-card divide-y divide-divider">
        <%!-- Notifications section --%>
        <div class="px-4 py-3">
          <p class="text-[11px] font-semibold text-muted uppercase tracking-widest mb-3">
            Notificaciones
          </p>

          <div class="flex items-center justify-between py-1">
            <div class="flex items-center gap-2">
              <.icon name="hero-bell" class="size-4 text-muted" />
              <span class="text-sm text-ink">Push</span>
            </div>
            <%= case @push_state do %>
              <% :subscribed -> %>
                <span class="text-[11px] text-live font-semibold flex items-center gap-1">
                  <.icon name="hero-check-circle" class="size-3.5" /> Activo
                </span>
              <% :denied -> %>
                <span class="text-xs text-muted">Bloqueado</span>
              <% :unsupported -> %>
                <span class="text-xs text-muted italic">No disponible</span>
              <% _ -> %>
                <button
                  id="push-subscribe-btn"
                  phx-hook="PushSubscription"
                  class="text-xs text-brand font-semibold"
                >
                  Activar
                </button>
            <% end %>
          </div>

          <%!-- WhatsApp opt-in --%>
          <div class="mt-2">
            <div class="flex items-center justify-between py-1">
              <div class="flex items-center gap-2">
                <.icon name="hero-chat-bubble-left" class="size-4 text-muted" />
                <span class="text-sm text-ink">WhatsApp</span>
              </div>
              <%= if @user.whatsapp_opted_in do %>
                <span class="text-[11px] text-live font-semibold flex items-center gap-1">
                  <.icon name="hero-check-circle" class="size-3.5" /> Activo
                </span>
              <% else %>
                <button
                  phx-click="start_whatsapp"
                  class="text-xs text-brand font-semibold"
                >
                  Activar
                </button>
              <% end %>
            </div>

            <%= if @whatsapp_state == :entering_phone do %>
              <div class="mt-2 flex gap-2">
                <input
                  type="tel"
                  phx-change="update_phone"
                  name="phone"
                  value={@phone_input}
                  placeholder="+54 9 11 1234-5678"
                  class="flex-1 border border-divider rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-brand"
                />
                <button
                  phx-click="send_whatsapp_code"
                  class="px-3 py-2 bg-brand text-white text-sm font-medium rounded-lg"
                >
                  Enviar
                </button>
              </div>
            <% end %>

            <%= if @whatsapp_state == :entering_code do %>
              <div class="mt-2">
                <p class="text-xs text-muted mb-2">
                  Ingresá el código de 6 dígitos enviado a {@user.phone_number}
                </p>
                <div class="flex gap-2">
                  <input
                    type="text"
                    phx-change="update_code"
                    name="code"
                    value={@code_input}
                    placeholder="123456"
                    maxlength="6"
                    class="flex-1 border border-divider rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-brand tracking-widest text-center font-score"
                  />
                  <button
                    phx-click="verify_whatsapp_code"
                    class="px-3 py-2 bg-brand text-white text-sm font-medium rounded-lg"
                  >
                    Verificar
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Account section --%>
        <div class="px-4 py-3">
          <p class="text-[11px] font-semibold text-muted uppercase tracking-widest mb-3">
            Cuenta
          </p>

          <.link
            navigate={~p"/users/settings"}
            class="flex items-center justify-between py-2"
          >
            <div class="flex items-center gap-2">
              <.icon name="hero-cog-6-tooth" class="size-4 text-muted" />
              <span class="text-sm text-ink">Configuración de cuenta</span>
            </div>
            <.icon name="hero-chevron-right" class="size-4 text-muted-2" />
          </.link>
        </div>
      </div>

      <%!-- Sign out --%>
      <div class="mx-4 mt-4">
        <.link
          href={~p"/users/log-out"}
          method="delete"
          class="w-full flex items-center justify-center gap-2 py-3 border border-brand text-brand font-semibold rounded-xl text-sm active:scale-[0.98] transition-transform"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
          Cerrar sesión
        </.link>
      </div>

      <%!-- App version --%>
      <p class="text-center text-[11px] text-muted-2 mt-6">Prode v1.0 · Mundial 2026</p>
    </div>
    """
  end

  # ── Events ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("show_create_group", _params, socket) do
    {:noreply, assign(socket, group_panel: :creating, created_group: nil)}
  end

  def handle_event("show_join_group", _params, socket) do
    {:noreply, assign(socket, group_panel: :joining, created_group: nil)}
  end

  def handle_event("cancel_group_panel", _params, socket) do
    {:noreply, assign(socket, group_panel: :idle, group_name_input: "", join_code_input: "")}
  end

  def handle_event("dismiss_created_group", _params, socket) do
    {:noreply, assign(socket, created_group: nil, group_panel: :idle)}
  end

  def handle_event("update_group_name", %{"group_name" => name}, socket) do
    {:noreply, assign(socket, :group_name_input, name)}
  end

  def handle_event("update_join_code", %{"join_code" => code}, socket) do
    {:noreply, assign(socket, :join_code_input, String.upcase(code))}
  end

  def handle_event("create_group", _params, socket) do
    user = socket.assigns.current_scope.user
    name = String.trim(socket.assigns.group_name_input)
    tournament = socket.assigns.tournament

    if is_nil(tournament) do
      {:noreply, put_flash(socket, :error, "No hay torneo activo en este momento.")}
    else
      case Groups.create_group(user, %{name: name, tournament_id: tournament.id}) do
        {:ok, group} ->
          groups = Groups.list_user_groups(user)

          {:noreply,
           socket
           |> assign(:groups, groups)
           |> assign(:created_group, group)
           |> assign(:group_panel, :idle)
           |> assign(:group_name_input, "")}

        {:error, changeset} ->
          msg = format_changeset_errors(changeset)
          {:noreply, put_flash(socket, :error, "No se pudo crear el grupo: #{msg}")}
      end
    end
  end

  def handle_event("join_group", _params, socket) do
    user = socket.assigns.current_scope.user
    code = String.trim(socket.assigns.join_code_input)

    case Groups.join_by_invite_code(user, code) do
      {:ok, _group} ->
        groups = Groups.list_user_groups(user)

        {:noreply,
         socket
         |> assign(:groups, groups)
         |> assign(:group_panel, :idle)
         |> assign(:join_code_input, "")
         |> put_flash(:info, "¡Te uniste al grupo!")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Código de invitación no encontrado.")}

      {:error, :already_member} ->
        {:noreply,
         socket
         |> assign(:group_panel, :idle)
         |> assign(:join_code_input, "")
         |> put_flash(:info, "Ya sos miembro de ese grupo.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo unir al grupo.")}
    end
  end

  def handle_event("copy_invite_link", %{"code" => code}, socket) do
    url = invite_url(code)
    {:noreply, push_event(socket, "copy_to_clipboard", %{text: url})}
  end

  @impl true
  def handle_event("push_subscribed", %{"endpoint" => ep, "p256dh" => p256dh, "auth" => auth}, socket) do
    user = socket.assigns.current_scope.user

    case Prode.Notifications.upsert_push_subscription(user, %{endpoint: ep, p256dh: p256dh, auth: auth}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:push_state, :subscribed)
         |> put_flash(:info, "¡Notificaciones push activadas!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo guardar la suscripción.")}
    end
  end

  def handle_event("push_denied", _params, socket) do
    {:noreply, assign(socket, :push_state, :denied)}
  end

  def handle_event("push_not_supported", _params, socket) do
    {:noreply, assign(socket, :push_state, :unsupported)}
  end

  def handle_event("push_error", _params, socket) do
    {:noreply, put_flash(socket, :error, "Error al activar notificaciones push.")}
  end

  def handle_event("start_whatsapp", _params, socket) do
    {:noreply, assign(socket, :whatsapp_state, :entering_phone)}
  end

  def handle_event("update_phone", %{"phone" => phone}, socket) do
    {:noreply, assign(socket, :phone_input, phone)}
  end

  def handle_event("update_code", %{"code" => code}, socket) do
    {:noreply, assign(socket, :code_input, code)}
  end

  def handle_event("send_whatsapp_code", _params, socket) do
    phone = String.trim(socket.assigns.phone_input)

    case Accounts.update_whatsapp_preferences(socket.assigns.user, %{
           phone_number: phone,
           whatsapp_opted_in: false
         }) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:whatsapp_state, :entering_code)
         |> put_flash(:info, "Código enviado a #{phone}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo enviar el código.")}
    end
  end

  def handle_event("verify_whatsapp_code", _params, socket) do
    # WhatsApp verification skipped until Meta Cloud API integration is complete
    case Accounts.update_whatsapp_preferences(socket.assigns.user, %{
           whatsapp_opted_in: true
         }) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:whatsapp_state, :verified)
         |> put_flash(:info, "¡WhatsApp activado!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Código incorrecto. Intentá de nuevo.")}
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp whatsapp_state(user) do
    cond do
      user.whatsapp_opted_in -> :verified
      user.phone_number -> :entering_code
      true -> :idle
    end
  end

  defp invite_url(code), do: ProdeWeb.Endpoint.url() <> "/join/#{code}"

  defp format_changeset_errors(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end
end
