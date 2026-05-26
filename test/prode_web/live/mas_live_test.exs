defmodule ProdeWeb.MasLiveTest do
  use ProdeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Prode.Factory

  setup :register_and_log_in_user

  describe "mount" do
    test "renders profile card with user email", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/mas")
      assert html =~ user.email
    end

    test "shows sign-out link", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/mas")
      assert html =~ "Cerrar sesión"
      assert html =~ "/users/log-out"
    end

    test "shows empty groups message when user has no groups", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/mas")
      assert html =~ "Todavía no pertenecés a ningún grupo"
    end
  end

  describe "group creation" do
    setup %{user: user} do
      tournament = insert(:tournament, status: :active)
      %{tournament: tournament, user: user}
    end

    test "create group form appears on button click", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/mas")
      html = render_click(lv, "show_create_group", %{})
      assert html =~ "Nuevo grupo"
    end

    test "cancel hides the create form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/mas")
      render_click(lv, "show_create_group", %{})
      html = render_click(lv, "cancel_group_panel", %{})
      refute html =~ "Nuevo grupo"
    end

    test "creating a group shows the invite link", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/mas")
      render_click(lv, "show_create_group", %{})
      render_keyup(lv, "update_group_name", %{"group_name" => "Los Cracks"})

      html = render_click(lv, "create_group", %{})
      assert html =~ "Compartí este link"
      assert html =~ "/join/"
    end
  end

  describe "group join" do
    setup _ctx do
      tournament = insert(:tournament, status: :active)
      other_user = insert(:user)
      group = insert(:group, tournament: tournament, owner: other_user)
      insert(:membership, group: group, user: other_user, role: :admin)
      %{group: group}
    end

    test "join form appears on button click", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/mas")
      html = render_click(lv, "show_join_group", %{})
      assert html =~ "Unirse con código"
    end

    test "joining with a valid code adds the group", %{conn: conn, group: group} do
      {:ok, lv, _html} = live(conn, ~p"/mas")
      render_click(lv, "show_join_group", %{})
      render_keyup(lv, "update_join_code", %{"join_code" => group.invite_code})

      html = render_click(lv, "join_group", %{})
      assert html =~ group.name
    end

    test "joining with an invalid code shows an error flash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/mas")
      render_click(lv, "show_join_group", %{})
      render_keyup(lv, "update_join_code", %{"join_code" => "XXXXXX"})

      html = render_click(lv, "join_group", %{})
      assert html =~ "no encontrado"
    end
  end

  describe "WhatsApp opt-in" do
    test "activar button shows phone input", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/mas")
      html = render_click(lv, "start_whatsapp", %{})
      assert html =~ "Enviar"
      assert html =~ ~s(type="tel")
    end

    test "sending phone transitions to code entry", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/mas")
      render_click(lv, "start_whatsapp", %{})
      render_change(lv, "update_phone", %{"phone" => "+54911234567"})

      html = render_click(lv, "send_whatsapp_code", %{})
      assert html =~ "Verificar"
    end
  end

  describe "push state" do
    test "push_denied event sets state to denied", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/mas")
      render_click(lv, "push_denied", %{})
      html = render(lv)
      assert html =~ "Bloqueado"
    end

    test "push_not_supported event sets state to unsupported", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/mas")
      render_click(lv, "push_not_supported", %{})
      html = render(lv)
      assert html =~ "No disponible"
    end
  end
end
