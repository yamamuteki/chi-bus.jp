require 'test_helper'
require 'minitest/mock'

class PlaceTest < ActiveSupport::TestCase
  test "should new" do
    assert Place.new nil
  end

  test "should have attributes" do
    spot = MiniTest::Mock.new
    spot.expect :place_id, 'place_id'
    spot.expect :name, 'name'
    spot.expect :lat, 1.0
    spot.expect :lng, 2.0
    spot.expect :formatted_address, 'formatted_address'

    place = Place.new spot
    assert_equal 'place_id', place.id
    assert_equal 'name', place.name
    assert_equal 1.0, place.latitude
    assert_equal 2.0, place.longitude
    assert_equal 'formatted_address', place.formatted_address
    assert spot === place.spot
    assert spot.verify
  end
end
