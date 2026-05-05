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
    with_google_places_stub(spots: []) do
      get bus_stops_path, params: { q: "no hits" }
      assert_response :success
      assert_select "p", text: "検索結果はありません。"
    end
  end

  test "should get index with place query and hits" do
    spot = GooglePlacesSpot.new(
      place_id: "place_id",
      name: "name",
      lat: 1.5,
      lng: 2.5,
      formatted_address: "formatted_address"
    )

    with_google_places_stub(spots: [ spot ]) do
      get bus_stops_path, params: { q: "hits" }
      assert_response :success
      assert_select "a.list-group-item", count: 1
      assert_select "div.badge", text: "周辺"
    end
  end

  test "should get index with position" do
    get bus_stops_path, params: { position: "40.7143528,-74.0059731" }
    assert_response :success
  end

  test "should get index with malformed position falling back to 0,0" do
    # `params[:position].split(",")[0].to_f` の挙動上、不正値は (0.0, 0.0) として扱われる。
    # 例外で 500 にせず正常レスポンスを返すことを明文化する。
    get bus_stops_path, params: { position: "abc" }
    assert_response :success
  end

  test "should prefer q over position when both given" do
    get bus_stops_path, params: { q: "Stop", position: "1,1" }
    assert_response :success
    assert_select "a.list-group-item", count: 2
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

  test "should return 404 for unknown bus_stop id" do
    get bus_stop_path(id: 999_999_999)
    assert_response :not_found
  end
end
