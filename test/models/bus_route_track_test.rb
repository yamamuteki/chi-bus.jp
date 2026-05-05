require "test_helper"

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

  test "should coordinates round-trip through database as JSON" do
    bus_route_track = BusRouteTrack.create!(
      bus_route: bus_routes(:one),
      gml_id: "track-roundtrip",
      coordinates: [ [ 1.5, 2.5 ], [ 3.5, 4.5 ] ]
    )

    bus_route_track.reload
    assert_equal [ [ 1.5, 2.5 ], [ 3.5, 4.5 ] ], bus_route_track.coordinates
  end

  test "should coordinates round-trip empty array" do
    bus_route_track = BusRouteTrack.create!(
      bus_route: bus_routes(:one),
      gml_id: "track-empty",
      coordinates: []
    )

    bus_route_track.reload
    assert_equal [], bus_route_track.coordinates
  end
end
