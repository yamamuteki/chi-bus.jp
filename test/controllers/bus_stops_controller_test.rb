require 'test_helper'

class BusStopsControllerTest < ActionController::TestCase
  test "should get index with no query" do
    get :index
    assert_response :success
    assert assigns(:bus_stops)
  end

  test "should get index with bus stop query and hits" do
    get :index, { q: 'Stop' }
    assert_response :success
    bus_stops = assigns(:bus_stops)
    assert bus_stops
    assert_equal 2, bus_stops.length
  end

  test "should get index with place query and no hits" do
    instance_mock = MiniTest::Mock.new
    instance_mock.expect :spots_by_query, [], [String, Hash]
    class_mock = MiniTest::Mock.new
    class_mock.expect :new, instance_mock, [String]
    GooglePlaces.send(:remove_const, :Client)
    GooglePlaces::Client = class_mock

    get :index, { q: 'no hits' }
    assert_response :success
    bus_stops = assigns(:bus_stops)
    assert bus_stops
    assert_equal 0, bus_stops.length
  end

  test "should get index with place query and hits" do
    spot = MiniTest::Mock.new
    spot.expect :place_id, 'place_id'
    spot.expect :name, 'name'
    spot.expect :lat, 1.5
    spot.expect :lng, 2.5
    spot.expect :name, 'name'
    spot.expect :lat, 1.5
    spot.expect :lng, 2.5
    spot.expect :lat, 1.5
    spot.expect :lng, 2.5
    spot.expect :place_id, 'place_id'
    spot.expect :name, 'name'
    spot.expect :formatted_address, 'formatted_address'

    instance_mock = MiniTest::Mock.new
    instance_mock.expect :spots_by_query, [spot], [String, Hash]
    class_mock = MiniTest::Mock.new
    class_mock.expect :new, instance_mock, [String]
    GooglePlaces.send(:remove_const, :Client)
    GooglePlaces::Client = class_mock

    get :index, { q: 'hits' }
    assert_response :success
    bus_stops = assigns(:bus_stops)
    assert bus_stops
    assert_equal 1, bus_stops.length
    assert_instance_of Place, bus_stops[0]
  end

  test "should get index with position" do
    get :index, { position: '40.7143528,-74.0059731' }
    assert_response :success
    assert assigns(:bus_stops)
  end

  test "should get show" do
    Geocoder::Lookup::Test.add_stub(
      "1.5,1.5", [
        {
          'latitude'     => 40.7143528,
          'longitude'    => -74.0059731,
          'address'      => 'New York, NY, USA',
          'state'        => 'New York',
          'state_code'   => 'NY',
          'country'      => 'United States',
          'country_code' => 'US'
        }
      ]
    )

    get :show, { id: bus_stops(:one) }
    assert_response :success
    assert assigns(:bus_stop)
  end
end
