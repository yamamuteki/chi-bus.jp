require 'test_helper'

class BusStopsHelperTest < ActionView::TestCase
  include BusStopsHelper

  test "should bus_stop_or_place_path return bus_stop_path" do
    bus_stop = BusStop.new(id: 1)
    assert_equal bus_stop_path(bus_stop), bus_stop_or_place_path(bus_stop)
  end

  test "should bus_stop_or_place_path return position" do
    spot = MiniTest::Mock.new
    spot.expect :lat, 1.0
    spot.expect :lng, 2.0
    place = Place.new(spot)
    assert_equal bus_stops_path + '?position=1.0,2.0', bus_stop_or_place_path(place)
  end

  test "should bus_stop_badge return bus routes count" do
    bus_stop = BusStop.new
    assert_equal 0, bus_stop_badge(bus_stop)
    bus_stop.bus_routes << BusRoute.new
    assert_equal 1, bus_stop_badge(bus_stop)
  end

  test "should bus_stop_badge return around string" do
    spot = MiniTest::Mock.new
    place = Place.new(spot)
    assert_equal '周辺', bus_stop_badge(place)
  end
end
