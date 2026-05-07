require "test_helper"

class BusStopTest < ActiveSupport::TestCase
  test "should new" do
    assert BusStop.new
  end

  test "should have attributes" do
    bus_stop = BusStop.new
    assert_respond_to bus_stop, :gml_id
    assert_respond_to bus_stop, :name
    assert_respond_to bus_stop, :latitude
    assert_respond_to bus_stop, :longitude
    assert_respond_to bus_stop, :bus_route_bus_stops
    assert_respond_to bus_stop, :bus_routes
    assert_respond_to bus_stop, :address
    assert_respond_to bus_stop, :formatted_address
  end

  test "should address return address" do
    bus_stop = BusStop.new(formatted_address: "New York, NY, USA")
    assert_equal "New York, NY, USA", bus_stop.address
  end

  test "should formatted_address return ''" do
    assert_equal "", BusStop.new.formatted_address
  end

  test "should bus_routes order by operation_company, line_name" do
    bus_stop = BusStop.new
    bus_stop.bus_route_bus_stops << BusRouteBusStop.new(bus_route: BusRoute.new(operation_company: "2", line_name: "2"))
    bus_stop.bus_route_bus_stops << BusRouteBusStop.new(bus_route: BusRoute.new(operation_company: "2", line_name: "1"))
    bus_stop.bus_route_bus_stops << BusRouteBusStop.new(bus_route: BusRoute.new(operation_company: "1", line_name: "2"))
    bus_stop.bus_route_bus_stops << BusRouteBusStop.new(bus_route: BusRoute.new(operation_company: "1", line_name: "1"))
    bus_stop.save

    bus_stop.reload
    assert_equal "1", bus_stop.bus_routes[0].operation_company
    assert_equal "1", bus_stop.bus_routes[0].line_name
    assert_equal "1", bus_stop.bus_routes[1].operation_company
    assert_equal "2", bus_stop.bus_routes[1].line_name
    assert_equal "2", bus_stop.bus_routes[2].operation_company
    assert_equal "1", bus_stop.bus_routes[2].line_name
    assert_equal "2", bus_stop.bus_routes[3].operation_company
    assert_equal "2", bus_stop.bus_routes[3].line_name
  end

  test "should keyword search match by kanji, hiragana, katakana, and romaji" do
    bus_stop = BusStop.create!(
      name: "千葉駅",
      latitude: 35.6049233,
      longitude: 140.1208483,
      keyword: "千葉駅 chibaeki ちばえき チバエキ"
    )

    # コントローラ側で使う SQL と同じ形（lower + like）で各表記が引けることを確認する。
    [ "千葉", "chiba", "ちば", "チバ" ].each do |query|
      results = BusStop.where("lower(keyword) like lower(?)", "%#{query}%")
      assert_includes results, bus_stop, "expected query #{query.inspect} to match"
    end
  end

  test "should near return bus stops ordered by distance" do
    chibaeki = BusStop.create!(name: "千葉駅",     latitude: 35.6049233, longitude: 140.1208483)
    kaihin   = BusStop.create!(name: "海浜幕張駅", latitude: 35.6489000, longitude: 140.0337000)

    results = BusStop.near([ 35.6049233, 140.1208483 ], 50).to_a

    assert_equal chibaeki, results.first
    assert_includes results, kaihin
  end
end
