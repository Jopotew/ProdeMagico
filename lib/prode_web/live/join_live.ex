defmodule ProdeWeb.JoinLive do
  use ProdeWeb, :live_view

  alias Prode.Groups

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Groups.join_by_invite_code(user, code) do
      {:ok, group} ->
        {:ok,
         socket
         |> put_flash(:info, "¡Te uniste a #{group.name}!")
         |> push_navigate(to: ~p"/posiciones")}

      {:error, :already_member} ->
        {:ok,
         socket
         |> put_flash(:info, "Ya sos miembro de ese grupo.")
         |> push_navigate(to: ~p"/posiciones")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> assign(:tab, :mas)
         |> assign(:code, code)
         |> assign(:error, :not_found)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-24 px-8 text-center">
      <.icon name="hero-exclamation-circle" class="size-12 text-muted-2 mb-4" />
      <p class="font-semibold text-ink mb-1">Código de invitación inválido</p>
      <p class="text-sm text-muted mb-6">
        El código <span class="font-mono font-bold">{@code}</span> no existe o ya no está activo.
      </p>
      <.link navigate={~p"/"} class="text-sm text-brand font-medium">
        Volver al inicio
      </.link>
    </div>
    """
  end
end
