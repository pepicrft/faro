defmodule FaroWeb.StatusTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint FaroWeb.Endpoint

  test "the public root reports the server's current capabilities" do
    conn = get(build_conn(), "/")

    assert %{"agent_runtime" => "not_configured", "service" => "server"} =
             json_response(conn, 200)
  end

  test "liveness responds without exposing configuration" do
    conn = get(build_conn(), "/health/live")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "readiness verifies the configured dependencies" do
    conn = get(build_conn(), "/health/ready")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "status describes the scaffold honestly" do
    conn = get(build_conn(), "/api/v1/status")

    assert json_response(conn, 200) == %{
             "name" => "Faro",
             "service" => "server",
             "agent_runtime" => "not_configured"
           }

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "unknown routes return a JSON not-found response" do
    conn = get(build_conn(), "/api/v1/conversations")
    assert json_response(conn, 404) == %{"errors" => %{"detail" => "Not Found"}}
  end

  test "JSON errors do not expose internal exception details" do
    assert FaroWeb.ErrorJSON.render("500.json", %{reason: "private"}) == %{
             errors: %{detail: "Internal Server Error"}
           }
  end
end
