defmodule ProdeWeb.Admin.MatchImportLive do
  @moduledoc """
  Admin page for uploading the matches.xlsx file and syncing fixtures to the DB.
  Only accessible to users with is_admin = true.
  """

  use ProdeWeb, :live_view

  alias Prode.Matches.ExcelImporter

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Importar Partidos")
      |> assign(:result, nil)
      |> assign(:uploading, false)
      |> allow_upload(:excel,
        accept: ~w(.xlsx),
        max_entries: 1,
        max_file_size: 20_000_000
      )

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto p-6">
      <h1 class="text-2xl font-bold mb-6">Importar Partidos</h1>

      <form phx-submit="import" phx-change="validate">
        <div
          class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center mb-4 cursor-pointer"
          phx-drop-target={@uploads.excel.ref}
        >
          <.live_file_input upload={@uploads.excel} class="hidden" />
          <p class="text-gray-500 text-sm mb-2">
            Arrastrá el archivo .xlsx aquí o hacé click para seleccionar
          </p>
          <p class="text-gray-400 text-xs">Solo archivos .xlsx, máximo 20 MB</p>

          <%= for entry <- @uploads.excel.entries do %>
            <div class="mt-3 text-sm text-gray-700">
              <span class="font-medium"><%= entry.client_name %></span>
              (<%= Float.round(entry.client_size / 1024 / 1024, 2) %> MB)
            </div>
            <div class="w-full bg-gray-200 rounded-full h-2 mt-2">
              <div
                class="bg-blue-500 h-2 rounded-full transition-all"
                style={"width: #{entry.progress}%"}
              >
              </div>
            </div>
          <% end %>

          <%= for err <- upload_errors(@uploads.excel) do %>
            <p class="text-red-500 text-sm mt-2"><%= upload_error_message(err) %></p>
          <% end %>
        </div>

        <button
          type="submit"
          disabled={@uploads.excel.entries == [] or @uploading}
          class="w-full bg-blue-600 text-white py-2 px-4 rounded-lg font-medium
                 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-blue-700 transition"
        >
          <%= if @uploading, do: "Importando...", else: "Importar partidos" %>
        </button>
      </form>

      <%= if @result do %>
        <div class={[
          "mt-6 p-4 rounded-lg",
          if(@result.errors > 0, do: "bg-yellow-50 border border-yellow-200", else: "bg-green-50 border border-green-200")
        ]}>
          <p class="font-semibold text-gray-800 mb-1">Resultado de la importación</p>
          <ul class="text-sm text-gray-700 space-y-1">
            <li>✓ Sincronizados: <strong><%= @result.synced %></strong></li>
            <li>→ Saltados: <strong><%= @result.skipped %></strong></li>
            <%= if @result.errors > 0 do %>
              <li class="text-red-600">✗ Errores: <strong><%= @result.errors %></strong></li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div class="mt-8 text-sm text-gray-500">
        <p class="font-medium mb-1">Instrucciones</p>
        <ol class="list-decimal list-inside space-y-1">
          <li>Completá los goles en la hoja "Partidos" del Excel.</li>
          <li>Guardá el archivo.</li>
          <li>Subilo aquí — los scores se actualizan en tiempo real.</li>
        </ol>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("import", _params, socket) do
    socket = assign(socket, :uploading, true)

    result =
      consume_uploaded_entries(socket, :excel, fn %{path: path}, _entry ->
        ExcelImporter.import_from_file(path)
      end)

    case result do
      [{:ok, summary}] ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> assign(:result, summary)}

      [{:error, reason}] ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> put_flash(:error, "Error al importar: #{inspect(reason)}")}

      [] ->
        {:noreply, assign(socket, :uploading, false)}
    end
  end

  defp upload_error_message(:too_large), do: "El archivo es demasiado grande (máx 20 MB)."
  defp upload_error_message(:not_accepted), do: "Solo se aceptan archivos .xlsx."
  defp upload_error_message(:too_many_files), do: "Solo se puede subir un archivo a la vez."
  defp upload_error_message(err), do: "Error: #{inspect(err)}"
end
