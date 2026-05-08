require "test_helper"

class BusStopsControllerTest < ActionDispatch::IntegrationTest
  test "should get index with no query" do
    get bus_stops_path
    assert_response :success
    assert_select "p", text: "検索結果はありません。"
  end

  test "should treat empty q as match-all keyword search" do
    # `if params[:q]` は空文字でも truthy なので keyword 分岐に入り、
    # `lower(keyword) like '%%'` で全件にヒットする。fixture が 2 件のため 2 件返る。
    # Google Places フォールバックには行かない（`@bus_stops.empty?` が偽）。
    get bus_stops_path, params: { q: "" }
    assert_response :success
    assert_select "a.list-group-item", count: 2
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

  test "should cache GooglePlaces results by query string" do
    # test 環境のキャッシュは :null_store で何も保持しないため、本テストの間だけ
    # memory_store に差し替えてキャッシュ動作を検証する。
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    begin
      # `with_google_places_stub` は `spots_by_query` を 1 回しか期待しない Mock を作るため、
      # 同じ q で 2 回 GET しても 2 回目はキャッシュから返って API が叩かれず、
      # 終了時の mock.verify が成功する。逆にキャッシュが効かなければ verify が失敗する。
      with_google_places_stub(spots: []) do
        get bus_stops_path, params: { q: "cached query" }
        assert_response :success

        get bus_stops_path, params: { q: "cached query" }
        assert_response :success
      end
    ensure
      Rails.cache = original_cache
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

  test "should exclude fragmented routes from bus_stop show route list" do
    Geocoder::Lookup::Test.add_stub("1.5,1.5", [ {
      "latitude" => 0, "longitude" => 0, "address" => "", "state" => "", "state_code" => "", "country" => "", "country_code" => ""
    } ])

    stop = bus_stops(:one)
    BusRouteBusStop.create!(bus_route: bus_routes(:fragmented), bus_stop: stop, bus_stop_number: 1)

    get bus_stop_path(stop)
    assert_response :success
    # fragmented 路線の line_name はリストに出ない
    assert_select "a", text: /FragmentedRoute/, count: 0
  end
end
