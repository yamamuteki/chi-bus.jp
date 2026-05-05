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

  test "should list bus_stops in bus_stop_number order" do
    route = bus_routes(:one)
    later   = BusStop.create!(name: "Later Stop",   latitude: 1.0, longitude: 1.0)
    earlier = BusStop.create!(name: "Earlier Stop", latitude: 2.0, longitude: 2.0)
    # 作成順は逆だが、bus_stop_number 順で並ぶことを期待する。
    BusRouteBusStop.create!(bus_route: route, bus_stop: later,   bus_stop_number: 2)
    BusRouteBusStop.create!(bus_route: route, bus_stop: earlier, bus_stop_number: 1)

    get bus_route_path(route)
    assert_response :success

    body = @response.body
    assert body.index("Earlier Stop") < body.index("Later Stop"),
      "Earlier Stop should appear before Later Stop in bus_stop_number order"
  end
end
