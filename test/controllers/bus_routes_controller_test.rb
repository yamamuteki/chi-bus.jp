require "test_helper"

class BusRoutesControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get bus_route_path(bus_routes(:one))
    assert_response :success
  end

  test "should return 404 for unknown bus_route id" do
    get bus_route_path(id: 999_999_999)
    assert_response :not_found
  end
end
