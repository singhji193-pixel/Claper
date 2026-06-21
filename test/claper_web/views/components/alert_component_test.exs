defmodule ClaperWeb.Component.AlertTest do
  use ClaperWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ClaperWeb.Component.Alert

  test "info notifications render as an accessible high-contrast toast" do
    html = render_component(&Alert.info/1, message: "Check your email for the 4-digit code.")

    assert html =~ "claper-flash--info"
    assert html =~ ~s(role="status")
    assert html =~ ~s(aria-live="polite")
    assert html =~ "Check your email for the 4-digit code."
    refute html =~ "supporting-green"
  end

  test "error notifications render with an assertive error state" do
    html = render_component(&Alert.error/1, message: "That code is not valid.")

    assert html =~ "claper-flash--error"
    assert html =~ ~s(role="alert")
    assert html =~ ~s(aria-live="assertive")
    assert html =~ "That code is not valid."
    refute html =~ "supporting-red"
  end
end
