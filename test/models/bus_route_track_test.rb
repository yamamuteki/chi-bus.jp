require 'test_helper'

class BusRouteTrackTest < ActiveSupport::TestCase
  test "should new" do
    assert BusRouteTrack.new
  end

  test "should have attributes" do
    bus_route_track = BusRouteTrack.new
    assert_respond_to bus_route_track, :gml_id
    assert_respond_to bus_route_track, :coordinates
    assert_respond_to bus_route_track, :bus_route
  end

  test "shoud coordinates serialize to JSON" do
    bus_route_track = BusRouteTrack.new

    bus_route_track.coordinates = []
    assert_equal '[]', bus_route_track.coordinates.inspect
    assert_not_equal '"[]"', bus_route_track.coordinates.inspect

    bus_route_track.gml_id = []
    assert_equal '"[]"', bus_route_track.gml_id.inspect
    assert_not_equal '[]', bus_route_track.gml_id.inspect
  end
end
