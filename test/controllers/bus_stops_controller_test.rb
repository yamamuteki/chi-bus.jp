require "test_helper"

class BusStopsControllerTest < ActionDispatch::IntegrationTest
  test "should get index with no query" do
    get bus_stops_path
    assert_response :success
    assert_select "p", text: "検索結果はありません。"
  end

  test "should get index with bus stop query and hits" do
    get bus_stops_path, params: { q: "Stop" }
    assert_response :success
    assert_select "a.list-group-item", count: 2
  end

  test "should get index with place query and no hits" do
    instance_mock = Minitest::Mock.new
    instance_mock.expect :spots_by_query, [], [ String ], lat: Float, lng: Float, radius: Integer, language: String
    class_mock = Minitest::Mock.new
    class_mock.expect :new, instance_mock, [ String ]
    GooglePlaces.send(:remove_const, :Client)
    GooglePlaces::Client = class_mock

    get bus_stops_path, params: { q: "no hits" }
    assert_response :success
    assert_select "p", text: "検索結果はありません。"
    instance_mock.verify
    class_mock.verify
  end

  test "should get index with place query and hits" do
    spot = nil
    def spot.place_id; "place_id" end
    def spot.name; "name" end
    def spot.lat; 1.5 end
    def spot.lng; 2.5 end
    def spot.formatted_address; "formatted_address" end
    def spot.place_id; "place_id" end

    instance_mock = Minitest::Mock.new
    instance_mock.expect :spots_by_query, [ spot ], [ String ], lat: Float, lng: Float, radius: Integer, language: String
    class_mock = Minitest::Mock.new
    class_mock.expect :new, instance_mock, [ String ]
    GooglePlaces.send(:remove_const, :Client)
    GooglePlaces::Client = class_mock

    get bus_stops_path, params: { q: "hits" }
    assert_response :success
    assert_select "a.list-group-item", count: 1
    assert_select "div.badge", text: "周辺"
    instance_mock.verify
    class_mock.verify
  end

  test "should get index with position" do
    get bus_stops_path, params: { position: "40.7143528,-74.0059731" }
    assert_response :success
  end

  test "should get show" do
    Geocoder::Lookup::Test.add_stub(
      "1.5,1.5", [
        {
          "latitude"     => 40.7143528,
          "longitude"    => -74.0059731,
          "address"      => "New York, NY, USA",
          "state"        => "New York",
          "state_code"   => "NY",
          "country"      => "United States",
          "country_code" => "US"
        }
      ]
    )

    get bus_stop_path(bus_stops(:one))
    assert_response :success
  end
end
