require "test_helper"

class BusRouteBusStopTest < ActiveSupport::TestCase
  test "should new" do
    assert BusRouteBusStop.new
  end

  test "should have attributes" do
    bus_route_bus_stop = BusRouteBusStop.new
    assert_respond_to bus_route_bus_stop, :bus_stop_number
    assert_respond_to bus_route_bus_stop, :bus_route
    assert_respond_to bus_route_bus_stop, :bus_stop
  end

  test "should require bus_route" do
    brbs = BusRouteBusStop.new(bus_stop: bus_stops(:one), bus_stop_number: 1)
    refute brbs.valid?
    assert_includes brbs.errors[:bus_route], "must exist"
  end

  test "should require bus_stop" do
    brbs = BusRouteBusStop.new(bus_route: bus_routes(:one), bus_stop_number: 1)
    refute brbs.valid?
    assert_includes brbs.errors[:bus_stop], "must exist"
  end
end
