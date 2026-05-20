defmodule ProdeWeb.ProfileLive do
  use ProdeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>Mi Perfil</.header>

    <div class="mt-8 max-w-md">
      <div class="flex items-center gap-4 mb-6">
        <%= if @current_scope.user.avatar_url do %>
          <img
            src={@current_scope.user.avatar_url}
            alt="Avatar"
            class="h-16 w-16 rounded-full object-cover"
          />
        <% else %>
          <div class="flex h-16 w-16 items-center justify-center rounded-full bg-zinc-200 text-2xl font-semibold text-zinc-600">
            {String.first(@current_scope.user.email) |> String.upcase()}
          </div>
        <% end %>

        <div>
          <h2 class="text-xl font-semibold text-zinc-900">
            {@current_scope.user.display_name || @current_scope.user.email}
          </h2>
          <p class="text-sm text-zinc-500">{@current_scope.user.email}</p>
          <%= if @current_scope.user.google_uid do %>
            <span class="mt-1 inline-flex items-center rounded-full bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-700/10">
              Google
            </span>
          <% end %>
        </div>
      </div>

      <dl class="divide-y divide-zinc-100 border-t border-zinc-200">
        <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
          <dt class="text-sm font-medium text-zinc-500">Email</dt>
          <dd class="mt-1 text-sm text-zinc-900 sm:col-span-2 sm:mt-0">
            {@current_scope.user.email}
          </dd>
        </div>
        <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
          <dt class="text-sm font-medium text-zinc-500">Nombre</dt>
          <dd class="mt-1 text-sm text-zinc-900 sm:col-span-2 sm:mt-0">
            {@current_scope.user.display_name || "No configurado"}
          </dd>
        </div>
        <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
          <dt class="text-sm font-medium text-zinc-500">Miembro desde</dt>
          <dd class="mt-1 text-sm text-zinc-900 sm:col-span-2 sm:mt-0">
            {Calendar.strftime(@current_scope.user.inserted_at, "%d/%m/%Y")}
          </dd>
        </div>
      </dl>

      <div class="mt-6">
        <.link href={~p"/users/settings"} class="text-sm text-blue-600 hover:underline">
          Editar configuración de cuenta
        </.link>
      </div>
    </div>
    """
  end
end
