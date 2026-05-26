defmodule ProdeWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ProdeWeb, :html

  embed_templates "layouts/*"

  # ── Mobile app shell ────────────────────────────────────────────────

  def mobile(assigns) do
    ~H"""
    <div class="flex flex-col h-dvh max-w-md mx-auto bg-app-bg relative">
      <%!-- Red header --%>
      <header class="bg-brand text-white flex items-center justify-between px-4 py-3 flex-shrink-0 z-10"
              style="box-shadow: 0 2px 12px rgb(232 32 42 / 0.25)">
        <div class="flex items-center gap-2.5">
          <.icon name="hero-trophy" class="size-6 text-white" />
          <div>
            <div class="font-heading text-xl leading-none tracking-widest">PRODE</div>
            <div class="text-[11px] opacity-75 leading-none mt-0.5 font-body">
              {if assigns[:active_tournament], do: assigns.active_tournament.name, else: "Mundial 2026"}
            </div>
          </div>
        </div>
        <div class="size-8 rounded-full bg-white/20 flex items-center justify-center">
          <span class="font-heading text-sm font-bold">
            {user_initial(assigns[:current_scope])}
          </span>
        </div>
      </header>

      <%!-- Flash messages --%>
      <.flash_group flash={@flash} />

      <%!-- Scrollable page content --%>
      <main class="flex-1 min-h-0 overflow-y-auto">
        {@inner_content}
      </main>

      <%!-- Bottom tab bar --%>
      <nav class="flex-shrink-0 bg-white border-t border-divider flex items-center pb-safe z-10">
        <.tab_item path={~p"/"} tab={:pronosticos} current_tab={assigns[:tab]}
                   icon="hero-pencil-square" label="Pronósticos" />
        <.tab_item path={~p"/posiciones"} tab={:posiciones} current_tab={assigns[:tab]}
                   icon="hero-trophy" label="Posiciones" />
        <.tab_item path={~p"/torneos"} tab={:torneos} current_tab={assigns[:tab]}
                   icon="hero-globe-alt" label="Torneos" />
        <.tab_item path={~p"/fixture"} tab={:fixture} current_tab={assigns[:tab]}
                   icon="hero-calendar" label="Fixture" />
        <.tab_item path={~p"/mas"} tab={:mas} current_tab={assigns[:tab]}
                   icon="hero-user-circle" label="Más" />
      </nav>
    </div>
    """
  end

  defp tab_item(assigns) do
    assigns = assign(assigns, :active, assigns.tab == assigns.current_tab)

    ~H"""
    <.link
      navigate={@path}
      class={[
        "flex-1 flex flex-col items-center gap-0.5 py-2 transition-colors",
        if(@active, do: "text-brand", else: "text-muted")
      ]}
    >
      <.icon name={@icon} class="size-5" />
      <span class={[
        "text-[10px] leading-none",
        if(@active, do: "font-semibold", else: "font-medium")
      ]}>
        {@label}
      </span>
    </.link>
    """
  end

  defp user_initial(nil), do: "?"
  defp user_initial(%{user: nil}), do: "?"

  defp user_initial(%{user: user}) do
    (user.display_name || user.email || "?")
    |> String.first()
    |> String.upcase()
  end

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
