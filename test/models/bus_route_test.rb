require 'test_helper'

class BusRouteTest < ActiveSupport::TestCase
  test "should new" do
    assert BusRoute.new
  end

  test "should have attributes" do
    bus_route = BusRoute.new
    assert_respond_to bus_route, :bus_type
    assert_respond_to bus_route, :operation_company
    assert_respond_to bus_route, :line_name
    assert_respond_to bus_route, :weekday_rate
    assert_respond_to bus_route, :saturday_rate
    assert_respond_to bus_route, :holiday_rate
    assert_respond_to bus_route, :note
    assert_respond_to bus_route, :bus_route_tracks
    assert_respond_to bus_route, :bus_route_bus_stops
    assert_respond_to bus_route, :bus_stops
  end

  test "should bus_type_label return" do
    bus_route = BusRoute.new
    assert_equal nil, bus_route.bus_type_label
    bus_route.bus_type = 1; assert_equal '路線バス（民間）', bus_route.bus_type_label
    bus_route.bus_type = 2; assert_equal '路線バス（公営）', bus_route.bus_type_label
    bus_route.bus_type = 3; assert_equal 'コミュニティバス', bus_route.bus_type_label
    bus_route.bus_type = 4; assert_equal 'デマンドバス', bus_route.bus_type_label
    bus_route.bus_type = 5; assert_equal 'その他', bus_route.bus_type_label
  end

  test "should bus_route_bus_stops order by bus_stop_number" do
    bus_route = BusRoute.new
    bus_route.bus_route_bus_stops << BusRouteBusStop.new(bus_stop_number: 2, bus_stop: BusStop.new(name: '2'))
    bus_route.bus_route_bus_stops << BusRouteBusStop.new(bus_stop_number: 1, bus_stop: BusStop.new(name: '1'))
    assert_equal 2, bus_route.bus_route_bus_stops[0].bus_stop_number
    assert_equal 1, bus_route.bus_route_bus_stops[1].bus_stop_number
    bus_route.save

    bus_route.reload
    assert_equal 1, bus_route.bus_route_bus_stops[0].bus_stop_number
    assert_equal 2, bus_route.bus_route_bus_stops[1].bus_stop_number
    assert_equal '1', bus_route.bus_stops[0].name
    assert_equal '2', bus_route.bus_stops[1].name
  end
end
