require 'test_helper'

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
end
