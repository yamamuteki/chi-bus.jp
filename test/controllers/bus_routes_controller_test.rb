require "test_helper"

class BusRoutesControllerTest < ActionDispatch::IntegrationTest
  test "should get show" do
    get bus_route_path(bus_routes(:one))
    assert_response :success
  end
end
